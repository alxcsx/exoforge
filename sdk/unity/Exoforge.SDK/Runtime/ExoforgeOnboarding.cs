using System;
using System.Text.Json;
using System.Threading.Tasks;
using UnityEngine;

namespace Exoforge.Client.Unity
{
    /// <summary>
    /// Pre-game onboarding. Resumes an existing session automatically, or asks the player for a
    /// display name and creates an anonymous session for them.
    ///
    /// This is the only gameplay-adjacent component that touches Exoforge auth — the game loop
    /// itself stays free of backend concerns. Activate <see cref="enableOnReady"/> (or subscribe
    /// to <see cref="OnReady"/>) to start gameplay once a session exists.
    /// </summary>
    [DefaultExecutionOrder(-900)]
    public class ExoforgeOnboarding : MonoBehaviour
    {
        [Header("Onboarding")]
        [Tooltip("Objects activated once a session is ready (usually the gameplay root).")]
        [SerializeField] private GameObject[] enableOnReady = Array.Empty<GameObject>();

        [Tooltip("Skip the name prompt and accept the anonymous session as-is.")]
        [SerializeField] private bool skipNamePrompt;

        /// <summary>Raised once the player has a session (auto-resumed or freshly named).</summary>
        public event Action<ExoClient>? OnReady;

        private ExoClient? _client;
        private string _displayName = "";
        private string _status = "Connecting…";
        private bool _busy;
        private bool _done;

        /// <summary>True once a session exists and gameplay may start.</summary>
        public bool IsReady => _done;

        private async void Start()
        {
            SetTargetsActive(false);

            try
            {
                _client = await ExoforgeBehaviour.Instance.GetClientAsync();
                _status = $"Connected as {_client.PlayerId}";

                // Already registered on this machine, or the prompt is skipped: straight in.
                if (ExoTokenStore.IsRegistered || skipNamePrompt)
                {
                    Finish();
                }
            }
            catch (Exception ex)
            {
                _status = $"Offline: {ex.Message}";
            }
        }

        private async Task SubmitAsync()
        {
            if (_client == null || _busy)
            {
                return;
            }

            _busy = true;

            string name = string.IsNullOrWhiteSpace(_displayName)
                ? $"Player{UnityEngine.Random.Range(1000, 9999)}"
                : _displayName.Trim();

            try
            {
                var result = await _client.SendActionAsync<JsonElement>("auth", "anonymous", new
                {
                    player_id = _client.PlayerId,
                    name
                });

                string token = result.ValueKind == JsonValueKind.Object && result.TryGetProperty("token", out var tokenProp)
                    ? tokenProp.GetString() ?? ""
                    : "";

                if (string.IsNullOrEmpty(token))
                {
                    _status = "Registration failed";
                    return;
                }

                var auth = await _client.AuthenticateAsync(token);
                ExoTokenStore.SaveSession(token, auth.PlayerId ?? _client.PlayerId, auth.Scopes, name);

                Finish();
            }
            catch (Exception ex)
            {
                _status = $"Registration failed: {ex.Message}";
            }
            finally
            {
                _busy = false;
            }
        }

        private void Finish()
        {
            _done = true;
            SetTargetsActive(true);
            OnReady?.Invoke(_client!);
            enabled = false;
        }

        private void SetTargetsActive(bool active)
        {
            foreach (var target in enableOnReady)
            {
                if (target != null)
                {
                    target.SetActive(active);
                }
            }
        }

        private void OnGUI()
        {
            float width = Mathf.Min(Screen.width - 40, 420);
            float height = 220;
            var rect = new Rect((Screen.width - width) / 2f, (Screen.height - height) / 2f, width, height);

            GUI.Box(rect, "Exoforge — Player Setup");
            GUILayout.BeginArea(new Rect(rect.x + 20, rect.y + 40, rect.width - 40, rect.height - 60));

            GUILayout.Label(_status);
            GUILayout.Space(10);
            GUILayout.Label("Choose a display name:");

            GUI.SetNextControlName("nameField");
            _displayName = GUILayout.TextField(_displayName ?? "", 24);

            GUILayout.Space(12);

            using (new GuiEnabledScope(!_busy && _client != null))
            {
                if (GUILayout.Button(_busy ? "Creating…" : "Play", GUILayout.Height(34)))
                {
                    _ = SubmitAsync();
                }
            }

            GUILayout.EndArea();
        }

        private readonly struct GuiEnabledScope : IDisposable
        {
            private readonly bool _previous;

            public GuiEnabledScope(bool enabled)
            {
                _previous = GUI.enabled;
                GUI.enabled = enabled;
            }

            public void Dispose() => GUI.enabled = _previous;
        }
    }
}
