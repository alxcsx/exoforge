using System;
using UnityEngine;

namespace Exoforge.Client.Unity
{
    public static class ExoProfile
    {
        private static string? s_cached;

        public static string Current
        {
            get
            {
                if (s_cached != null) return s_cached;
                s_cached = Resolve();
                return s_cached;
            }
        }

        public static void ResetCache() => s_cached = null;

        private static string Resolve()
        {
            // command line -exoProfile <name>
            try
            {
                var args = Environment.GetCommandLineArgs();
                for (int i = 0; i < args.Length - 1; i++)
                {
                    if (string.Equals(args[i], "-exoProfile", StringComparison.OrdinalIgnoreCase))
                    {
                        var name = args[i + 1];
                        if (!string.IsNullOrWhiteSpace(name)) return name.Trim();
                    }
                }
            }
            catch { }

            // MPPM: environment variable fallback
            try
            {
                var mppm = Environment.GetEnvironmentVariable("UNITY_MPPM_PLAYER_ID");
                if (!string.IsNullOrWhiteSpace(mppm)) return mppm.Trim();
            }
            catch { }

            return "default";
        }

        public static bool IsDefault => string.Equals(Current, "default", StringComparison.Ordinal);

        public static string Suffix => IsDefault ? string.Empty : "." + Current;
    }
}