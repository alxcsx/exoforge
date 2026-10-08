using System;
using System.Collections.Generic;
using UnityEngine;

namespace Exoforge.Client
{

    /// <summary>
    /// Persists the bearer token, player id, name, and scopes in Unity's PlayerPrefs so a client
    /// can reuse them across sessions, scenes, and builds.
    ///
    /// Two sessions are kept apart: this device's own, and the one the Exoforge Studio window is
    /// signed in as. <see cref="UseStudioSession"/> picks which one the accessors below read, so play
    /// mode can act as the Studio's account - same leaderboard rows, same player data - without
    /// destroying the device's.
    ///
    /// Low-level: game code should use <see cref="ExoforgeSDK.Auth"/> instead. Exposed for
    /// advanced cases (custom credential storage, tooling).
    /// </summary>
    /// <remarks>
    /// PlayerPrefs is plaintext (registry / plist). Use it for convenience during development,
    /// not as secure storage in untrusted production environments.
    /// </remarks>
    public static class ExoTokenStore
    {
        private const string TokenKey = "Exoforge.Token";
        private const string PlayerIdKey = "Exoforge.PlayerId";
        private const string ScopesKey = "Exoforge.Scopes";
        private const string NameKey = "Exoforge.PlayerName";

        private const string StudioTokenKey = "Exoforge.Studio.Token";
        private const string StudioPlayerIdKey = "Exoforge.Studio.PlayerId";
        private const string StudioScopesKey = "Exoforge.Studio.Scopes";
        private const string StudioNameKey = "Exoforge.Studio.PlayerName";

        /// <summary>
        /// Read the Studio's session instead of this device's. Set from <c>ExoforgeManager</c>'s
        /// "use studio connection" flag, which is what decides it in play mode.
        /// </summary>
        public static bool UseStudioSession { get; set; }

        // Setters write to PlayerPrefs but do not flush it. SaveSession and Clear flush once, so
        // storing a session is one disk write rather than four. Unity flushes on quit regardless.

        public static string Token
        {
            get => Read(TokenKey, StudioTokenKey);
            set => Write(TokenKey, StudioTokenKey, value);
        }

        public static string PlayerId
        {
            get => Read(PlayerIdKey, StudioPlayerIdKey);
            set => Write(PlayerIdKey, StudioPlayerIdKey, value);
        }

        /// <summary>Scopes as a comma-separated string. Written for diagnostics; the SDK reads scopes from the session.</summary>
        public static string Scopes
        {
            get => Read(ScopesKey, StudioScopesKey);
            set => Write(ScopesKey, StudioScopesKey, value);
        }

        /// <summary>Display name chosen by the player during onboarding (empty for a fresh anonymous session).</summary>
        public static string PlayerName
        {
            get => Read(NameKey, StudioNameKey);
            set => Write(NameKey, StudioNameKey, value);
        }

        public static bool HasToken => !string.IsNullOrEmpty(Token);

        // The Studio's slot, whatever UseStudioSession says. The editor works with these directly:
        // it is the Studio, and its session is not the device's.

        /// <summary>The Studio's bearer token.</summary>
        public static string StudioToken => PlayerPrefs.GetString(StudioTokenKey, string.Empty);

        /// <summary>The Studio's player id.</summary>
        public static string StudioPlayerId => PlayerPrefs.GetString(StudioPlayerIdKey, string.Empty);

        /// <summary>The Studio's scopes, comma-separated.</summary>
        public static string StudioScopes => PlayerPrefs.GetString(StudioScopesKey, string.Empty);

        /// <summary>Forgets the Studio's session, leaving the device's alone.</summary>
        public static void ClearStudioSession()
        {
            PlayerPrefs.DeleteKey(StudioTokenKey);
            PlayerPrefs.DeleteKey(StudioPlayerIdKey);
            PlayerPrefs.DeleteKey(StudioScopesKey);
            PlayerPrefs.DeleteKey(StudioNameKey);
            PlayerPrefs.Save();
        }

        public static void SaveSession(string token, string? playerId = null, IEnumerable<string>? scopes = null, string? name = null) =>
            Store(TokenKey, PlayerIdKey, ScopesKey, NameKey, token, playerId, scopes, name);

        /// <summary>
        /// Stores the Exoforge Studio window's session. Written by the editor on connect; read in play
        /// mode when <see cref="UseStudioSession"/> is on.
        /// </summary>
        public static void SaveStudioSession(string token, string? playerId = null, IEnumerable<string>? scopes = null, string? name = null) =>
            Store(StudioTokenKey, StudioPlayerIdKey, StudioScopesKey, StudioNameKey, token, playerId, scopes, name);

        private static void Store(
            string tokenKey, string playerIdKey, string scopesKey, string nameKey,
            string token, string? playerId, IEnumerable<string>? scopes, string? name)
        {
            string resolvedPlayerId = playerId ?? string.Empty;

            // A different account cannot inherit the previous one's name. Callers that reconnect
            // with a stored token pass no name, so without this the name stuck around and
            // ExoSession.DisplayName reported the wrong player — which is how someone else's name
            // ends up on a shared leaderboard.
            bool samePlayer = !string.IsNullOrEmpty(resolvedPlayerId) &&
                              string.Equals(PlayerPrefs.GetString(playerIdKey, string.Empty), resolvedPlayerId, StringComparison.Ordinal);

            PlayerPrefs.SetString(tokenKey, token);
            PlayerPrefs.SetString(playerIdKey, resolvedPlayerId);
            PlayerPrefs.SetString(scopesKey, scopes != null ? string.Join(",", scopes) : string.Empty);

            if (name != null)
            {
                PlayerPrefs.SetString(nameKey, name);
            }
            else if (!samePlayer)
            {
                PlayerPrefs.SetString(nameKey, string.Empty);
            }

            PlayerPrefs.Save();
        }

        /// <summary>Clears the session in use, leaving the other one alone.</summary>
        public static void Clear()
        {
            Delete(TokenKey, StudioTokenKey);
            Delete(PlayerIdKey, StudioPlayerIdKey);
            Delete(ScopesKey, StudioScopesKey);
            Delete(NameKey, StudioNameKey);
            PlayerPrefs.Save();
        }

        private static string Read(string deviceKey, string studioKey) =>
            PlayerPrefs.GetString(UseStudioSession ? studioKey : deviceKey, string.Empty);

        private static void Write(string deviceKey, string studioKey, string? value) =>
            PlayerPrefs.SetString(UseStudioSession ? studioKey : deviceKey, value ?? string.Empty);

        private static void Delete(string deviceKey, string studioKey) =>
            PlayerPrefs.DeleteKey(UseStudioSession ? studioKey : deviceKey);
    }
}
