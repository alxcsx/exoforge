using System;
using System.Diagnostics;
using System.IO;
using Exoforge.Management;
using UnityEditor;
using UnityEngine;

namespace Exoforge.Unity.Editor
{
    /// <summary>
    /// Validates the .NET SDK installation (v9.0+) required for native C# backend extension builds.
    /// </summary>
    public static class ExoforgeDotnetValidator
    {
        public const string DotnetDownloadUrl = "https://dotnet.microsoft.com/download/dotnet/9.0";
        public const int MinimumRequiredMajorVersion = 9;

        public struct ValidationResult
        {
            public bool IsInstalled;
            public bool MeetsMinimumVersion;
            public string ResolvedPath;
            public string Version;
            public string Message;

            public bool IsValid => IsInstalled && MeetsMinimumVersion;
        }

        private static ValidationResult s_cachedResult;
        private static double s_lastCheckTime = -999.0;
        private static string s_lastConfiguredPath = "";

        /// <summary>
        /// Validates that the .NET SDK is installed and meets version requirements (.NET 9.0+).
        /// Caches results for up to 5 seconds unless forceFresh is true.
        /// </summary>
        public static ValidationResult Validate(string? configuredPath = null, bool forceFresh = false)
        {
            string config = configuredPath ?? ExoforgeEditorConfig.DotnetPath;
            double now = EditorApplication.timeSinceStartup;

            if (!forceFresh &&
                string.Equals(config, s_lastConfiguredPath, StringComparison.Ordinal) &&
                now - s_lastCheckTime < 5.0 &&
                !string.IsNullOrEmpty(s_cachedResult.ResolvedPath))
            {
                return s_cachedResult;
            }

            s_lastConfiguredPath = config;
            s_lastCheckTime = now;

            string resolved = ExoDeployer.ResolveDotnetPath(config);
            var res = new ValidationResult
            {
                ResolvedPath = resolved,
                Version = "",
                IsInstalled = false,
                MeetsMinimumVersion = false,
                Message = ""
            };

            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = resolved,
                    Arguments = "--version",
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                    CreateNoWindow = true
                };

                using var proc = Process.Start(psi);
                if (proc != null)
                {
                    string output = proc.StandardOutput.ReadToEnd().Trim();
                    proc.WaitForExit(3000);

                    if (proc.ExitCode == 0 && !string.IsNullOrWhiteSpace(output))
                    {
                        res.IsInstalled = true;
                        res.Version = output;

                        // Parse major version (e.g. "9.0.100" -> 9, "10.0.400" -> 10)
                        string[] parts = output.Split('.');
                        if (parts.Length > 0 && int.TryParse(parts[0].Trim(), out int major))
                        {
                            if (major >= MinimumRequiredMajorVersion)
                            {
                                res.MeetsMinimumVersion = true;
                                res.Message = $"✓ .NET SDK v{output} detected ({resolved})";
                            }
                            else
                            {
                                res.MeetsMinimumVersion = false;
                                res.Message = $"⚠️ Detected .NET SDK v{output}, but Exoforge requires .NET {MinimumRequiredMajorVersion}.0 or newer.";
                            }
                        }
                        else
                        {
                            res.MeetsMinimumVersion = true;
                            res.Message = $"✓ .NET SDK v{output} detected ({resolved})";
                        }
                    }
                    else
                    {
                        res.IsInstalled = false;
                        res.Message = $"⚠️ .NET CLI exited with code {proc.ExitCode} or produced no version output.";
                    }
                }
                else
                {
                    res.IsInstalled = false;
                    res.Message = "⚠️ Could not start .NET CLI process.";
                }
            }
            catch (Exception ex)
            {
                res.IsInstalled = false;
                res.Message = $"⚠️ .NET SDK not detected: {ex.Message}";
            }

            if (!res.IsInstalled)
            {
                res.Message = "⚠️ .NET SDK was not found on this computer. Native C# extension builds require the .NET SDK (v9.0+).";
            }

            s_cachedResult = res;
            return res;
        }

        /// <summary>
        /// Opens the official .NET SDK download page in the default web browser.
        /// </summary>
        public static void OpenDownloadPage()
        {
            Application.OpenURL(DotnetDownloadUrl);
        }

        /// <summary>
        /// Checks if .NET SDK is installed and meets requirements. If missing or obsolete,
        /// prompts the user with an interactive dialog offering a direct download link.
        /// Returns true if valid, false if missing.
        /// </summary>
        public static bool PromptIfMissing(string contextAction = "build C# backend extensions")
        {
            var res = Validate(forceFresh: true);
            if (res.IsValid) return true;

            string detail = !res.IsInstalled
                ? "The .NET SDK (dotnet) was not detected on this computer."
                : $"Detected .NET SDK v{res.Version}, but Exoforge requires .NET {MinimumRequiredMajorVersion}.0 or newer.";

            bool download = EditorUtility.DisplayDialog(
                ".NET SDK Required",
                $"{detail}\n\n" +
                $"Exoforge requires the .NET SDK ({MinimumRequiredMajorVersion}.0+) to {contextAction}.\n\n" +
                $"Would you like to open the official .NET download page now?",
                "Download .NET SDK",
                "Cancel");

            if (download)
            {
                OpenDownloadPage();
            }

            return false;
        }
    }
}
