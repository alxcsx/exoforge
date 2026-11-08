using System;
using System.Diagnostics;
using System.IO;

namespace Exoforge.Unity.Editor
{
    public enum SdkCompatibilityStatus
    {
        Unknown,
        UpToDate,
        UpdateAvailable,
        Ahead
    }

    /// <summary>
    /// Package version and build information (version, git hash, build date)
    /// for the Exoforge Unity SDK.
    /// </summary>
    public static class ExoforgePackageVersion
    {
        public const string SdkVersion = "0.1.29";
        public const string DefaultBuildHash = "6be4ec5";
        public const string DefaultBuildDate = "2026-11-06 16:08";

        private static string? s_resolvedHash;
        private static string? s_resolvedDate;
        private static bool s_probed;

        public static string BuildHash
        {
            get
            {
                if (!s_probed) ResolveBuildInfo();
                return s_resolvedHash ?? DefaultBuildHash;
            }
        }

        public static string BuildDate
        {
            get
            {
                if (!s_probed) ResolveBuildInfo();
                return s_resolvedDate ?? DefaultBuildDate;
            }
        }

        public static string Formatted => $"v{SdkVersion} (#{BuildHash})";

        /// <summary>Compares the local SDK version against a remote version string and commit hash.</summary>
        public static SdkCompatibilityStatus Compare(string? remoteVersion, string? remoteHash = null)
        {
            if (string.IsNullOrWhiteSpace(remoteVersion) || remoteVersion == "—")
                return SdkCompatibilityStatus.Unknown;

            string cleanRemote = CleanSemVer(remoteVersion);
            string cleanLocal = CleanSemVer(SdkVersion);

            if (System.Version.TryParse(cleanRemote, out var rVer) &&
                System.Version.TryParse(cleanLocal, out var lVer))
            {
                if (rVer > lVer) return SdkCompatibilityStatus.UpdateAvailable;
                if (rVer < lVer) return SdkCompatibilityStatus.Ahead;

                return SdkCompatibilityStatus.UpToDate;
            }

            if (string.Equals(remoteVersion.Trim(), SdkVersion.Trim(), StringComparison.OrdinalIgnoreCase))
            {
                return SdkCompatibilityStatus.UpToDate;
            }

            return SdkCompatibilityStatus.UpdateAvailable;
        }

        private static string CleanSemVer(string v)
        {
            v = v.Trim().TrimStart('v', 'V');
            int dash = v.IndexOf('-');
            if (dash > 0) v = v[..dash];
            int plus = v.IndexOf('+');
            if (plus > 0) v = v[..plus];
            return v;
        }

        private static void ResolveBuildInfo()
        {
            s_probed = true;
            try
            {
                using var pHash = new Process();
                pHash.StartInfo = new ProcessStartInfo("git", "rev-parse --short HEAD")
                {
                    RedirectStandardOutput = true,
                    UseShellExecute = false,
                    CreateNoWindow = true
                };
                if (pHash.Start() && pHash.WaitForExit(1000))
                {
                    string output = pHash.StandardOutput.ReadToEnd().Trim();
                    if (!string.IsNullOrEmpty(output) && output.Length >= 4 && !output.Contains("fatal"))
                    {
                        s_resolvedHash = output;
                    }
                }

                using var pDate = new Process();
                pDate.StartInfo = new ProcessStartInfo("git", "log -1 --format=%cd --date=format:%Y-%m-%d\\ %H:%M")
                {
                    RedirectStandardOutput = true,
                    UseShellExecute = false,
                    CreateNoWindow = true
                };
                if (pDate.Start() && pDate.WaitForExit(1000))
                {
                    string output = pDate.StandardOutput.ReadToEnd().Trim();
                    if (!string.IsNullOrEmpty(output) && !output.Contains("fatal"))
                    {
                        s_resolvedDate = output;
                    }
                }
            }
            catch
            {
                // Fallback to static defaults
            }

            s_resolvedHash ??= DefaultBuildHash;
            s_resolvedDate ??= DefaultBuildDate;
        }
    }
}
