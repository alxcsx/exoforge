using System;

namespace Exoforge.Client
{
    public static class ExoProfileResolver
    {
        public const int MaxNameLength = 32;

        public static string Resolve(string[] args, string dataPath)
        {
            if (args != null)
            {
                for (int i = 0; i < args.Length - 1; i++)
                {
                    if (string.Equals(args[i], "-exoProfile", StringComparison.OrdinalIgnoreCase))
                    {
                        var candidate = args[i + 1];
                        if (IsValid(candidate)) return candidate.Trim();
                    }
                }
            }

            if (!string.IsNullOrEmpty(dataPath))
            {
                var normalized = dataPath.Replace('\\', '/');
                var segments = normalized.Split(new[] { '/' }, StringSplitOptions.RemoveEmptyEntries);
                for (int i = 0; i + 2 < segments.Length; i++)
                {
                    if (segments[i] == "Library" && segments[i + 1] == "VP")
                    {
                        var id = segments[i + 2];
                        if (IsValid(id)) return id;
                    }
                }
            }

            return "default";
        }

        public static bool IsValid(string? name)
        {
            if (string.IsNullOrWhiteSpace(name)) return false;
            var trimmed = name.Trim();
            if (trimmed.Length == 0 || trimmed.Length > MaxNameLength) return false;
            foreach (char c in trimmed)
            {
                bool isAscii = (c >= 'A' && c <= 'Z')
                    || (c >= 'a' && c <= 'z')
                    || (c >= '0' && c <= '9')
                    || c == '-'
                    || c == '_';
                if (!isAscii) return false;
            }
            return true;
        }

        public static string SuffixFor(string profile) =>
            string.Equals(profile, "default", StringComparison.Ordinal) ? string.Empty : "." + profile;

        public static string DeviceSeed(string hardwareSeed, string profile) =>
            string.Equals(profile, "default", StringComparison.Ordinal) ? hardwareSeed : hardwareSeed + ":" + profile;
    }
}