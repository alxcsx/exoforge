using System;
using System.Threading;
using System.Threading.Tasks;
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

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]
        private static void CaptureMainThread()
        {
            _mainContext = SynchronizationContext.Current;
            _mainThreadId = Environment.CurrentManagedThreadId;
        }

        /// <summary>Player sign-in.</summary>
        public static ExoforgeAuth Auth => _auth ??= new ExoforgeAuth();

        /// <summary>
        /// The client. Usable with or without a socket: an action over HTTP needs no connection.
        /// Use it with the generated service extensions
        /// (<c>Client.PlayerData()</c>, <c>Client.SnakeLeaderboard()</c>, …).
        /// </summary>
        public static ExoClient Client =>
            Behaviour.Client is { CanSendActions: true } client
                ? client
                : throw new InvalidOperationException(
                    "Exoforge has no transport. Link the workspace config, or call ExoforgeSDK.ConnectAsync().");

        /// <summary>Connects to the cluster (idempotent) and returns the client.</summary>
        public static Task<ExoClient> ConnectAsync() => Behaviour.GetClientAsync();

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
                return existing;
            }

            var host = new GameObject("[ExoforgeSDK]");
            return host.AddComponent<ExoforgeManager>();
        }
    }
}
