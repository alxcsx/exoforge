using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Threading.Tasks;
using Exoforge.Client;
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
        /// <param name="disposable">
        /// Marks the account as one a test, a demo or a load run made, so `auth.purge_disposable` can
        /// remove it and nothing else. A game leaves this alone: its players are the point.
        /// </param>
        public async Task<ExoSession> LoginAnonymously(bool disposable = false)
        {
            // No socket. Signing in is a request/response call, and a game that never subscribes
            // should never open one - so this goes over HTTP and the socket stays shut until
            // something actually needs it.
            var client = ExoforgeSDK.Client;

            // Fast path: the credential this machine already holds.
            if (ExoTokenStore.HasToken)
            {
                var existing = await AuthenticateAsync(client, ExoTokenStore.Token);

                if (existing != null)
                {
                    client.UseToken(ExoTokenStore.Token);
                    if (client.IsConnected && !client.IsAuthenticated)
                    {
                        await client.AuthenticateAsync(ExoTokenStore.Token);
                    }

                    Current = new ExoSession(
                        existing.Value.PlayerId,
                        ExoTokenStore.PlayerName,
                        ExoTokenStore.Token,
                        existing.Value.Scopes,
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
                player_id = ExoDeviceId.Get(),
                disposable
            }, ExoTransportPreference.Http);

            string token = result.ValueKind == JsonValueKind.Object && result.TryGetProperty("token", out var tokenProp)
                ? tokenProp.GetString() ?? ""
                : "";

            if (string.IsNullOrEmpty(token))
            {
                throw new InvalidOperationException("auth.anonymous did not return a token.");
            }

            client.UseToken(token);
            if (client.IsConnected)
            {
                await client.AuthenticateAsync(token);
            }

            var auth = await AuthenticateAsync(client, token)
                ?? throw new InvalidOperationException("Could not authenticate the new session.");

            string name = result.ValueKind == JsonValueKind.Object && result.TryGetProperty("name", out var nameProp)
                ? nameProp.GetString() ?? ""
                : "";

            ExoTokenStore.SaveSession(token, auth.PlayerId, auth.Scopes, name);

            Current = new ExoSession(auth.PlayerId, name, token, auth.Scopes, true);
            return Current;
        }

        /// <summary>
        /// Resolves a token to a player over HTTP, returning null when it is not valid.
        ///
        /// This is the <c>auth.authenticate</c> action rather than <see cref="ExoClient.AuthenticateAsync"/>,
        /// which is the socket's own auth frame and needs a connection this deliberately avoids.
        /// </summary>
        private static async Task<(string PlayerId, List<string> Scopes)?> AuthenticateAsync(
            ExoClient client, string token)
        {
            try
            {
                var result = await client.SendActionAsync<JsonElement>("auth", "authenticate", new { token }, ExoTransportPreference.Http);

                if (result.ValueKind != JsonValueKind.Object)
                {
                    return null;
                }

                string playerId = result.TryGetProperty("player_id", out var idProp)
                    ? idProp.GetString() ?? ""
                    : "";

                var scopes = new List<string>();

                if (result.TryGetProperty("scopes", out var scopesProp) && scopesProp.ValueKind == JsonValueKind.Array)
                {
                    foreach (var scope in scopesProp.EnumerateArray())
                    {
                        scopes.Add(scope.GetString() ?? "");
                    }
                }

                return string.IsNullOrEmpty(playerId) ? null : (playerId, scopes);
            }
            catch (Exception)
            {
                // A stale or rejected credential falls through to a fresh account.
                return null;
            }
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
            var client = ExoforgeSDK.Client;
            var result = await client.SendActionAsync<JsonElement>("auth", "set_display_name", new { name = trimmed }, ExoTransportPreference.Http);

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
