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
    internal static class ExoDeviceId
    {
        private const string Key = "Exoforge.DeviceId";

        /// <summary>Returns the cached device id, deriving and persisting it on first call.</summary>
        public static string Get()
        {
            string cached = PlayerPrefs.GetString(Key, string.Empty);

            if (!string.IsNullOrEmpty(cached))
            {
                return cached;
            }

            string seed = SystemInfo.deviceUniqueIdentifier;

            // Unity returns this when the platform exposes no identifier.
            if (string.IsNullOrEmpty(seed) || seed == SystemInfo.unsupportedIdentifier)
            {
                seed = Guid.NewGuid().ToString("N");
            }

            string deviceId = Derive(seed);
            PlayerPrefs.SetString(Key, deviceId);
            PlayerPrefs.Save();

            return deviceId;
        }

        /// <summary>Clears the cached id — the next sign-in claims a fresh account.</summary>
        public static void Reset()
        {
            PlayerPrefs.DeleteKey(Key);
            PlayerPrefs.Save();
        }

        private static string Derive(string seed)
        {
            using var sha = SHA256.Create();
            byte[] hash = sha.ComputeHash(Encoding.UTF8.GetBytes(seed));

            var sb = new StringBuilder("dev_", 4 + 32);

            for (int i = 0; i < 16; i++)
            {
                sb.Append(hash[i].ToString("x2"));
            }

            return sb.ToString();
        }
    }
}
