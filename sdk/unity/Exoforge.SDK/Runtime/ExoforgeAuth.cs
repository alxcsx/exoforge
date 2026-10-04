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
        /// Signs in anonymously, keyed by this device rather than by name.
        ///
        /// The account is claimed for <see cref="ExoDeviceId"/>: the same machine always resolves
        /// to the same player, even if the stored credential is lost. <paramref name="displayName"/>
        /// only labels the player.
        /// </summary>
        public async Task<ExoSession> LoginAnonymously(string? displayName = null)
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

            string chosen = string.IsNullOrWhiteSpace(displayName)
                ? $"Player{UnityEngine.Random.Range(1000, 9999)}"
                : displayName.Trim();

            // `player_id` is the account key, so this creates the player on first sight of the
            // device and re-claims it (updating the display name) on a fresh install.
            var result = await client.SendActionAsync<JsonElement>("auth", "anonymous", new
            {
                player_id = ExoDeviceId.Get(),
                name = chosen
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
            ExoTokenStore.SaveSession(token, playerId, auth.Scopes, chosen);

            Current = new ExoSession(playerId, chosen, token, auth.Scopes ?? new List<string>(), true);
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
