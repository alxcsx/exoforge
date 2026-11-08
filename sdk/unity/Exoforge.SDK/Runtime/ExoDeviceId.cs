using System;
using System.Security.Cryptography;
using System.Text;
using UnityEngine;

namespace Exoforge.Client.Unity
{
    /// <summary>
    /// Stable per-install identity used as the account key for anonymous sign-in
    /// (the PlayFab `CustomId` pattern).
    ///
    /// Derived from <see cref="SystemInfo.deviceUniqueIdentifier"/> and persisted on first sight,
    /// so the account survives reinstalls on platforms where the platform id is stable, and is
    /// still stable on platforms where it is not (iOS IDFV, Android factory reset).
    ///
    /// The raw device id is never used as the account key — it is hashed, so the player id does
    /// not leak a device fingerprint.
    /// </summary>
    public static class ExoDeviceId
    {
        private const string Key = "Exoforge.DeviceId";
        private const string PreviousKey = "Exoforge.PreviousDeviceId";
        private static string? s_cached;

        /// <summary>Returns the true hardware-derived device id (stable across reinstalls).</summary>
        public static string HardwareId
        {
            get
            {
                string seed = SystemInfo.deviceUniqueIdentifier;
                if (string.IsNullOrEmpty(seed) || seed == SystemInfo.unsupportedIdentifier)
                {
                    seed = "hw_fallback_device";
                }
                return Derive(seed);
            }
        }

        /// <summary>Returns the previously active device id before the last reset/impersonation, if any.</summary>
        public static string PreviousId => PlayerPrefs.GetString(PreviousKey, string.Empty);

        /// <summary>True if the active device id is masked or impersonated away from the native hardware id.</summary>
        public static bool IsCustom => !string.Equals(Get(), HardwareId, StringComparison.Ordinal);

        /// <summary>Returns the active device id, deriving and persisting it on first call.</summary>
        public static string Get()
        {
            if (!string.IsNullOrEmpty(s_cached))
            {
                return s_cached!;
            }

            try
            {
                string cached = PlayerPrefs.GetString(Key, string.Empty);

                if (!string.IsNullOrEmpty(cached))
                {
                    s_cached = cached;
                    return cached;
                }

                string deviceId = HardwareId;
                PlayerPrefs.SetString(Key, deviceId);
                PlayerPrefs.Save();

                s_cached = deviceId;
                return deviceId;
            }
            catch (Exception)
            {
                s_cached ??= Derive(Guid.NewGuid().ToString("N"));
                return s_cached;
            }
        }

        /// <summary>Clears the cached id and generates a fresh unique device id — the next sign-in claims a brand new account.</summary>
        public static string Reset() => ResetWithNewId();

        /// <summary>
        /// Masks the current device by generating a brand new random device id, saving the current one
        /// to <see cref="PreviousId"/>, and clearing the cached anonymous player credentials.
        /// </summary>
        public static string Mask() => ResetWithNewId();

        /// <summary>Generates and persists a new unique device identifier, saving the previous one.</summary>
        public static string ResetWithNewId()
        {
            string current = Get();
            string seed = Guid.NewGuid().ToString("N");
            string newId = Derive(seed);

            SaveTransition(current, newId);
            return newId;
        }

        /// <summary>
        /// Impersonates a specific device identifier for testing, saving the current one to <see cref="PreviousId"/>
        /// and clearing the cached player credentials so the next sign-in enters that account.
        /// </summary>
        public static string Impersonate(string targetDeviceId)
        {
            if (string.IsNullOrWhiteSpace(targetDeviceId))
                throw new ArgumentException("Target device ID cannot be empty.", nameof(targetDeviceId));

            string current = Get();
            string trimmed = targetDeviceId.Trim();

            SaveTransition(current, trimmed);
            return trimmed;
        }

        /// <summary>
        /// Reverts the active device id to the previous one before the last change, if available.
        /// </summary>
        public static string? ResetToPreviousId()
        {
            string previous = PreviousId;
            if (string.IsNullOrEmpty(previous)) return null;

            string current = Get();
            SaveTransition(current, previous);
            return previous;
        }

        /// <summary>
        /// Reverts the active device id to the native hardware device ID, saving the current one to <see cref="PreviousId"/>.
        /// </summary>
        public static string ResetToHardwareId()
        {
            string current = Get();
            string hardware = HardwareId;
            SaveTransition(current, hardware);
            return hardware;
        }

        private static void SaveTransition(string previous, string next)
        {
            s_cached = next;
            try
            {
                if (!string.IsNullOrEmpty(previous) && !string.Equals(previous, next, StringComparison.Ordinal))
                {
                    PlayerPrefs.SetString(PreviousKey, previous);
                }
                PlayerPrefs.SetString(Key, next);
                PlayerPrefs.Save();

                // Clear cached anonymous player token so next sign-in claims the new identity
                ExoTokenStore.ClearDeviceSession();
            }
            catch (Exception) { }
        }

        private static string Derive(string seed)
        {
            using var sha = SHA256.Create();
            byte[] hash = sha.ComputeHash(Encoding.UTF8.GetBytes(seed));

            // did_, not dev_ (M33 Fix 19): the backend's developer-token checks watch for dev-ish
            // prefixes, and a device identity is a player id, not a developer credential.
            var sb = new StringBuilder("did_", 4 + 32);

            for (int i = 0; i < 16; i++)
            {
                sb.Append(hash[i].ToString("x2"));
            }

            return sb.ToString();
        }
    }
}
