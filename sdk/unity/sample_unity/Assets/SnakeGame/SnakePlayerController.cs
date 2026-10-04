using System;
using System.Text.Json;
using System.Threading.Tasks;
using Exoforge.Client;
using Exoforge.Client.Unity;
using UnityEngine;

namespace SnakeGame
{
    /// <summary>
    /// Owns the player session. Authenticates against Exoforge, registers an anonymous player on
    /// first run, and assigns that player's display name.
    ///
    /// Gameplay never talks to auth — it reads <see cref="PlayerId"/> / <see cref="DisplayName"/>
    /// and subscribes to <see cref="SessionReady"/>. The scene/UI part is intentionally left out.
    /// </summary>
    [DefaultExecutionOrder(-800)]
    public class SnakePlayerController : MonoBehaviour
    {
        [Header("Player")]
        [Tooltip("Display name to register on first run. Empty generates one.")]
        [SerializeField] private string playerName = "";

        [Tooltip("Object(s) activated once the session exists (usually the gameplay root).")]
        [SerializeField] private GameObject[] enableOnReady = Array.Empty<GameObject>();

        /// <summary>Raised once the player has a named session.</summary>
        public event Action<ExoClient>? SessionReady;

        public ExoClient? Client { get; private set; }
        public string PlayerId { get; private set; } = "";
        public string DisplayName { get; private set; } = "";
        public bool IsReady { get; private set; }

        private async void Start()
        {
            SetTargets(false);

            try
            {
                await EnsureSessionAsync();
            }
            catch (Exception ex)
            {
                Debug.LogError($"[Snake] player session failed: {ex.Message}");
            }
        }

        /// <summary>
        /// Authenticates and, on first run, creates + names an anonymous player.
        /// Pass <paramref name="name"/> to override the serialized name.
        /// </summary>
        public async Task<bool> EnsureSessionAsync(string? name = null)
        {
            Client = await ExoforgeBehaviour.Instance.GetClientAsync();

            // This machine already registered a player: reuse the stored session.
            if (ExoTokenStore.IsRegistered)
            {
                PlayerId = ExoTokenStore.PlayerId;
                DisplayName = ExoTokenStore.PlayerName;
                Ready();
                return true;
            }

            string chosen = string.IsNullOrWhiteSpace(name) ? playerName : name;

            if (string.IsNullOrWhiteSpace(chosen))
            {
                chosen = $"Player{UnityEngine.Random.Range(1000, 9999)}";
            }

            // `auth.anonymous` is reachable before a session exists. Passing the current player id
            // makes it a naming update on the anonymous player rather than a second registration.
            var result = await Client.SendActionAsync<JsonElement>("auth", "anonymous", new
            {
                player_id = Client.PlayerId,
                name = chosen
            });

            string token = result.ValueKind == JsonValueKind.Object && result.TryGetProperty("token", out var tokenProp)
                ? tokenProp.GetString() ?? ""
                : "";

            if (string.IsNullOrEmpty(token))
            {
                Debug.LogError("[Snake] auth.anonymous returned no token");
                return false;
            }

            var auth = await Client.AuthenticateAsync(token);

            if (!auth.IsSuccess)
            {
                Debug.LogError($"[Snake] re-authentication failed: {auth.Error}");
                return false;
            }

            PlayerId = auth.PlayerId ?? Client.PlayerId ?? "";
            DisplayName = chosen;
            ExoTokenStore.SaveSession(token, PlayerId, auth.Scopes, DisplayName);

            Ready();
            return true;
        }

        private void Ready()
        {
            IsReady = true;
            SetTargets(true);
            SessionReady?.Invoke(Client!);
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
