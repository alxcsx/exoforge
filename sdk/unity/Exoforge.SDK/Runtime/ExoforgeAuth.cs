using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Threading.Tasks;
using UnityEngine;

namespace Exoforge.Client.Unity
{
    /// <summary>
    /// Player sign-in. This is the API game code should use — the token store behind it is an
    /// implementation detail.
    /// </summary>
    public sealed class ExoforgeAuth
    {
        /// <summary>The signed-in player, or null before the first login.</summary>
        public ExoSession? Current { get; private set; }

        /// <summary>
        /// Stage 1 — enters the account for this device, registering it on first sight.
        ///
        /// No display name is assigned: a new account comes back with
        /// <see cref="ExoSession.HasDisplayName"/> false, and the game prompts for one, then calls
        /// <see cref="SetDisplayName"/>.
        /// </summary>
        public async Task<ExoSession> LoginAnonymously()
        {
            var client = await ExoforgeSDK.ConnectAsync();

            // Fast path: the credential this machine already holds.
            if (ExoTokenStore.HasToken)
            {
                var existing = await client.AuthenticateAsync(ExoTokenStore.Token);

                if (existing.IsSuccess)
                {
                    Current = new ExoSession(
                        existing.PlayerId ?? ExoTokenStore.PlayerId,
                        ExoTokenStore.PlayerName,
                        ExoTokenStore.Token,
                        existing.Scopes ?? new List<string>(),
                        false);

                    return Current;
                }

                // Stored credential is stale — fall through and mint a fresh account.
                ExoTokenStore.Clear();
            }

            // `player_id` is the account key, so this creates the player on first sight of the
            // device and re-enters it on a fresh install.
            var result = await client.SendActionAsync<JsonElement>("auth", "anonymous", new
            {
                player_id = ExoDeviceId.Get()
            });

            string token = result.ValueKind == JsonValueKind.Object && result.TryGetProperty("token", out var tokenProp)
                ? tokenProp.GetString() ?? ""
                : "";

            if (string.IsNullOrEmpty(token))
            {
                throw new InvalidOperationException("auth.anonymous did not return a token.");
            }

            var auth = await client.AuthenticateAsync(token);

            if (!auth.IsSuccess)
            {
                throw new InvalidOperationException($"Could not authenticate the new session: {auth.Error}");
            }

            string playerId = auth.PlayerId ?? "";
            string name = result.ValueKind == JsonValueKind.Object && result.TryGetProperty("name", out var nameProp)
                ? nameProp.GetString() ?? ""
                : "";

            ExoTokenStore.SaveSession(token, playerId, auth.Scopes, name);

            Current = new ExoSession(playerId, name, token, auth.Scopes ?? new List<string>(), true);
            return Current;
        }

        /// <summary>
        /// Stage 2 — assigns the player's display name. Only the signed-in player can name
        /// themselves, so no id is sent.
        /// </summary>
        public async Task<ExoSession> SetDisplayName(string displayName)
        {
            if (Current == null)
            {
                throw new InvalidOperationException("Call LoginAnonymously() before setting a display name.");
            }

            if (string.IsNullOrWhiteSpace(displayName))
            {
                throw new ArgumentException("Display name cannot be empty.", nameof(displayName));
            }

            string trimmed = displayName.Trim();
            var client = await ExoforgeSDK.ConnectAsync();
            var result = await client.SendActionAsync<JsonElement>("auth", "set_display_name", new { name = trimmed });

            string applied = result.ValueKind == JsonValueKind.Object && result.TryGetProperty("name", out var nameProp)
                ? nameProp.GetString() ?? trimmed
                : trimmed;

            ExoTokenStore.SaveSession(Current.Token, Current.PlayerId, Current.Scopes, applied);
            Current = Current with { DisplayName = applied };

            return Current;
        }

        /// <summary>
        /// Forgets the stored session. The device identity is kept, so signing in again resolves
        /// to the same player.
        /// </summary>
        public void Logout()
        {
            ExoTokenStore.Clear();
            Current = null;
        }

        /// <summary>Forgets the stored session <em>and</em> the device identity (claims a new player).</summary>
        public void LogoutAndForgetDevice()
        {
            Logout();
            ExoDeviceId.Reset();
        }
    }
}
