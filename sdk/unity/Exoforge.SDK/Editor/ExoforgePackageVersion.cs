using System;
using System.Diagnostics;
using System.IO;

namespace Exoforge.Unity.Editor
{
    /// <summary>
    /// Package version and build information (version, git hash, build date)
    /// for the Exoforge Unity SDK.
    /// </summary>
    public static class ExoforgePackageVersion
    {
        public const string SdkVersion = "0.1.0";
        public const string DefaultBuildHash = "35630a3";
        public const string DefaultBuildDate = "2026-11-03 10:07";

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
