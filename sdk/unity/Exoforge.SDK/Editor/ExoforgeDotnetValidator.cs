using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using Exoforge.Management;
using UnityEditor;
using UnityEngine;

namespace Exoforge.Unity.Editor
{
    /// <summary>
    /// Validates the .NET SDK and runtime installation (v9.0+) required for native C# backend extension builds.
    /// Checks SDK version, installed runtimes, host platform RID (e.g. win-x64, osx-arm64), and target server RID (linux-x64).
    /// </summary>
    public static class ExoforgeDotnetValidator
    {
        public const string DotnetDownloadUrl = "https://dotnet.microsoft.com/download/dotnet/9.0";
        public const int MinimumRequiredMajorVersion = 9;
        public const string StandardServerRid = "linux-x64";

        public struct ValidationResult
        {
            public bool IsInstalled;
            public bool MeetsMinimumVersion;
            public string ResolvedPath;
            public string Version;
            public string HostRid;
            public string TargetServerRid;
            public List<string> InstalledRuntimes;
            public List<string> InstalledSdks;
            public bool HasLocalRuntimePack;
            public bool HasLinuxRuntimePack;
            public string Message;

            public bool IsValid => IsInstalled && MeetsMinimumVersion;
        }

        private static ValidationResult s_cachedResult;
        private static double s_lastCheckTime = -999.0;
        private static string s_lastConfiguredPath = "";

        /// <summary>
        /// Validates that the .NET SDK is installed, meets version requirements (.NET 9.0+),
        /// discovers installed runtimes, and inspects host and server target RIDs.
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
            string hostRid = ExoDeployer.HostRuntimeIdentifier();

            var res = new ValidationResult
            {
                ResolvedPath = resolved,
                Version = "",
                HostRid = hostRid,
                TargetServerRid = StandardServerRid,
                InstalledRuntimes = new List<string>(),
                InstalledSdks = new List<string>(),
                IsInstalled = false,
                MeetsMinimumVersion = false,
                HasLocalRuntimePack = IsRuntimePackCached(hostRid, MinimumRequiredMajorVersion),
                HasLinuxRuntimePack = IsRuntimePackCached(StandardServerRid, MinimumRequiredMajorVersion),
                Message = ""
            };

            try
            {
                // 1. Check SDK version
                var psiVersion = new ProcessStartInfo
                {
                    FileName = resolved,
                    Arguments = "--version",
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                    CreateNoWindow = true
                };

                using (var proc = Process.Start(psiVersion))
                {
                    if (proc != null)
                    {
                        string output = proc.StandardOutput.ReadToEnd().Trim();
                        proc.WaitForExit(3000);

                        if (proc.ExitCode == 0 && !string.IsNullOrWhiteSpace(output))
                        {
                            res.IsInstalled = true;
                            res.Version = output;

                            string[] parts = output.Split('.');
                            if (parts.Length > 0 && int.TryParse(parts[0].Trim(), out int major))
                            {
                                res.MeetsMinimumVersion = major >= MinimumRequiredMajorVersion;
                            }
                            else
                            {
                                res.MeetsMinimumVersion = true;
                            }
                        }
                    }
                }

                // 2. Query .NET runtimes and SDKs via `dotnet --info`
                if (res.IsInstalled)
                {
                    QueryDotnetInfo(resolved, ref res);
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
            else if (!res.MeetsMinimumVersion)
            {
                res.Message = $"⚠️ Detected .NET SDK v{res.Version}, but Exoforge requires .NET {MinimumRequiredMajorVersion}.0 or newer.";
            }
            else
            {
                string runtimesSummary = res.InstalledRuntimes.Count > 0
                    ? string.Join(", ", res.InstalledRuntimes)
                    : "Standard .NET runtime";

                res.Message = $"✓ .NET SDK v{res.Version} ({res.HostRid}) | Runtimes: {runtimesSummary} | Target Server: {res.TargetServerRid}";
            }

            s_cachedResult = res;
            return res;
        }

        private static void QueryDotnetInfo(string resolvedPath, ref ValidationResult res)
        {
            try
            {
                var psiInfo = new ProcessStartInfo
                {
                    FileName = resolvedPath,
                    Arguments = "--info",
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                    CreateNoWindow = true
                };

                using var proc = Process.Start(psiInfo);
                if (proc == null) return;

                string line;
                bool inRuntimes = false;
                bool inSdks = false;

                while ((line = proc.StandardOutput.ReadLine()) != null)
                {
                    string trimmed = line.Trim();

                    if (trimmed.StartsWith("RID:", StringComparison.OrdinalIgnoreCase))
                    {
                        string[] parts = trimmed.Split(new[] { ':' }, 2);
                        if (parts.Length == 2 && !string.IsNullOrWhiteSpace(parts[1]))
                        {
                            res.HostRid = parts[1].Trim();
                            res.HasLocalRuntimePack = IsRuntimePackCached(res.HostRid, MinimumRequiredMajorVersion);
                        }
                        continue;
                    }

                    if (trimmed.StartsWith(".NET runtimes installed:", StringComparison.OrdinalIgnoreCase))
                    {
                        inRuntimes = true;
                        inSdks = false;
                        continue;
                    }

                    if (trimmed.StartsWith(".NET SDKs installed:", StringComparison.OrdinalIgnoreCase))
                    {
                        inSdks = true;
                        inRuntimes = false;
                        continue;
                    }

                    if (string.IsNullOrEmpty(trimmed) || (trimmed.EndsWith(":") && !trimmed.Contains(" ")))
                    {
                        inRuntimes = false;
                        inSdks = false;
                    }

                    if (inRuntimes && trimmed.StartsWith("Microsoft.NETCore.App", StringComparison.OrdinalIgnoreCase))
                    {
                        int bracket = trimmed.IndexOf('[');
                        string display = bracket > 0 ? trimmed.Substring(0, bracket).Trim() : trimmed;
                        if (!res.InstalledRuntimes.Contains(display))
                        {
                            res.InstalledRuntimes.Add(display);
                        }
                    }
                    else if (inSdks && !string.IsNullOrEmpty(trimmed))
                    {
                        int bracket = trimmed.IndexOf('[');
                        string display = bracket > 0 ? trimmed.Substring(0, bracket).Trim() : trimmed;
                        if (!res.InstalledSdks.Contains(display))
                        {
                            res.InstalledSdks.Add(display);
                        }
                    }
                }

                proc.WaitForExit(3000);
            }
            catch
            {
                // Best effort
            }
        }

        /// <summary>
        /// Checks if a Microsoft.NETCore.App.Runtime pack for the given RID is cached in local NuGet packages.
        /// </summary>
        public static bool IsRuntimePackCached(string rid, int minMajor = MinimumRequiredMajorVersion)
        {
            try
            {
                string userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
                string packDir = Path.Combine(userProfile, ".nuget", "packages", $"microsoft.netcore.app.runtime.{rid.ToLowerInvariant()}");
                if (!Directory.Exists(packDir)) return false;

                var versions = Directory.GetDirectories(packDir);
                foreach (var v in versions)
                {
                    string vName = Path.GetFileName(v);
                    string[] parts = vName.Split('.');
                    if (parts.Length > 0 && int.TryParse(parts[0], out int major) && major >= minMajor)
                    {
                        return true;
                    }
                }
            }
            catch
            {
                // Best effort
            }

            return false;
        }

        /// <summary>
        /// Restores and pre-warms runtime packs for the target RIDs (e.g. host RID and "linux-x64")
        /// from official nuget.org so framework-dependent extension builds succeed without NETSDK1112 errors.
        /// </summary>
        public static bool PrewarmRuntimePacks(string? targetRid = null, string? dotnetPath = null, Action<string>? log = null)
        {
            string dotnet = ExoDeployer.ResolveDotnetPath(dotnetPath ?? ExoforgeEditorConfig.DotnetPath);
            string ridsToRestore = targetRid ?? $"{ExoDeployer.HostRuntimeIdentifier()},{StandardServerRid}";
            string[] rids = ridsToRestore.Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries);

            bool allOk = true;

            foreach (var r in rids)
            {
                string cleanRid = r.Trim();
                if (string.IsNullOrEmpty(cleanRid)) continue;

                log?.Invoke($"[Prewarm] Restoring runtime pack for target RID '{cleanRid}'...");

                try
                {
                    // Create a minimal temporary project to trigger runtime pack download
                    string tempDir = Path.Combine(Path.GetTempPath(), "exoforge_runtime_probe_" + Guid.NewGuid().ToString("N"));
                    Directory.CreateDirectory(tempDir);

                    try
                    {
                        string tempCsproj = Path.Combine(tempDir, "runtime_probe.csproj");
                        string tempNuget = Path.Combine(tempDir, "nuget.config");

                        File.WriteAllText(tempCsproj,
                            "<Project Sdk=\"Microsoft.NET.Sdk\">\n" +
                            "  <PropertyGroup>\n" +
                            "    <TargetFramework>net9.0</TargetFramework>\n" +
                            "    <OutputType>Exe</OutputType>\n" +
                            "  </PropertyGroup>\n" +
                            "</Project>\n");

                        File.WriteAllText(tempNuget,
                            "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n" +
                            "<configuration>\n" +
                            "  <packageSources>\n" +
                            "    <add key=\"nuget.org\" value=\"https://api.nuget.org/v3/index.json\" protocolVersion=\"3\" />\n" +
                            "  </packageSources>\n" +
                            "</configuration>\n");

                        var psi = new ProcessStartInfo
                        {
                            FileName = dotnet,
                            Arguments = $"restore \"{tempCsproj}\" -r {cleanRid}",
                            WorkingDirectory = tempDir,
                            RedirectStandardOutput = true,
                            RedirectStandardError = true,
                            UseShellExecute = false,
                            CreateNoWindow = true
                        };

                        using var proc = Process.Start(psi);
                        if (proc != null)
                        {
                            string outText = proc.StandardOutput.ReadToEnd();
                            string errText = proc.StandardError.ReadToEnd();
                            proc.WaitForExit(30000);

                            if (proc.ExitCode == 0)
                            {
                                log?.Invoke($"✓ Runtime pack for '{cleanRid}' successfully restored and cached.");
                            }
                            else
                            {
                                log?.Invoke($"⚠️ Restore for '{cleanRid}' returned exit code {proc.ExitCode}:\n{outText}\n{errText}");
                                allOk = false;
                            }
                        }
                    }
                    finally
                    {
                        try { Directory.Delete(tempDir, true); } catch { }
                    }
                }
                catch (Exception ex)
                {
                    log?.Invoke($"⚠️ Failed to restore runtime pack for '{cleanRid}': {ex.Message}");
                    allOk = false;
                }
            }

            s_cachedResult = default; // Invalidate cache
            return allOk;
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
                $"Host Platform: {res.HostRid}\n" +
                $"Target Server: {StandardServerRid}\n\n" +
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
