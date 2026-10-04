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
        /// Signs in anonymously: re-uses the account this machine already registered, or creates
        /// one (naming it <paramref name="name"/>, or a generated name).
        /// </summary>
        public async Task<ExoSession> LoginAnonymously(string? name = null)
        {
            var client = await ExoforgeSDK.ConnectAsync();

            // Re-use the account this machine already registered.
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

            string chosen = string.IsNullOrWhiteSpace(name)
                ? $"Player{UnityEngine.Random.Range(1000, 9999)}"
                : name.Trim();

            var result = await client.SendActionAsync<JsonElement>("auth", "anonymous", new { name = chosen });

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

        /// <summary>Forgets the stored session.</summary>
        public void Logout()
        {
            ExoTokenStore.Clear();
            Current = null;
        }
    }
}
