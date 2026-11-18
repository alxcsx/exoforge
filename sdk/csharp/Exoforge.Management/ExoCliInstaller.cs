using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;

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
    public const string GitignoreMarkerStart = ExoAgentInstaller.GitignoreMarkerStart;
    public const string GitignoreMarkerEnd = ExoAgentInstaller.GitignoreMarkerEnd;

    public static CliInstallResult Install(string projectRoot, string? packageRootOverride = null)
    {
        string resolvedProject = Path.GetFullPath(projectRoot);
        if (Directory.GetParent(resolvedProject) != null &&
            Directory.Exists(Path.Combine(Directory.GetParent(resolvedProject)!.FullName, "Assets")))
        {
            resolvedProject = Directory.GetParent(resolvedProject)!.FullName;
        }

        var result = new CliInstallResult { ProjectRoot = resolvedProject };

        // Write wrappers at project root (and Exoforge/ if present)
        InstallWrappers(resolvedProject, result.UpdatedFiles);
        string exoforgeSubdir = Path.Combine(resolvedProject, "Exoforge");
        if (Directory.Exists(exoforgeSubdir))
        {
            InstallWrappers(exoforgeSubdir, result.UpdatedFiles);
        }

        // Update gitignore block with only cli entries
        var entries = new List<string> { "exo", "exo.cmd", "exo.ps1" };
        ExoAgentInstaller.UpdateGitignorePublic(resolvedProject, entries, result.UpdatedFiles);

        result.WrapperInstalled = File.Exists(Path.Combine(resolvedProject, "exo")) ||
                                  File.Exists(Path.Combine(resolvedProject, "exo.cmd"));
        return result;
    }

    // Reuse wrapper writing logic by calling into ExoAgentInstaller's private? Instead duplicate via reflection not needed:
    // We'll keep a copy of InstallWrappers here by delegating to ExoAgentInstaller through a public shim.
    private static void InstallWrappers(string directory, List<string> updatedFiles)
    {
        ExoAgentInstaller.InstallWrappersPublic(directory, updatedFiles);
    }
}
