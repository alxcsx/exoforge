using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Linq;

namespace Exoforge.Management;

public class CliInstallResult
{
    public string ProjectRoot { get; set; } = "";
    public string PackageRoot { get; set; } = "";
    public List<string> UpdatedFiles { get; set; } = new();
    public bool WrapperInstalled { get; set; }
}

public static class ExoCliInstaller
{
    public const string GitignoreMarkerStart = "# >>> EXOFORGE-CLI:START";
    public const string GitignoreMarkerEnd = "# <<< EXOFORGE-CLI:END";

    public static CliInstallResult Install(string projectRoot, string? packageRootOverride = null)
    {
        string resolvedProject = Path.GetFullPath(projectRoot);
        if (Directory.GetParent(resolvedProject) != null &&
            Directory.Exists(Path.Combine(Directory.GetParent(resolvedProject)!.FullName, "Assets")))
        {
            resolvedProject = Directory.GetParent(resolvedProject)!.FullName;
        }

        var result = new CliInstallResult { ProjectRoot = resolvedProject, PackageRoot = packageRootOverride ?? "" };

        InstallWrappers(resolvedProject, result.UpdatedFiles);
        string exoforgeSubdir = Path.Combine(resolvedProject, "Exoforge");
        if (Directory.Exists(exoforgeSubdir))
        {
            InstallWrappers(exoforgeSubdir, result.UpdatedFiles);
        }

        var entries = new List<string> { "exo", "exo.cmd", "exo.ps1" };
        UpdateGitignore(resolvedProject, entries, result.UpdatedFiles);

        result.WrapperInstalled = File.Exists(Path.Combine(resolvedProject, "exo")) ||
                                  File.Exists(Path.Combine(resolvedProject, "exo.cmd"));
        return result;
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

        string normalizedSh = shContent.Replace("\r\n", "\n");
        if (!File.Exists(shPath) || !string.Equals(File.ReadAllText(shPath), normalizedSh, StringComparison.Ordinal))
        {
            File.WriteAllText(shPath, normalizedSh);
            MakeExecutable(shPath);
            updatedFiles.Add(shPath);
        }

        if (!File.Exists(cmdPath) || !string.Equals(File.ReadAllText(cmdPath), cmdContent, StringComparison.Ordinal))
        {
            File.WriteAllText(cmdPath, cmdContent);
            updatedFiles.Add(cmdPath);
        }
    }

    private static void UpdateGitignore(string projectRoot, IEnumerable<string> generatedEntries, List<string> updatedFiles)
    {
        var generatedSet = new HashSet<string>(
            generatedEntries.Where(e => !string.IsNullOrWhiteSpace(e)).Select(e => e.Trim()),
            StringComparer.Ordinal);

        if (generatedSet.Count == 0) return;

        string gitignorePath = Path.Combine(projectRoot, ".gitignore");
        if (!File.Exists(gitignorePath))
        {
            string block = GitignoreMarkerStart + "\n" + string.Join("\n", generatedSet) + "\n" + GitignoreMarkerEnd;
            File.WriteAllText(gitignorePath, block + "\n");
            updatedFiles.Add(gitignorePath);
            return;
        }

        string existing = File.ReadAllText(gitignorePath);
        int startIdx = existing.IndexOf(GitignoreMarkerStart, StringComparison.Ordinal);
        int endIdx = startIdx >= 0
            ? existing.IndexOf(GitignoreMarkerEnd, startIdx + GitignoreMarkerStart.Length, StringComparison.Ordinal)
            : -1;

        string desired;
        if (startIdx >= 0 && endIdx > startIdx)
        {
            int bodyStart = startIdx + GitignoreMarkerStart.Length;
            string existingBody = existing.Substring(bodyStart, endIdx - bodyStart);
            var merged = new HashSet<string>(generatedSet, StringComparer.Ordinal);
            foreach (string line in existingBody.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries))
            {
                string trimmed = line.Trim();
                if (trimmed.Length > 0 && !trimmed.StartsWith("#", StringComparison.Ordinal))
                    merged.Add(trimmed);
            }
            string block = GitignoreMarkerStart + "\n" + string.Join("\n", merged) + "\n" + GitignoreMarkerEnd;
            desired = existing.Substring(0, startIdx) + block + existing.Substring(endIdx + GitignoreMarkerEnd.Length);
        }
        else
        {
            string block = GitignoreMarkerStart + "\n" + string.Join("\n", generatedSet) + "\n" + GitignoreMarkerEnd;
            string trimmedExisting = existing.TrimEnd('\r', '\n');
            desired = string.IsNullOrEmpty(trimmedExisting)
                ? block + "\n"
                : trimmedExisting + "\n\n" + block + "\n";
        }

        if (!string.Equals(existing, desired, StringComparison.Ordinal))
        {
            File.WriteAllText(gitignorePath, desired);
            updatedFiles.Add(gitignorePath);
        }
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
        catch { }
    }
}