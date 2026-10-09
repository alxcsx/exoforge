using System;
using System.Threading.Tasks;
using Exoforge.Client.Unity;
using UnityEngine;

namespace SnakeGame
{
    [DefaultExecutionOrder(-800)]
    public class SnakePlayerController : MonoBehaviour
    {
        [SerializeField] private GameObject[] enableOnReady = Array.Empty<GameObject>();

        public event Action<ExoSession>? SessionReady;
        public event Action? DisplayNameRequired;

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
                if (this == null || !isActiveAndEnabled) return;
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
