using System;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;
using Exoforge.Client;
using UnityEngine;

namespace Exoforge.Client.Unity
{
    /// <summary>
    /// The SDK entry point for game code.
    ///
    /// <code>
    /// var session = await ExoforgeSDK.Auth.LoginAnonymously("Viper");
    /// var board   = await ExoforgeSDK.Client.SnakeLeaderboard().GetLeaderboardAsync(10);
    /// </code>
    ///
    /// Connection and dispatcher pumping live in <see cref="ExoforgeManager"/>, which is created
    /// on demand if no Exoforge prefab is in the scene — game code never has to place one.
    /// </summary>
    public static class ExoforgeSDK
    {
        private static ExoforgeAuth? _auth;
        private static SynchronizationContext? _mainContext;
        private static int _mainThreadId;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
        private static void ResetSubsystem()
        {
            _auth = null;
            _mainContext = null;
            _mainThreadId = 0;
        }

#if UNITY_EDITOR
        [UnityEditor.InitializeOnLoadMethod]
#endif
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
        private static void CaptureMainThread()
        {
            _mainContext = SynchronizationContext.Current;
            _mainThreadId = Environment.CurrentManagedThreadId;
            try { ExoDeviceId.Get(); } catch { }
            try { WireExoServicesLocator(); } catch { }
        }

        /// <summary>
        /// Auto-wires the static ExoServices.Client and Exo.Client facade to this ambient SDK client.
        /// </summary>
        internal static void WireExoServicesLocator()
        {
            try
            {
                foreach (var asm in AppDomain.CurrentDomain.GetAssemblies())
                {
                    var exoServicesType = asm.GetType("Exoforge.Client.ExoServices");
                    if (exoServicesType != null)
                    {
                        var setLocator = exoServicesType.GetMethod("SetClientLocator", BindingFlags.Public | BindingFlags.Static);
                        if (setLocator != null)
                        {
                            Func<ExoClient> locator = () => Client;
                            setLocator.Invoke(null, new object[] { locator });
                        }
                    }
                }
            }
            catch { }
        }

        /// <summary>
        /// Player sign-in and session management.
        /// <para>
        /// In Unity games, ALWAYS use this property (<c>ExoforgeSDK.Auth.LoginAnonymously()</c> or <c>ExoforgeSDK.Auth.LoginWithEmail()</c>)
        /// rather than calling raw RPCs on <c>ExoServices.Auth.AnonymousAsync()</c> or <c>ExoforgeSDK.Client.Services().Auth.AnonymousAsync()</c>.
        /// <c>ExoforgeSDK.Auth</c> automatically mints and caches the stable device ID, manages <c>ExoTokenStore</c> persistence,
        /// and configures the ambient authenticated player session.
        /// </para>
        /// </summary>
        public static ExoforgeAuth Auth => _auth ??= new ExoforgeAuth();

        /// <summary>Task that completes when the client has established connection and authenticated.</summary>
        public static Task Ready => Behaviour.ReadyTask;

        /// <summary>True once the client has connected and authenticated.</summary>
        public static bool IsReady => Behaviour.IsReady;

        /// <summary>Event that fires when Exoforge is connected and ready to send actions.</summary>
        public static event Action? OnReady
        {
            add
            {
                if (IsReady)
                {
                    value?.Invoke();
                }
                ExoforgeManager.OnReady += value;
            }
            remove => ExoforgeManager.OnReady -= value;
        }

        /// <summary>Current cluster connection state.</summary>
        public static ExoforgeConnectionState State => Behaviour.CurrentState;

        /// <summary>Event that fires on connection state transitions.</summary>
        public static event Action<ExoforgeConnectionState>? StateChanged
        {
            add => ExoforgeManager.OnStateChanged += value;
            remove => ExoforgeManager.OnStateChanged -= value;
        }

        /// <summary>
        /// The client. Usable with or without a socket: an action over HTTP needs no connection.
        /// Use it with the generated service extensions
        /// (<c>Client.PlayerData()</c>, <c>Client.SnakeLeaderboard()</c>, …).
        /// </summary>
        public static ExoClient Client
        {
            get
            {
                var client = Behaviour.Client is { CanSendActions: true } c
                    ? c
                    : throw new InvalidOperationException(
                        "Exoforge has no transport. Link the workspace config, or call ExoforgeSDK.ConnectAsync().");
                try { WireExoServicesLocator(); } catch { }
                return client;
            }
        }

        /// <summary>
        /// The last 50 calls this session made, as JSON. Paste it into a bug report: every entry
        /// carries the server's request id, which the Studio timeline joins to the whole request.
        /// </summary>
        public static string ExportDiagnostics() => ExoClient.ExportDiagnostics();

        /// <summary>Connects to the cluster (idempotent) and returns the client.</summary>
        public static async Task<ExoClient> ConnectAsync()
        {
            var client = await Behaviour.GetClientAsync();
            try { WireExoServicesLocator(); } catch { }
            return client;
        }

        /// <summary>
        /// Closes the socket and stops reconnecting. Actions that do not need one keep working over
        /// HTTP, and the socket is opened again on demand.
        ///
        /// For a scene that does not use realtime at all - a match that runs for forty minutes while
        /// the menus are where the events live - this releases the connection instead of holding an
        /// idle socket for the whole match.
        /// </summary>
        public static Task DisconnectAsync() => Behaviour.DisconnectAsync();

        private static ExoforgeManager Behaviour
        {
            get
            {
                if (ExoforgeManager.Current != null)
                {
                    return ExoforgeManager.Current;
                }

                if (_mainThreadId == 0 || Environment.CurrentManagedThreadId == _mainThreadId || _mainContext == null)
                {
                    return CreateOrFindHost();
                }

                ExoforgeManager? manager = null;
                _mainContext.Send(_ =>
                {
                    manager = ExoforgeManager.Current ?? CreateOrFindHost();
                }, null);

                return manager ?? throw new InvalidOperationException("Failed to initialize ExoforgeManager on main thread.");
            }
        }

        private static ExoforgeManager CreateOrFindHost()
        {
            var existing = UnityEngine.Object.FindAnyObjectByType<ExoforgeManager>(FindObjectsInactive.Include);
            if (existing != null)
            {
                ExoforgeManager.Current = existing;
                return existing;
            }

            var host = new GameObject("[ExoforgeSDK]");
            var created = host.AddComponent<ExoforgeManager>();
            ExoforgeManager.Current = created;
            return created;
        }
    }

    /// <summary>
    /// Modern static entry point for Exoforge gameplay code.
    ///
    /// <code>
    /// await Exoforge.Ready;
    /// var response = await Exoforge.Client.DailyRewards().ClaimDailyRewardAsync(new() { Level = 1 });
    /// if (response.Success)
    /// {
    ///     Debug.Log($"Claimed {response.Reward.Amount} {response.Reward.Kind}!");
    /// }
    /// </code>
    /// </summary>
    public static class Exoforge
    {
        /// <summary>Task that completes when Exoforge is connected and authenticated.</summary>
        public static Task Ready => ExoforgeSDK.Ready;

        /// <summary>True once Exoforge has connected and authenticated.</summary>
        public static bool IsReady => ExoforgeSDK.IsReady;

        /// <summary>Event that fires when Exoforge is connected and ready to send actions.</summary>
        public static event Action? OnReady
        {
            add => ExoforgeSDK.OnReady += value;
            remove => ExoforgeSDK.OnReady -= value;
        }

        /// <summary>Current cluster connection state.</summary>
        public static ExoforgeConnectionState State => ExoforgeSDK.State;

        /// <summary>The active client for invoking extension actions.</summary>
        public static ExoClient Client => ExoforgeSDK.Client;

        /// <summary>Player and session authentication facade.</summary>
        public static ExoforgeAuth Auth => ExoforgeSDK.Auth;

        /// <summary>Connects to the cluster (idempotent) and returns the client.</summary>
        public static Task<ExoClient> ConnectAsync() => ExoforgeSDK.ConnectAsync();

        /// <summary>Closes the socket and releases realtime resources.</summary>
        public static Task DisconnectAsync() => ExoforgeSDK.DisconnectAsync();

        /// <summary>The last 50 calls this session made, as JSON, for a bug report.</summary>
        public static string ExportDiagnostics() => ExoforgeSDK.ExportDiagnostics();

        /// <summary>Event that fires on connection state transitions.</summary>
        public static event Action<ExoforgeConnectionState>? StateChanged
        {
            add => ExoforgeSDK.StateChanged += value;
            remove => ExoforgeSDK.StateChanged -= value;
        }
    }
}
