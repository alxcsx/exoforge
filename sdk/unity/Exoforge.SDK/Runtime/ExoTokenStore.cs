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
    #if UNITY_EDITOR
                UnityEditor.EditorPrefs.SetString("Exoforge_AdminToken", value ?? string.Empty);
    #endif
            }
        }

        public static string PlayerId
        {
            get => PlayerPrefs.GetString(PlayerIdKey, string.Empty);
            set
            {
                PlayerPrefs.SetString(PlayerIdKey, value ?? string.Empty);
                PlayerPrefs.Save();
    #if UNITY_EDITOR
                UnityEditor.EditorPrefs.SetString("Exoforge_PlayerId", value ?? string.Empty);
    #endif
            }
        }

        public static string Scopes
        {
            get => PlayerPrefs.GetString(ScopesKey, string.Empty);
            set
            {
                PlayerPrefs.SetString(ScopesKey, value ?? string.Empty);
                PlayerPrefs.Save();
    #if UNITY_EDITOR
                UnityEditor.EditorPrefs.SetString("Exoforge_Scopes", value ?? string.Empty);
    #endif
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

        /// <summary>True once a session exists and the player has picked a display name.</summary>
        public static bool IsRegistered => HasToken && !string.IsNullOrEmpty(PlayerName);

        public static void SaveSession(string token, string? playerId = null, IEnumerable<string>? scopes = null, string? name = null)
        {
            Token = token;
            PlayerId = playerId ?? string.Empty;
            Scopes = scopes != null ? string.Join(",", scopes) : string.Empty;

            if (name != null)
            {
                PlayerName = name;
            }
        }

        public static void Clear()
        {
            PlayerPrefs.DeleteKey(TokenKey);
            PlayerPrefs.DeleteKey(PlayerIdKey);
            PlayerPrefs.DeleteKey(ScopesKey);
            PlayerPrefs.DeleteKey(NameKey);
            PlayerPrefs.Save();
    #if UNITY_EDITOR
            UnityEditor.EditorPrefs.DeleteKey("Exoforge_AdminToken");
            UnityEditor.EditorPrefs.DeleteKey("Exoforge_PlayerId");
            UnityEditor.EditorPrefs.DeleteKey("Exoforge_Scopes");
    #endif
        }
    }
}
