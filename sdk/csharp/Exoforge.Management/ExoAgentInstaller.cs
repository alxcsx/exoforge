using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.Json.Serialization;

namespace Exoforge.Management;

public class AgentInstallResult
{
    [JsonPropertyName("project_root")]
    public string ProjectRoot { get; set; } = "";

    [JsonPropertyName("package_root")]
    public string PackageRoot { get; set; } = "";

    [JsonPropertyName("cli_available")]
    public bool CliAvailable { get; set; }

    [JsonPropertyName("installed_skills")]
    public List<string> InstalledSkills { get; set; } = new();

    [JsonPropertyName("updated_files")]
    public List<string> UpdatedFiles { get; set; } = new();
}

public class AgentStatusResult
{
    [JsonPropertyName("project_root")]
    public string ProjectRoot { get; set; } = "";

    [JsonPropertyName("package_root")]
    public string? PackageRoot { get; set; }

    [JsonPropertyName("cli_available")]
    public bool CliAvailable { get; set; }

    [JsonPropertyName("agents_guide_installed")]
    public bool AgentsGuideInstalled { get; set; }

    [JsonPropertyName("wrapper_installed")]
    public bool WrapperInstalled { get; set; }

    [JsonPropertyName("checks")]
    public List<string> Checks { get; set; } = new();

    [JsonPropertyName("installed_skills")]
    public List<string> InstalledSkills { get; set; } = new();
}

public static class ExoAgentInstaller
{
    public const string MarkerStart = "<!-- EXOFORGE-AGENT-GUIDE:START -->";
    public const string MarkerEnd = "<!-- EXOFORGE-AGENT-GUIDE:END -->";
    public const string GenericMarker = "<!-- EXOFORGE-AGENT-GUIDE";

    public static string? FindPackageRoot(string? startDir = null)
    {
        if (!string.IsNullOrEmpty(startDir) && IsPackageRoot(startDir))
        {
            return Path.GetFullPath(startDir);
        }

        // 1. AppContext.BaseDirectory and ancestors (when running via Editor/Cli~/exo.dll)
        string? baseDir = AppContext.BaseDirectory;
        if (!string.IsNullOrEmpty(baseDir))
        {
            var dir = new DirectoryInfo(baseDir);
            while (dir != null)
            {
                if (IsPackageRoot(dir.FullName))
                {
                    return dir.FullName;
                }
                dir = dir.Parent;
            }
        }

        // 2. <projectRoot>/Packages/com.exoforge.sdk
        if (!string.IsNullOrEmpty(startDir))
        {
            string pkgPath = Path.Combine(startDir, "Packages", "com.exoforge.sdk");
            if (IsPackageRoot(pkgPath))
            {
                return Path.GetFullPath(pkgPath);
            }

            // 3. <projectRoot>/Library/PackageCache/com.exoforge.sdk@*
            string cacheDir = Path.Combine(startDir, "Library", "PackageCache");
            if (Directory.Exists(cacheDir))
            {
                try
                {
                    var matches = Directory.GetDirectories(cacheDir, "com.exoforge.sdk*");
                    foreach (var match in matches)
                    {
                        if (IsPackageRoot(match))
                        {
                            return Path.GetFullPath(match);
                        }
                    }
                }
                catch { }
            }
        }

        // 4. Dev/test in monorepo (<repoRoot>/sdk/unity/Exoforge.SDK or ancestors)
        var searchBases = new List<string>();
        if (!string.IsNullOrEmpty(startDir)) searchBases.Add(startDir);
        searchBases.Add(Directory.GetCurrentDirectory());
        if (!string.IsNullOrEmpty(AppContext.BaseDirectory)) searchBases.Add(AppContext.BaseDirectory);

        foreach (var searchBase in searchBases)
        {
            var repoScan = new DirectoryInfo(Path.GetFullPath(searchBase));
            while (repoScan != null)
            {
                string monorepoCandidate = Path.Combine(repoScan.FullName, "sdk", "unity", "Exoforge.SDK");
                if (IsPackageRoot(monorepoCandidate))
                {
                    return Path.GetFullPath(monorepoCandidate);
                }

                string distCandidate = Path.Combine(repoScan.FullName, "dist", "package");
                if (IsPackageRoot(distCandidate))
                {
                    return Path.GetFullPath(distCandidate);
                }

                repoScan = repoScan.Parent;
            }
        }

        return null;
    }

    private static bool IsPackageRoot(string dir)
    {
        if (string.IsNullOrEmpty(dir) || !Directory.Exists(dir)) return false;
        if (Directory.Exists(Path.Combine(dir, "Agents~"))) return true;
        string pkgJson = Path.Combine(dir, "package.json");
        if (File.Exists(pkgJson))
        {
            try
            {
                string content = File.ReadAllText(pkgJson);
                if (content.Contains("\"name\": \"com.exoforge.sdk\"") || content.Contains("\"name\":\"com.exoforge.sdk\""))
                    return true;
            }
            catch { }
        }
        return false;
    }

    public static AgentInstallResult Install(string projectRoot, string target = "all", string? packageRootOverride = null)
    {
        string resolvedProject = Path.GetFullPath(projectRoot);

        // If pointing to <game>/Exoforge, step up to <game> if parent has Assets/
        if (Directory.GetParent(resolvedProject) != null &&
            Directory.Exists(Path.Combine(Directory.GetParent(resolvedProject)!.FullName, "Assets")))
        {
            resolvedProject = Directory.GetParent(resolvedProject)!.FullName;
        }

        string? pkgRoot = packageRootOverride ?? FindPackageRoot(resolvedProject);
        if (string.IsNullOrEmpty(pkgRoot) || !Directory.Exists(pkgRoot))
        {
            throw new DirectoryNotFoundException(
                $"Could not locate com.exoforge.sdk package root containing Agents~ or package.json from '{resolvedProject}'.");
        }

        var result = new AgentInstallResult
        {
            ProjectRoot = resolvedProject,
            PackageRoot = pkgRoot
        };

        // 1. Copy skills
        string packageSkillsDir = Path.Combine(pkgRoot, "Agents~", "skills");
        if (Directory.Exists(packageSkillsDir))
        {
            var skillDirs = Directory.GetDirectories(packageSkillsDir);
            var targetFolders = new List<string>();

            string t = target.Trim().ToLowerInvariant();
            if (t == "all")
            {
                targetFolders.Add(".agents/skills");
                targetFolders.Add(".claude/skills");
                targetFolders.Add(".gemini/skills");
            }
            else if (t == "agents")
            {
                targetFolders.Add(".agents/skills");
            }
            else if (t == "claude")
            {
                targetFolders.Add(".claude/skills");
            }
            else if (t == "gemini")
            {
                targetFolders.Add(".gemini/skills");
            }
            else
            {
                targetFolders.Add($".{t}/skills");
            }

            var installedSkillNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            foreach (var skillPath in skillDirs)
            {
                string skillName = Path.GetFileName(skillPath);
                installedSkillNames.Add(skillName);

                foreach (var tf in targetFolders)
                {
                    string destSkillDir = Path.Combine(resolvedProject, tf, skillName);
                    CopyDirectoryRecursively(skillPath, destSkillDir, result.UpdatedFiles);
                }
            }

            result.InstalledSkills = installedSkillNames.OrderBy(s => s).ToList();
        }

        // 2. Install / Update AGENTS.md
        string srcAgentsMd = Path.Combine(pkgRoot, "Agents~", "AGENTS.md");
        if (File.Exists(srcAgentsMd))
        {
            string guideContent = File.ReadAllText(srcAgentsMd);
            string destAgentsMd = Path.Combine(resolvedProject, "AGENTS.md");

            if (!File.Exists(destAgentsMd))
            {
                File.WriteAllText(destAgentsMd, guideContent);
                result.UpdatedFiles.Add(destAgentsMd);
            }
            else
            {
                string existing = File.ReadAllText(destAgentsMd);

                if (existing.Contains(MarkerStart) && existing.Contains(MarkerEnd))
                {
                    int startIdx = existing.IndexOf(MarkerStart, StringComparison.Ordinal);
                    int endIdx = existing.IndexOf(MarkerEnd, StringComparison.Ordinal) + MarkerEnd.Length;
                    string updated = existing.Substring(0, startIdx) + guideContent.Trim() + existing.Substring(endIdx);
                    File.WriteAllText(destAgentsMd, updated);
                    result.UpdatedFiles.Add(destAgentsMd);
                }
                else if (existing.Contains(GenericMarker))
                {
                    int startIdx = existing.IndexOf(GenericMarker, StringComparison.Ordinal);
                    string updated = existing.Substring(0, startIdx) + guideContent.Trim() + "\n";
                    File.WriteAllText(destAgentsMd, updated);
                    result.UpdatedFiles.Add(destAgentsMd);
                }
                else
                {
                    string appended = existing.TrimEnd() + "\n\n" + guideContent;
                    File.WriteAllText(destAgentsMd, appended);
                    result.UpdatedFiles.Add(destAgentsMd);
                }
            }
        }

        // 3. Create ./exo and ./exo.cmd wrappers
        InstallWrappers(resolvedProject, result.UpdatedFiles);

        string exoforgeSubdir = Path.Combine(resolvedProject, "Exoforge");
        if (Directory.Exists(exoforgeSubdir))
        {
            InstallWrappers(exoforgeSubdir, result.UpdatedFiles);
        }

        // 4. Check if CLI is available
        result.CliAvailable = CheckCliAvailability(resolvedProject, pkgRoot);

        return result;
    }

    public static AgentStatusResult GetStatus(string projectRoot, string? packageRootOverride = null)
    {
        string resolvedProject = Path.GetFullPath(projectRoot);
        if (Directory.GetParent(resolvedProject) != null &&
            Directory.Exists(Path.Combine(Directory.GetParent(resolvedProject)!.FullName, "Assets")))
        {
            resolvedProject = Directory.GetParent(resolvedProject)!.FullName;
        }

        string? pkgRoot = packageRootOverride ?? FindPackageRoot(resolvedProject);
        bool cliAvailable = CheckCliAvailability(resolvedProject, pkgRoot);

        string agentsMd = Path.Combine(resolvedProject, "AGENTS.md");
        bool hasGuide = false;
        if (File.Exists(agentsMd))
        {
            string content = File.ReadAllText(agentsMd);
            hasGuide = content.Contains("EXOFORGE-AGENT-GUIDE") || content.Contains("Exoforge Agent Operating Guide");
        }

        bool hasWrapper = File.Exists(Path.Combine(resolvedProject, "exo")) ||
                          File.Exists(Path.Combine(resolvedProject, "exo.cmd"));

        var skills = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var sub in new[] { ".agents/skills", ".claude/skills", ".gemini/skills" })
        {
            string p = Path.Combine(resolvedProject, sub);
            if (Directory.Exists(p))
            {
                foreach (var d in Directory.GetDirectories(p))
                {
                    skills.Add(Path.GetFileName(d));
                }
            }
        }

        var checks = new List<string>
        {
            cliAvailable ? "[✓] Embedded CLI binary: Available" : "[✗] Embedded CLI binary: Missing (expected at Editor/Cli~/exo.dll)",
            hasWrapper ? "[✓] Project root CLI wrapper (exo / exo.cmd): Present" : "[!] Project root CLI wrapper: Not installed",
            hasGuide ? "[✓] Project AGENTS.md guide: Configured" : "[!] Project AGENTS.md guide: Missing or unconfigured",
            skills.Count > 0 ? $"[✓] Project agent skills: {skills.Count} installed" : "[!] Project agent skills: None installed"
        };

        return new AgentStatusResult
        {
            ProjectRoot = resolvedProject,
            PackageRoot = pkgRoot,
            CliAvailable = cliAvailable,
            AgentsGuideInstalled = hasGuide,
            WrapperInstalled = hasWrapper,
            Checks = checks,
            InstalledSkills = skills.OrderBy(s => s).ToList()
        };
    }

    private static void CopyDirectoryRecursively(string sourceDir, string targetDir, List<string> updatedFiles)
    {
        Directory.CreateDirectory(targetDir);

        foreach (string file in Directory.GetFiles(sourceDir))
        {
            string fileName = Path.GetFileName(file);
            string destFile = Path.Combine(targetDir, fileName);
            File.Copy(file, destFile, overwrite: true);
            updatedFiles.Add(destFile);
        }

        foreach (string subDir in Directory.GetDirectories(sourceDir))
        {
            string subDirName = Path.GetFileName(subDir);
            CopyDirectoryRecursively(subDir, Path.Combine(targetDir, subDirName), updatedFiles);
        }
    }

    private static void InstallWrappers(string directory, List<string> updatedFiles)
    {
        string shPath = Path.Combine(directory, "exo");
        string cmdPath = Path.Combine(directory, "exo.cmd");

        const string shContent = """
        #!/usr/bin/env bash
        set -e

        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

        # Locate exo.dll
        DLL_PATH=""
        if [ -f "$SCRIPT_DIR/Packages/com.exoforge.sdk/Editor/Cli~/exo.dll" ]; then
            DLL_PATH="$SCRIPT_DIR/Packages/com.exoforge.sdk/Editor/Cli~/exo.dll"
        elif [ -f "$SCRIPT_DIR/../Packages/com.exoforge.sdk/Editor/Cli~/exo.dll" ]; then
            DLL_PATH="$SCRIPT_DIR/../Packages/com.exoforge.sdk/Editor/Cli~/exo.dll"
        elif ls "$SCRIPT_DIR"/Library/PackageCache/com.exoforge.sdk@*/Editor/Cli~/exo.dll 1> /dev/null 2>&1; then
            DLL_PATH=$(ls "$SCRIPT_DIR"/Library/PackageCache/com.exoforge.sdk@*/Editor/Cli~/exo.dll | head -n 1)
        elif ls "$SCRIPT_DIR"/../Library/PackageCache/com.exoforge.sdk@*/Editor/Cli~/exo.dll 1> /dev/null 2>&1; then
            DLL_PATH=$(ls "$SCRIPT_DIR"/../Library/PackageCache/com.exoforge.sdk@*/Editor/Cli~/exo.dll | head -n 1)
        elif [ -f "$SCRIPT_DIR/Editor/Cli~/exo.dll" ]; then
            DLL_PATH="$SCRIPT_DIR/Editor/Cli~/exo.dll"
        elif [ -f "$SCRIPT_DIR/sdk/csharp/Exoforge.Cli/bin/Release/net10.0/exo.dll" ]; then
            DLL_PATH="$SCRIPT_DIR/sdk/csharp/Exoforge.Cli/bin/Release/net10.0/exo.dll"
        elif [ -f "$SCRIPT_DIR/../sdk/csharp/Exoforge.Cli/bin/Release/net10.0/exo.dll" ]; then
            DLL_PATH="$SCRIPT_DIR/../sdk/csharp/Exoforge.Cli/bin/Release/net10.0/exo.dll"
        fi

        if [ -z "$DLL_PATH" ] || [ ! -f "$DLL_PATH" ]; then
            echo "Error: Exoforge CLI (exo.dll) not found in Packages/com.exoforge.sdk or Library/PackageCache." >&2
            echo "Ensure com.exoforge.sdk is installed in this Unity project." >&2
            exit 1
        fi

        HAS_DIR=false
        for arg in "$@"; do
            if [ "$arg" = "--dir" ]; then
                HAS_DIR=true
                break
            fi
        done

        if [ "$HAS_DIR" = true ]; then
            exec dotnet "$DLL_PATH" "$@"
        else
            WORKSPACE_DIR="$SCRIPT_DIR"
            if [ -d "$SCRIPT_DIR/Exoforge" ]; then
                WORKSPACE_DIR="$SCRIPT_DIR/Exoforge"
            fi
            exec dotnet "$DLL_PATH" "$@" --dir "$WORKSPACE_DIR"
        fi
        """;

        const string cmdContent = """
        @echo off
        setlocal enabledelayedexpansion

        set "SCRIPT_DIR=%~dp0"
        set "DLL_PATH="

        if exist "%SCRIPT_DIR%Packages\com.exoforge.sdk\Editor\Cli~\exo.dll" (
            set "DLL_PATH=%SCRIPT_DIR%Packages\com.exoforge.sdk\Editor\Cli~\exo.dll"
        ) else if exist "%SCRIPT_DIR%..\Packages\com.exoforge.sdk\Editor\Cli~\exo.dll" (
            set "DLL_PATH=%SCRIPT_DIR%..\Packages\com.exoforge.sdk\Editor\Cli~\exo.dll"
        ) else (
            for /d %%D in ("%SCRIPT_DIR%Library\PackageCache\com.exoforge.sdk@*") do (
                if exist "%%D\Editor\Cli~\exo.dll" set "DLL_PATH=%%D\Editor\Cli~\exo.dll"
            )
            if "!DLL_PATH!"=="" (
                for /d %%D in ("%SCRIPT_DIR%..\Library\PackageCache\com.exoforge.sdk@*") do (
                    if exist "%%D\Editor\Cli~\exo.dll" set "DLL_PATH=%%D\Editor\Cli~\exo.dll"
                )
            )
        )

        if "%DLL_PATH%"=="" (
            if exist "%SCRIPT_DIR%Editor\Cli~\exo.dll" set "DLL_PATH=%SCRIPT_DIR%Editor\Cli~\exo.dll"
        )

        if "%DLL_PATH%"=="" (
            echo Error: Exoforge CLI ^(exo.dll^) not found in Packages or Library\PackageCache. >&2
            exit /b 1
        )

        set "HAS_DIR="
        for %%A in (%*) do (
            if "%%~A"=="--dir" set "HAS_DIR=1"
        )

        if defined HAS_DIR (
            dotnet "%DLL_PATH%" %*
        ) else (
            set "WORKSPACE_DIR=%SCRIPT_DIR%"
            if exist "%SCRIPT_DIR%Exoforge" set "WORKSPACE_DIR=%SCRIPT_DIR%Exoforge"
            dotnet "%DLL_PATH%" %* --dir "!WORKSPACE_DIR!"
        )
        """;

        File.WriteAllText(shPath, shContent.Replace("\r\n", "\n"));
        MakeExecutable(shPath);
        updatedFiles.Add(shPath);

        File.WriteAllText(cmdPath, cmdContent);
        updatedFiles.Add(cmdPath);
    }

    private static void MakeExecutable(string filePath)
    {
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows)) return;

        try
        {
            var psi = new ProcessStartInfo("chmod", $"+x \"{filePath}\"")
            {
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            using var process = Process.Start(psi);
            process?.WaitForExit();
        }
        catch
        {
            // Ignore if chmod command is unavailable
        }
    }

    private static bool CheckCliAvailability(string projectRoot, string? packageRoot)
    {
        if (!string.IsNullOrEmpty(packageRoot) && File.Exists(Path.Combine(packageRoot, "Editor", "Cli~", "exo.dll")))
            return true;
        if (File.Exists(Path.Combine(projectRoot, "Packages", "com.exoforge.sdk", "Editor", "Cli~", "exo.dll")))
            return true;
        string cache = Path.Combine(projectRoot, "Library", "PackageCache");
        if (Directory.Exists(cache))
        {
            try
            {
                foreach (var d in Directory.GetDirectories(cache, "com.exoforge.sdk*"))
                {
                    if (File.Exists(Path.Combine(d, "Editor", "Cli~", "exo.dll")))
                        return true;
                }
            }
            catch { }
        }
        return false;
    }
}
