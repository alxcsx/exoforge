using System;
using Exoforge.Client.Unity;
using UnityEngine;

namespace SnakeGame
{
    /// <summary>
    /// Signs the player in on start and hands the session to gameplay.
    ///
    /// The whole flow is one SDK call — <see cref="ExoforgeSDK.Auth"/> re-uses the account this
    /// machine already registered, or creates and names a new one. Gameplay reads
    /// <see cref="Session"/> and subscribes to <see cref="SessionReady"/>; it never touches tokens.
    /// </summary>
    [DefaultExecutionOrder(-800)]
    public class SnakePlayerController : MonoBehaviour
    {
        [Header("Player")]
        [Tooltip("Display name for a new account. Empty generates one.")]
        [SerializeField] private string playerName = "";

        [Tooltip("Object(s) activated once the session exists (usually the gameplay root).")]
        [SerializeField] private GameObject[] enableOnReady = Array.Empty<GameObject>();

        /// <summary>Raised once the player is signed in.</summary>
        public event Action<ExoSession>? SessionReady;

        /// <summary>The signed-in player, or null until sign-in completes.</summary>
        public ExoSession? Session { get; private set; }

        public string PlayerId => Session?.PlayerId ?? "";
        public string DisplayName => Session?.DisplayName ?? "";
        public bool IsReady => Session != null;

        private async void Start()
        {
            SetTargets(false);

            try
            {
                Session = await ExoforgeSDK.Auth.LoginAnonymously(playerName);

                SetTargets(true);
                SessionReady?.Invoke(Session);
                Debug.Log($"[Snake] player ready: {DisplayName} ({PlayerId})");
            }
            catch (Exception ex)
            {
                Debug.LogError($"[Snake] sign-in failed: {ex.Message}");
            }
        }

        private void SetTargets(bool active)
        {
            foreach (var target in enableOnReady)
            {
                if (target != null)
                {
                    target.SetActive(active);
                }
            }
        }
    }
}
