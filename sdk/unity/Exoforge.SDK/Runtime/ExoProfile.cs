using System;
using Exoforge.Client;
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
                s_cached = ExoProfileResolver.Resolve(Environment.GetCommandLineArgs(), Application.dataPath);
                return s_cached;
            }
        }

        public static void ResetCache() => s_cached = null;

        public static bool IsDefault => string.Equals(Current, "default", StringComparison.Ordinal);

        public static string Suffix => IsDefault ? string.Empty : "." + Current;
    }
}