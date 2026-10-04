using System;
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
    /// Connection and dispatcher pumping live in <see cref="ExoforgeBehaviour"/>, which is created
    /// on demand if no Exoforge prefab is in the scene — game code never has to place one.
    /// </summary>
    public static class ExoforgeSDK
    {
        private static ExoforgeAuth? _auth;

        /// <summary>Player sign-in.</summary>
        public static ExoforgeAuth Auth => _auth ??= new ExoforgeAuth();

        /// <summary>
        /// The connected client. Use it with the generated service extensions
        /// (<c>Client.PlayerData()</c>, <c>Client.SnakeLeaderboard()</c>, …).
        /// </summary>
        public static ExoClient Client =>
            Behaviour.Client ?? throw new InvalidOperationException("Call ExoforgeSDK.ConnectAsync() first.");

        /// <summary>Connects to the cluster (idempotent) and returns the client.</summary>
        public static Task<ExoClient> ConnectAsync() => Behaviour.GetClientAsync();

        private static ExoforgeBehaviour Behaviour
        {
            get
            {
                if (ExoforgeBehaviour.Current != null)
                {
                    return ExoforgeBehaviour.Current;
                }

                // No prefab in the scene: create the runtime host on demand.
                var host = new GameObject("[ExoforgeSDK]");
                return host.AddComponent<ExoforgeBehaviour>();
            }
        }
    }
}
