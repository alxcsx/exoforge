using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Threading;
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
        public ExoSession? Current { get; internal set; }

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
        /// <summary>
        /// Non-async callback overload for anonymous login. Automatically dispatches onComplete
        /// and onError onto the Unity main thread via the client dispatcher.
        /// </summary>
        public void LoginAnonymously(Action<ExoSession> onComplete, Action<Exception>? onError = null, bool disposable = false)
        {
            _ = Task.Run(async () =>
            {
                try
                {
                    var session = await LoginAnonymously(disposable);
                    ExoforgeSDK.Client.Dispatcher.Post(() => onComplete(session));
                }
                catch (Exception ex)
                {
                    if (onError != null)
                        ExoforgeSDK.Client.Dispatcher.Post(() => onError(ex));
                    else
                        Debug.LogError($"[Exoforge] Anonymous login error: {ex.Message}");
                }
            });
        }

        public async Task<ExoSession> LoginAnonymously(bool disposable = false)
        {
            // No socket. Signing in is a request/response call, and a game that never subscribes
            // should never open one - so this goes over HTTP and the socket stays shut until
            // something actually needs it.
            var client = ExoforgeSDK.Client;
            string activeDeviceId = ExoDeviceId.Get();

            // Fast path: the credential this machine already holds for the active device ID.
            // Anonymous login is strictly for device/player sessions and must never reuse staff/admin credentials.
            string cachedToken = ExoTokenStore.DeviceToken;
            string attachedDeviceId = ExoTokenStore.AttachedDeviceId;

            if (!string.IsNullOrEmpty(cachedToken) && string.Equals(attachedDeviceId, activeDeviceId, StringComparison.Ordinal))
            {
                var existing = await AuthenticateAsync(client, cachedToken);

                if (existing != null)
                {
                    bool isStaff = existing.Value.Scopes.Contains("admin") || existing.Value.Scopes.Contains("studio");
                    if (isStaff)
                    {
                        Debug.LogWarning("[Exoforge] Cached device token belongs to staff/admin while running as player. Resetting session to mint fresh anonymous account.");
                        ExoTokenStore.ClearDeviceSession();
                    }
                    else
                    {
                        client.UseToken(cachedToken);
                        if (client.IsConnected && !client.IsAuthenticated)
                        {
                            await client.AuthenticateAsync(cachedToken);
                        }

                        Current = new ExoSession(
                            existing.Value.PlayerId,
                            ExoTokenStore.PlayerName,
                            cachedToken,
                            existing.Value.Scopes,
                            false);

                        ExoforgeSDK.WireExoServicesLocator();
                        return Current;
                    }
                }
                else if (!string.IsNullOrEmpty(ExoTokenStore.DeviceRefreshToken) && await RefreshAsync())
                {
                    // The access token expired, which is ordinary: the refresh token renews the
                    // session for the same player instead of registering a new account.
                    if (Current != null)
                    {
                        ExoforgeSDK.WireExoServicesLocator();
                        return Current;
                    }
                }
                else
                {
                    // Stored credential is stale — fall through and mint a fresh account.
                    ExoTokenStore.ClearDeviceSession();
                }
            }

            // `player_id` is the account key, so this creates the player on first sight of the
            // device and re-enters it on a fresh install. We pass both player_id and device_id.
            var result = await client.SendActionAsync<JsonElement>("auth", "anonymous", new
            {
                player_id = activeDeviceId,
                device_id = activeDeviceId,
                disposable
            }, ExoTransportPreference.Http);

            string token = result.ValueKind == JsonValueKind.Object && result.TryGetProperty("token", out var tokenProp)
                ? tokenProp.GetString() ?? ""
                : "";

            string refreshToken = result.ValueKind == JsonValueKind.Object && result.TryGetProperty("refresh_token", out var refreshProp)
                ? refreshProp.GetString() ?? ""
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

            ExoTokenStore.SaveSession(token, auth.PlayerId, auth.Scopes, name, activeDeviceId, refreshToken);

            Current = new ExoSession(auth.PlayerId, name, token, auth.Scopes, true);
            ExoforgeSDK.WireExoServicesLocator();
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
        /// Exchanges the stored refresh token for a new access/refresh pair.
        ///
        /// The client calls this itself when an action comes back <c>token_expired</c> (and then
        /// retries once), so game code rarely needs it; it is public for a game that wants to renew
        /// ahead of time. Returns false when there is no refresh token or the server refuses it.
        ///
        /// Every route to a renewal - the retry after an expiry, a reconnect, a login - runs under
        /// the client's one gate, so a burst of expiries shares a single rotation and all of them
        /// await its result.
        /// </summary>
        public Task<bool> RefreshAsync(CancellationToken cancellationToken = default) =>
            ExoforgeSDK.Client.RefreshTokensOnceAsync(RefreshCoreAsync, cancellationToken);

        /// <summary>
        /// The rotation itself. Internal because it must not be reached except through
        /// <see cref="RefreshAsync"/>: calling it twice concurrently would replay a single-use
        /// refresh token and revoke the session family.
        /// </summary>
        internal async Task<bool> RefreshCoreAsync(CancellationToken cancellationToken = default)
        {
            var client = ExoforgeSDK.Client;
            string refreshToken = ExoTokenStore.RefreshToken;

            if (string.IsNullOrEmpty(refreshToken))
            {
                return false;
            }

            JsonElement result;

            try
            {
                result = await client.SendActionAsync<JsonElement>(
                    "auth",
                    "refresh",
                    new { token = refreshToken },
                    ExoTransportPreference.Http,
                    cancellationToken: cancellationToken);
            }
            catch (Exception)
            {
                // A refused or replayed refresh token normally means this session is over and the
                // caller falls back to a fresh login. Unless the store now holds a pair that was
                // rotated while this call waited: then that pair is the session, and adopting it
                // beats replaying the spent token.
                string stored = ExoTokenStore.RefreshToken;

                if (string.IsNullOrEmpty(stored) ||
                    string.Equals(stored, refreshToken, StringComparison.Ordinal))
                {
                    return false;
                }

                return await AdoptStoredSessionAsync(client);
            }

            string token = result.ValueKind == JsonValueKind.Object && result.TryGetProperty("token", out var tokenProp)
                ? tokenProp.GetString() ?? ""
                : "";

            string rotated = result.ValueKind == JsonValueKind.Object && result.TryGetProperty("refresh_token", out var rotatedProp)
                ? rotatedProp.GetString() ?? ""
                : "";

            if (string.IsNullOrEmpty(token) || string.IsNullOrEmpty(rotated))
            {
                return false;
            }

            var auth = await AuthenticateAsync(client, token);

            if (auth == null)
            {
                return false;
            }

            if (ExoTokenStore.UseStudioSession)
            {
                ExoTokenStore.SaveStudioSession(token, auth.Value.PlayerId, auth.Value.Scopes, ExoTokenStore.PlayerName, rotated);
            }
            else
            {
                ExoTokenStore.SaveSession(token, auth.Value.PlayerId, auth.Value.Scopes, ExoTokenStore.PlayerName, ExoTokenStore.AttachedDeviceId, rotated);
            }

            client.UseToken(token);
            await AuthenticateSocketIfConnectedAsync(client, token);

            Current = new ExoSession(auth.Value.PlayerId, ExoTokenStore.PlayerName, token, auth.Value.Scopes, false);
            return true;
        }

        /// <summary>
        /// Uses the access token already in the store - one another client rotated - instead of
        /// minting a second rotation from a refresh token that has been spent.
        /// </summary>
        private async Task<bool> AdoptStoredSessionAsync(ExoClient client)
        {
            string stored = ExoTokenStore.Token;

            if (string.IsNullOrEmpty(stored))
            {
                return false;
            }

            var auth = await AuthenticateAsync(client, stored);

            if (auth == null)
            {
                return false;
            }

            client.UseToken(stored);
            await AuthenticateSocketIfConnectedAsync(client, stored);

            Current = new ExoSession(auth.Value.PlayerId, ExoTokenStore.PlayerName, stored, auth.Value.Scopes, false);
            return true;
        }

        private static async Task AuthenticateSocketIfConnectedAsync(ExoClient client, string token)
        {
            if (!client.IsConnected)
            {
                return;
            }

            try
            {
                await client.AuthenticateAsync(token);
            }
            catch (Exception)
            {
                // The next reconnect authenticates the socket with the new token anyway.
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
            ExoTokenStore.ClearDeviceSession();
            Current = null;
            try
            {
                ExoforgeSDK.Client.UseToken(null);
            }
            catch { }
        }

        /// <summary>Forgets the stored session <em>and</em> the device identity (claims a new player).</summary>
        public void LogoutAndForgetDevice()
        {
            Logout();
            ExoDeviceId.Reset();
        }

        /// <summary>Alias for <see cref="LogoutAndForgetDevice"/> to start completely fresh as an anonymous player.</summary>
        public void ResetSession() => LogoutAndForgetDevice();
    }
}
