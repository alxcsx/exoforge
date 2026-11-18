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

    public const string GitignoreMarkerStart = "# >>> EXOFORGE-AGENT-TOOLING:START";
    public const string GitignoreMarkerEnd = "# <<< EXOFORGE-AGENT-TOOLING:END";

    private static readonly string[] CanonicalGitignoreOrder =
    {
        ".agents/",
        ".claude/",
        ".gemini/",
        "AGENTS.md",
        "exo",
        "exo.cmd",
        "exo.ps1"
    };

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
        var targets = string.IsNullOrWhiteSpace(target)
            ? Array.Empty<string>()
            : new[] { target };
        return Install(projectRoot, (IEnumerable<string>)targets, packageRootOverride);
    }

    public static AgentInstallResult Install(string projectRoot, IEnumerable<string> targets, string? packageRootOverride = null)
    {
        if (targets == null)
        {
            throw new ArgumentNullException(nameof(targets));
        }

        string resolvedProject = Path.GetFullPath(projectRoot);

        // If pointing to <game>/Exoforge, step up to <game> if parent has Assets/
        if (Directory.GetParent(resolvedProject) != null &&
            Directory.Exists(Path.Combine(Directory.GetParent(resolvedProject)!.FullName, "Assets")))
        {
            resolvedProject = Directory.GetParent(resolvedProject)!.FullName;
        }

        var selectedTargets = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (string rawTarget in targets)
        {
            if (string.IsNullOrWhiteSpace(rawTarget))
            {
                continue;
            }

            string t = rawTarget.Trim().ToLowerInvariant();
            switch (t)
            {
                case "all":
                    selectedTargets.Add("agents");
                    selectedTargets.Add("claude");
                    selectedTargets.Add("gemini");
                    break;
                case "agents":
                case "claude":
                case "gemini":
                    selectedTargets.Add(t);
                    break;
                default:
                    throw new ArgumentException(
                        $"Unknown agent install target '{rawTarget}'. Expected one of: agents, claude, gemini, all.",
                        nameof(targets));
            }
        }

        string? pkgRoot = packageRootOverride ?? FindPackageRoot(resolvedProject);

        if (selectedTargets.Count == 0)
        {
            return new AgentInstallResult
            {
                ProjectRoot = resolvedProject,
                PackageRoot = pkgRoot ?? "",
                CliAvailable = CheckCliAvailability(resolvedProject, pkgRoot)
            };
        }

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

        var gitignoreEntries = new List<string>();

        // 1. Copy skills
        var targetFolders = new List<string>();
        if (selectedTargets.Contains("agents"))
        {
            targetFolders.Add(".agents/skills");
            gitignoreEntries.Add(".agents/");
        }
        if (selectedTargets.Contains("claude"))
        {
            targetFolders.Add(".claude/skills");
            gitignoreEntries.Add(".claude/");
        }
        if (selectedTargets.Contains("gemini"))
        {
            targetFolders.Add(".gemini/skills");
            gitignoreEntries.Add(".gemini/");
        }

        string packageSkillsDir = Path.Combine(pkgRoot, "Agents~", "skills");
        if (Directory.Exists(packageSkillsDir))
        {
            var skillDirs = Directory.GetDirectories(packageSkillsDir);
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
            string guideContent = File.ReadAllText(srcAgentsMd).Trim();
            string destAgentsMd = Path.Combine(resolvedProject, "AGENTS.md");
            string desiredAgentsMd;

            if (!File.Exists(destAgentsMd))
            {
                desiredAgentsMd = guideContent + "\n";
                File.WriteAllText(destAgentsMd, desiredAgentsMd);
                result.UpdatedFiles.Add(destAgentsMd);
            }
            else
            {
                string existing = File.ReadAllText(destAgentsMd);

                if (existing.Contains(MarkerStart) && existing.Contains(MarkerEnd))
                {
                    int startIdx = existing.IndexOf(MarkerStart, StringComparison.Ordinal);
                    int endIdx = existing.IndexOf(MarkerEnd, StringComparison.Ordinal) + MarkerEnd.Length;
                    desiredAgentsMd = existing.Substring(0, startIdx) + guideContent + existing.Substring(endIdx);
                }
                else if (existing.Contains(GenericMarker))
                {
                    int startIdx = existing.IndexOf(GenericMarker, StringComparison.Ordinal);
                    desiredAgentsMd = existing.Substring(0, startIdx) + guideContent + "\n";
                }
                else
                {
                    desiredAgentsMd = existing.TrimEnd() + "\n\n" + guideContent + "\n";
                }

                if (!string.Equals(existing, desiredAgentsMd, StringComparison.Ordinal))
                {
                    File.WriteAllText(destAgentsMd, desiredAgentsMd);
                    result.UpdatedFiles.Add(destAgentsMd);
                }
            }

            gitignoreEntries.Add("AGENTS.md");
        }

        // 3. Create ./exo and ./exo.cmd wrappers via ExoCliInstaller
        var cliResult = ExoCliInstaller.Install(resolvedProject, pkgRoot);
        foreach (var f in cliResult.UpdatedFiles) result.UpdatedFiles.Add(f);

        string exoforgeSubdir = Path.Combine(resolvedProject, "Exoforge");
        if (Directory.Exists(exoforgeSubdir))
        {
            var cliResult2 = ExoCliInstaller.Install(exoforgeSubdir, pkgRoot);
            foreach (var f in cliResult2.UpdatedFiles) result.UpdatedFiles.Add(f);
        }
        // 4. Update marked .gitignore block for exact generated items
        UpdateGitignore(resolvedProject, gitignoreEntries, result.UpdatedFiles);

        // 5. Check if CLI is available
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
            if (!File.Exists(destFile) || !FilesEqual(file, destFile))
            {
                File.Copy(file, destFile, overwrite: true);
                updatedFiles.Add(destFile);
            }
        }

        foreach (string subDir in Directory.GetDirectories(sourceDir))
        {
            string subDirName = Path.GetFileName(subDir);
            CopyDirectoryRecursively(subDir, Path.Combine(targetDir, subDirName), updatedFiles);
        }
    }

    private static bool FilesEqual(string pathA, string pathB)
    {
        var infoA = new FileInfo(pathA);
        var infoB = new FileInfo(pathB);
        if (infoA.Length != infoB.Length)
        {
            return false;
        }

        byte[] bytesA = File.ReadAllBytes(pathA);
        byte[] bytesB = File.ReadAllBytes(pathB);
        return bytesA.AsSpan().SequenceEqual(bytesB);
    }

    private static void UpdateGitignore(string projectRoot, IEnumerable<string> generatedEntries, List<string> updatedFiles)
    {
        var generatedSet = new HashSet<string>(
            generatedEntries.Where(e => !string.IsNullOrWhiteSpace(e)).Select(e => e.Trim()),
            StringComparer.Ordinal);

        if (generatedSet.Count == 0)
        {
            return;
        }

        string gitignorePath = Path.Combine(projectRoot, ".gitignore");
        if (!File.Exists(gitignorePath))
        {
            string block = BuildGitignoreBlock(OrderGitignoreEntries(generatedSet));
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
                {
                    merged.Add(trimmed);
                }
            }

            string block = BuildGitignoreBlock(OrderGitignoreEntries(merged));
            desired = existing.Substring(0, startIdx) + block + existing.Substring(endIdx + GitignoreMarkerEnd.Length);
        }
        else
        {
            var existingLines = existing
                .Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries)
                .Select(l => l.Trim())
                .Where(l => l.Length > 0 && !l.StartsWith("#", StringComparison.Ordinal))
                .ToHashSet(StringComparer.Ordinal);

            var toAdd = generatedSet.Where(e => !existingLines.Contains(e)).ToList();
            if (toAdd.Count == 0)
            {
                return;
            }

            string block = BuildGitignoreBlock(OrderGitignoreEntries(toAdd));
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

    private static List<string> OrderGitignoreEntries(IEnumerable<string> entries)
    {
        var entrySet = new HashSet<string>(entries, StringComparer.Ordinal);
        var ordered = new List<string>();
        foreach (string canonical in CanonicalGitignoreOrder)
        {
            if (entrySet.Remove(canonical))
            {
                ordered.Add(canonical);
            }
        }
        ordered.AddRange(entrySet.OrderBy(e => e, StringComparer.Ordinal));
        return ordered;
    }

    private static string BuildGitignoreBlock(IReadOnlyList<string> entries)
    {
        return GitignoreMarkerStart + "\n" + string.Join("\n", entries) + "\n" + GitignoreMarkerEnd;
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
