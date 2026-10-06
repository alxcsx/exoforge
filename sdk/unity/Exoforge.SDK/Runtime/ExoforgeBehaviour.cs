using System;
using System.Threading;
using System.Threading.Tasks;
using UnityEngine;

namespace Exoforge.Client.Unity
{

    /// <summary>
    /// Unity entry point for Exoforge. Owns the <see cref="ExoClient"/> lifecycle, resolves
    /// connection settings from the workspace <c>exoforge.json</c> (linked into
    /// <c>Resources/exoforge.json</c> by the Exoforge Editor tools), authenticates via
    /// <see cref="ExoTokenStore"/>, and pumps the dispatcher on the main thread.
    ///
    /// Drop the standard <c>Exoforge</c> prefab into a scene, then read
    /// <see cref="Instance"/> or <c>await ExoforgeBehaviour.Instance.GetClientAsync()</c> from
    /// game code — no connection configuration belongs in gameplay scripts.
    /// </summary>
    [DefaultExecutionOrder(-1000)]
    public class ExoforgeBehaviour : MonoBehaviour
    {
        private static ExoforgeBehaviour? _instance;

        /// <summary>The active instance, or null when no Exoforge prefab is in the scene.</summary>
        public static ExoforgeBehaviour? Current => _instance;

        /// <summary>The active instance; throws a clear error when the prefab is missing.</summary>
        public static ExoforgeBehaviour Instance =>
            _instance != null
                ? _instance
                : throw new InvalidOperationException(
                    "No ExoforgeBehaviour in the scene. Add the Exoforge prefab (Exoforge SDK) to bootstrap the client.");

        [Header("Configuration")]
        [Tooltip("Optional workspace config (exoforge.json). Empty loads Resources/exoforge.json.")]
        [SerializeField] private TextAsset? workspaceConfig;

        [Tooltip("Optional WebSocket endpoint override. Empty uses the workspace config.")]
        [SerializeField] private string wsUrlOverride = "";

        [Tooltip("Connect as soon as the scene loads.")]
        [SerializeField] private bool connectOnAwake = true;

        [Header("Reconnect")]
        [Tooltip("Reconnect automatically when the connection drops.")]
        [SerializeField] private bool autoReconnect = true;

        [Tooltip("First retry delay; doubles each attempt up to the maximum.")]
        [SerializeField] private float reconnectBaseDelay = 1f;

        [Tooltip("Longest delay between reconnect attempts.")]
        [SerializeField] private float reconnectMaxDelay = 30f;

        private Task? _pendingConnect;
        private ExoforgeRuntimeConfig? _resolvedConfig;
        private CancellationTokenSource? _reconnectCts;
        private int _reconnectAttempt;

        /// <summary>The live client, or null before the first connection attempt.</summary>
        public ExoClient? Client { get; private set; }

        /// <summary>True once the transport is connected.</summary>
        public bool IsConnected => Client?.IsConnected ?? false;

        /// <summary>True once the transport is connected and a session is authenticated.</summary>
        public bool IsReady => Client != null && Client.IsConnected && Client.IsAuthenticated;

        /// <summary>The resolved workspace config, or null when none is linked.</summary>
        public ExoforgeRuntimeConfig? Config
        {
            get
            {
                if (_resolvedConfig != null)
                {
                    return _resolvedConfig;
                }

                var asset = workspaceConfig != null
                    ? workspaceConfig
                    : Resources.Load<TextAsset>(ExoforgeRuntimeConfig.ResourcePath);

                if (asset == null)
                {
                    return null;
                }

                _resolvedConfig = ExoforgeRuntimeConfig.FromWorkspaceJson(asset.text);
                return _resolvedConfig;
            }
        }

        private void Awake()
        {
            if (_instance != null && _instance != this)
            {
                Destroy(gameObject);
                return;
            }

            _instance = this;
            DontDestroyOnLoad(gameObject);

            if (connectOnAwake)
            {
                _pendingConnect = ConnectAsync();
            }
        }

        /// <summary>
        /// Returns a connected client, awaiting an in-flight connection or starting one.
        /// Game code should prefer this over touching the client directly.
        /// </summary>
        public async Task<ExoClient> GetClientAsync()
        {
            if (Client is { IsConnected: true })
            {
                return Client;
            }

            if (_pendingConnect == null)
            {
                _pendingConnect = ConnectAsync();
            }

            try
            {
                await _pendingConnect;
            }
            finally
            {
                // Cleared either way. On success the guard above short-circuits the next call; on
                // failure the next call has to be allowed to try again. Leaving this set made a
                // failed connection permanent — the backend being down at boot meant the game could
                // never connect, and every later call awaited the same finished task.
                _pendingConnect = null;
            }

            return Client is { IsConnected: true }
                ? Client
                : throw new InvalidOperationException("Exoforge is not connected. See the console for details.");
        }

        /// <summary>Connects to the cluster and authenticates with the stored or configured token.</summary>
        public async Task<bool> ConnectAsync(string? url = null, string? token = null)
        {
            var cfg = Config;

            string targetUrl =
                !string.IsNullOrEmpty(url) ? url!
                : !string.IsNullOrEmpty(wsUrlOverride) ? wsUrlOverride
                : cfg?.WsUrl ?? "";

            if (string.IsNullOrEmpty(targetUrl))
            {
                Debug.LogError("[Exoforge] No WebSocket URL. Sync the runtime config or set an override.");
                return false;
            }

            string? targetToken =
                token
                ?? (ExoTokenStore.HasToken ? ExoTokenStore.Token : null)
                ?? (string.IsNullOrEmpty(cfg?.Token) ? null : cfg!.Token);

            try
            {
                Client?.Dispose();
                Client = new ExoClient();
                Client.OnDisconnected += OnClientDisconnected;

                if (!string.IsNullOrEmpty(cfg?.HttpUrl))
                {
                    Client.HttpBaseUri = new Uri(cfg!.HttpUrl);
                }

                await Client.ConnectAsync(new Uri(targetUrl));

                if (!string.IsNullOrEmpty(targetToken))
                {
                    var auth = await Client.AuthenticateAsync(targetToken);
                    if (auth.IsSuccess)
                    {
                        ExoTokenStore.SaveSession(targetToken, auth.PlayerId, auth.Scopes);
                        Debug.Log($"[Exoforge] Connected and authenticated as {auth.PlayerId} ({cfg?.Environment ?? "?"})");
                    }
                    else
                    {
                        Debug.LogWarning($"[Exoforge] Connected, but authentication failed: {auth.Error}");
                    }
                }
                else
                {
                    Debug.Log($"[Exoforge] Connected to {targetUrl} (unauthenticated)");
                }

                _reconnectAttempt = 0;
                return true;
            }
            catch (Exception ex)
            {
                Debug.LogError($"[Exoforge] Connection error: {ex.Message}");

                // A backend that is not up yet is the common case at boot, so retry from a failed
                // first attempt too, not only from a dropped connection.
                StartReconnecting();

                return false;
            }
        }

        private void Update()
        {
            Client?.Dispatcher.Update();
        }

        /// <summary>
        /// Starts the retry loop when the connection drops.
        ///
        /// Deliberately a background task rather than something driven from <see cref="Update"/>:
        /// disconnect notifications are themselves delivered through the dispatcher, so a behaviour
        /// that stops pumping — disabled, or destroyed mid-teardown — would never reconnect.
        /// </summary>
        private void OnClientDisconnected(Exception? error) => StartReconnecting();

        private void StartReconnecting()
        {
            if (!autoReconnect || _reconnectCts != null)
            {
                return;
            }

            var cts = new CancellationTokenSource();
            _reconnectCts = cts;
            _ = Task.Run(() => ReconnectLoopAsync(cts.Token), CancellationToken.None);
        }

        private async Task ReconnectLoopAsync(CancellationToken cancellationToken)
        {
            try
            {
                while (!cancellationToken.IsCancellationRequested && !IsReady)
                {
                    TimeSpan delay = ExoBackoff.Delay(_reconnectAttempt, reconnectBaseDelay, reconnectMaxDelay);

                    _reconnectAttempt++;

                    Debug.LogWarning($"[Exoforge] Not connected. Retrying in {delay.TotalSeconds:0.#}s (attempt {_reconnectAttempt}).");

                    await Task.Delay(delay, cancellationToken).ConfigureAwait(false);

                    if (cancellationToken.IsCancellationRequested)
                    {
                        return;
                    }

                    // ConnectAsync reports its own failure and returns false; the loop backs off and
                    // tries again until it succeeds or the behaviour goes away.
                    await ConnectAsync().ConfigureAwait(false);
                }
            }
            catch (OperationCanceledException)
            {
                // The behaviour is going away.
            }
            finally
            {
                _reconnectCts = null;
            }
        }

        private async void OnDestroy()
        {
            // Before anything can await: leaving this set meant Current/Instance kept returning a
            // destroyed object, so game code got a MissingReferenceException instead of the
            // "no ExoforgeBehaviour in the scene" message this class is careful to give.
            if (_instance == this)
            {
                _instance = null;
            }

            _reconnectCts?.Cancel();
            _reconnectCts = null;

            if (Client == null)
            {
                return;
            }

            try
            {
                await Client.DisconnectAsync();
            }
            catch (Exception ex)
            {
                Debug.LogWarning($"[Exoforge] Disconnect during teardown failed: {ex.Message}");
            }
            finally
            {
                Client.Dispose();
            }
        }
    }
}
