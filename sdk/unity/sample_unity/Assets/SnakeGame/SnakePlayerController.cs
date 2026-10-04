using System;
using System.Threading.Tasks;
using Exoforge.Client.Unity;
using UnityEngine;

namespace SnakeGame
{
    /// <summary>
    /// Signs the player in, then names them if the account has no display name yet.
    ///
    /// Stage 1 — <see cref="ExoforgeSDK.Auth"/> enters the account for this device (registering it
    /// on first sight). Stage 2 — a new account has no display name, so <see cref="DisplayNameRequired"/>
    /// fires and the game prompts; the answer goes back through <see cref="SetDisplayNameAsync"/>.
    ///
    /// Gameplay is only enabled once both stages are done.
    /// </summary>
    [DefaultExecutionOrder(-800)]
    public class SnakePlayerController : MonoBehaviour
    {
        [Tooltip("Object(s) activated once the player is signed in and named (usually the gameplay root).")]
        [SerializeField] private GameObject[] enableOnReady = Array.Empty<GameObject>();

        /// <summary>Raised once the player is signed in <em>and</em> named.</summary>
        public event Action<ExoSession>? SessionReady;

        /// <summary>Raised when the account still needs a display name — show the prompt here.</summary>
        public event Action? DisplayNameRequired;

        /// <summary>The signed-in player, or null until sign-in completes.</summary>
        public ExoSession? Session { get; private set; }

        public string PlayerId => Session?.PlayerId ?? "";
        public string DisplayName => Session?.DisplayName ?? "";
        public bool IsSignedIn => Session != null;
        public bool NeedsDisplayName => Session is { HasDisplayName: false };
        public bool IsReady => Session is { HasDisplayName: true };

        private async void Start()
        {
            SetTargets(false);

            try
            {
                Session = await ExoforgeSDK.Auth.LoginAnonymously();
                Debug.Log($"[Snake] signed in as {PlayerId}");

                if (NeedsDisplayName)
                {
                    DisplayNameRequired?.Invoke();
                    return;
                }

                Ready();
            }
            catch (Exception ex)
            {
                Debug.LogError($"[Snake] sign-in failed: {ex.Message}");
            }
        }

        /// <summary>Stage 2: applies the name the player chose and starts gameplay.</summary>
        public async Task<bool> SetDisplayNameAsync(string displayName)
        {
            if (Session == null)
            {
                Debug.LogWarning("[Snake] sign in before setting a display name");
                return false;
            }

            try
            {
                Session = await ExoforgeSDK.Auth.SetDisplayName(displayName);
                Ready();
                return true;
            }
            catch (Exception ex)
            {
                Debug.LogError($"[Snake] could not set display name: {ex.Message}");
                return false;
            }
        }

        private void Ready()
        {
            SetTargets(true);
            SessionReady?.Invoke(Session!);
            Debug.Log($"[Snake] player ready: {DisplayName} ({PlayerId})");
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
