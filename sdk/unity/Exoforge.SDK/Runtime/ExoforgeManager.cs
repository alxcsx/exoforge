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
    /// <see cref="Instance"/> or <c>await ExoforgeManager.Instance.GetClientAsync()</c> from
    /// game code — no connection configuration belongs in gameplay scripts.
    /// </summary>
    [DefaultExecutionOrder(-1000)]
    public class ExoforgeManager : MonoBehaviour
    {
        private static ExoforgeManager? _instance;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
        private static void ResetStaticState()
        {
            _instance = null;
        }

        /// <summary>The active instance, or null when no Exoforge prefab is in the scene.</summary>
        public static ExoforgeManager? Current => _instance;

        /// <summary>The active instance; throws a clear error when the prefab is missing.</summary>
        public static ExoforgeManager Instance =>
            _instance != null
                ? _instance
                : throw new InvalidOperationException(
                    "No ExoforgeManager in the scene. Add the Exoforge prefab (Exoforge SDK) to bootstrap the client.");

        [Header("Configuration")]
        [Tooltip("Optional workspace config (exoforge.json). Empty loads Resources/exoforge.json.")]
        [SerializeField] private TextAsset? workspaceConfig;

        [Tooltip("Optional WebSocket endpoint override. Empty uses the workspace config.")]
        [SerializeField] private string wsUrlOverride = "";

        [Tooltip("Connect as soon as the scene loads.")]
        [SerializeField] private bool connectOnAwake = true;

        [Header("Session")]
        [Tooltip(
            "In the editor, play as the account the Exoforge Studio window is signed in as, instead of " +
            "this device's own session. Play mode then shares the Studio's player - the same leaderboard " +
            "rows and the same player data - and no anonymous account is minted for the editor. " +
            "A build has no Studio window, so it falls back to the device's own session.")]
        [SerializeField] private bool useStudioConnection = true;

        [Header("Reconnect")]
        [Tooltip("Reconnect automatically when the connection drops.")]
        [SerializeField] private bool autoReconnect = true;

        [Tooltip("First retry delay; doubles each attempt up to the maximum.")]
        [SerializeField] private float reconnectBaseDelay = 1f;

        [Tooltip("Longest delay between reconnect attempts.")]
        [SerializeField] private float reconnectMaxDelay = 30f;

        private Task? _pendingConnect;
        private ExoClient? _client;
        private ExoforgeRuntimeConfig? _resolvedConfig;
        private bool _configResolved;
        private readonly SemaphoreSlim _connectGate = new(1, 1);
        private CancellationTokenSource? _reconnectCts;
        private int _reconnectAttempt;

        /// <summary>
        /// The client, built on demand from the workspace config.
        ///
        /// Built without connecting, because a request/response action over HTTP needs no socket and
        /// most of a game's calls are exactly that. The socket is opened by <see cref="GetClientAsync"/>
        /// when something actually needs one.
        /// </summary>
        public ExoClient? Client
        {
            get
            {
                if (_client == null && Config != null)
                {
                    _client = CreateClient();
                }

                return _client;
            }
        }

        /// <summary>True once the transport is connected.</summary>
        public bool IsConnected => Client?.IsConnected ?? false;

        /// <summary>True once the transport is connected and a session is authenticated.</summary>
        public bool IsReady => Client != null && Client.IsConnected && Client.IsAuthenticated;

        /// <summary>The resolved workspace config, or null when none is linked.</summary>
        public ExoforgeRuntimeConfig? Config
        {
            get
            {
                if (_configResolved)
                {
                    return _resolvedConfig;
                }

                var asset = workspaceConfig != null
                    ? workspaceConfig
                    : Resources.Load<TextAsset>(ExoforgeRuntimeConfig.ResourcePath);

                if (asset != null)
                {
                    _resolvedConfig = ExoforgeRuntimeConfig.FromWorkspaceJson(asset.text);
                }

                _configResolved = true;
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

            // Resolved here, on the main thread, once — so no background thread ever loads a
            // resource (M33 Fix 15).
            _ = Config;

            // Decided before anything connects: the session this run reads is either the Studio's or
            // the device's own.
            ExoTokenStore.UseStudioSession = useStudioConnection;

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
            // One at a time (M33 Fix 21): two callers racing the check-then-assign below each
            // started a connect, and one disposed the client the other was authenticating on.
            await _connectGate.WaitAsync().ConfigureAwait(false);

            try
            {
                // Await any connect already in flight before handing out a client. Short-circuiting on
                // IsConnected alone returned a client that was connected but still authenticating, so a
                // second caller authenticated on the same socket and one of them lost it with
                // "Disconnected from server".
                if (_pendingConnect == null)
                {
                    if (Client is { IsConnected: true })
                    {
                        return Client;
                    }

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
            }
            finally
            {
                _connectGate.Release();
            }

            return Client is { IsConnected: true }
                ? Client
                : throw new InvalidOperationException("Exoforge is not connected. See the console for details.");
        }

        /// <summary>
        /// Builds a client pointed at the workspace's HTTP endpoint. Kept separate from connecting so
        /// HTTP actions work with no socket open.
        /// </summary>
        private ExoClient CreateClient()
        {
            var cfg = Config;
            var client = new ExoClient();

            if (!string.IsNullOrEmpty(cfg?.HttpUrl))
            {
                client.HttpBaseUri = new Uri(cfg!.HttpUrl);
            }

            client.OnDisconnected += OnClientDisconnected;

            // What makes the connection lazy: the client asks for a socket only when an operation
            // needs one - a subscription, or an action the contract declared as WebSocket.
            client.EnsureConnected = async () => { await GetClientAsync().ConfigureAwait(false); };
            return client;
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
                // Reuse the client when the endpoint has not changed. Recreating it would invalidate
                // the reference game code is holding from ExoforgeSDK.Client, which is now handed out
                // before anything connects.
                if (_client == null || url != null || token != null)
                {
                    _client?.Dispose();
                    _client = CreateClient();
                }

                await Client!.ConnectAsync(new Uri(targetUrl));

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
        /// <summary>
        /// Closes the socket and stops reconnecting, leaving the client usable over HTTP. The socket
        /// is opened again on demand by <see cref="GetClientAsync"/>.
        ///
        /// For a scene that does not use realtime - a long match, with the events living in the menus -
        /// this releases the connection instead of holding an idle socket for its whole duration.
        /// </summary>
        public async Task DisconnectAsync()
        {
            // Stop the reconnect loop first: leaving it running would immediately undo this.
            _reconnectCts?.Cancel();
            _reconnectCts = null;
            _reconnectAttempt = 0;

            if (_client == null)
            {
                return;
            }

            try
            {
                await _client.DisconnectAsync().ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                Debug.LogWarning($"[Exoforge] Disconnect failed: {ex.Message}");
            }
        }

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

                    // GetClientAsync, not ConnectAsync: it shares the single in-flight connect with
                    // every other caller. Calling ConnectAsync directly here disposed and replaced
                    // the client underneath a game-side call doing the same thing.
                    try
                    {
                        await GetClientAsync().ConfigureAwait(false);
                    }
                    catch (InvalidOperationException)
                    {
                        // ConnectAsync already logged why. Back off and try again.
                    }
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

        private void OnDestroy()
        {
            // Before anything can await: leaving this set meant Current/Instance kept returning a
            // destroyed object, so game code got a MissingReferenceException instead of the
            // "no ExoforgeManager in the scene" message this class is careful to give.
            if (_instance == this)
            {
                _instance = null;
            }

            _reconnectCts?.Cancel();
            _reconnectCts = null;

            // The private field, not the property (M33 Fix 16): reading `Client` here would lazily
            // create a fresh client just in time to dispose it.
            var client = _client;
            _client = null;

            if (client == null)
            {
                return;
            }

            // Not `async void` (M33 Fix 16): a teardown that raced the await surfaced its exception
            // on a destroyed behaviour. The close runs against the client, which outlives this
            // object, and disposes it when done.
            _ = Task.Run(async () =>
            {
                try
                {
                    await client.DisconnectAsync();
                }
                catch (Exception ex)
                {
                    Debug.LogWarning($"[Exoforge] Disconnect during teardown failed: {ex.Message}");
                }
                finally
                {
                    client.Dispose();
                }
            });
        }
    }
}
