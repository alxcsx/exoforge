using System;
using System.Collections.Generic;
using UnityEngine;

namespace Exoforge.Client
{

    /// <summary>
    /// Persists the bearer token, player id, name, and scopes in Unity's PlayerPrefs so a client
    /// can reuse them across sessions, scenes, and builds.
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

        public static string Token
        {
            get => PlayerPrefs.GetString(TokenKey, string.Empty);
            set
            {
                PlayerPrefs.SetString(TokenKey, value ?? string.Empty);
                PlayerPrefs.Save();
            }
        }

        public static string PlayerId
        {
            get => PlayerPrefs.GetString(PlayerIdKey, string.Empty);
            set
            {
                PlayerPrefs.SetString(PlayerIdKey, value ?? string.Empty);
                PlayerPrefs.Save();
            }
        }

        public static string Scopes
        {
            get => PlayerPrefs.GetString(ScopesKey, string.Empty);
            set
            {
                PlayerPrefs.SetString(ScopesKey, value ?? string.Empty);
                PlayerPrefs.Save();
            }
        }

        /// <summary>Display name chosen by the player during onboarding (empty for a fresh anonymous session).</summary>
        public static string PlayerName
        {
            get => PlayerPrefs.GetString(NameKey, string.Empty);
            set
            {
                PlayerPrefs.SetString(NameKey, value ?? string.Empty);
                PlayerPrefs.Save();
            }
        }

        public static bool HasToken => !string.IsNullOrEmpty(Token);

        public static void SaveSession(string token, string? playerId = null, IEnumerable<string>? scopes = null, string? name = null)
        {
            string resolvedPlayerId = playerId ?? string.Empty;

            // A different account cannot inherit the previous one's name. Callers that reconnect
            // with a stored token pass no name, so without this the name stuck around and
            // ExoSession.DisplayName reported the wrong player — which is how someone else's name
            // ends up on a shared leaderboard.
            bool samePlayer = !string.IsNullOrEmpty(resolvedPlayerId) &&
                              string.Equals(PlayerId, resolvedPlayerId, StringComparison.Ordinal);

            Token = token;
            PlayerId = resolvedPlayerId;
            Scopes = scopes != null ? string.Join(",", scopes) : string.Empty;

            if (name != null)
            {
                PlayerName = name;
            }
            else if (!samePlayer)
            {
                PlayerName = string.Empty;
            }
        }

        public static void Clear()
        {
            PlayerPrefs.DeleteKey(TokenKey);
            PlayerPrefs.DeleteKey(PlayerIdKey);
            PlayerPrefs.DeleteKey(ScopesKey);
            PlayerPrefs.DeleteKey(NameKey);
            PlayerPrefs.Save();
        }
    }
}
