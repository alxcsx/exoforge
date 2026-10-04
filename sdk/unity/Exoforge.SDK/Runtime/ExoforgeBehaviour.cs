using System;
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

        private Task? _pendingConnect;
        private ExoforgeRuntimeConfig? _resolvedConfig;

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
            if (IsReady)
            {
                return Client!;
            }

            if (_pendingConnect == null)
            {
                _pendingConnect = ConnectAsync();
            }

            await _pendingConnect;

            return Client != null && Client.IsConnected
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

                return true;
            }
            catch (Exception ex)
            {
                Debug.LogError($"[Exoforge] Connection error: {ex.Message}");
                return false;
            }
        }

        private void Update()
        {
            Client?.Dispatcher.Update();
        }

        private async void OnDestroy()
        {
            if (Client != null)
            {
                await Client.DisconnectAsync();
                Client.Dispose();
            }
        }
    }
}
