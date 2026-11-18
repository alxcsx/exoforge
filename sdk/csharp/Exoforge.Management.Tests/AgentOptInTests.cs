using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Xunit;

namespace Exoforge.Management.Tests;

public class AgentOptInTests : IDisposable
{
    private const string GitignoreMarkerStart = "# >>> EXOFORGE-AGENT-TOOLING:START";
    private const string GitignoreMarkerEnd = "# <<< EXOFORGE-AGENT-TOOLING:END";

    private readonly string _tempDir;

    public AgentOptInTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), $"exo_agent_optin_{Guid.NewGuid():N}");
        Directory.CreateDirectory(_tempDir);
    }

    public void Dispose()
    {
        try
        {
            if (Directory.Exists(_tempDir))
            {
                Directory.Delete(_tempDir, true);
            }
        }
        catch
        {
            // Ignore cleanup errors
        }
    }

    private static async Task<(int ExitCode, string StdOut)> RunCliAsync(params string[] args)
    {
        var originalOut = Console.Out;
        using var sw = new StringWriter();
        try
        {
            Console.SetOut(sw);
            int code = await Exoforge.CLI.Program.Main(args);
            return (code, sw.ToString());
        }
        finally
        {
            Console.SetOut(originalOut);
        }
    }

    private static void AssertNoAiToolingFiles(string root)
    {
        string[] dirs = { ".agents", ".claude", ".gemini" };
        foreach (string dir in dirs)
        {
            Assert.False(Directory.Exists(Path.Combine(root, dir)), $"Unexpected AI directory '{dir}' in {root}");
        }

        string[] files = { "AGENTS.md", "exo", "exo.cmd", "exo.ps1", ".gitignore" };
        foreach (string file in files)
        {
            Assert.False(File.Exists(Path.Combine(root, file)), $"Unexpected file '{file}' in {root}");
        }
    }

    private static string ExtractMarkedBlock(string gitignoreContent)
    {
        int start = gitignoreContent.IndexOf(GitignoreMarkerStart, StringComparison.Ordinal);
        int end = gitignoreContent.IndexOf(GitignoreMarkerEnd, StringComparison.Ordinal);
        Assert.True(start >= 0, $"Expected '{GitignoreMarkerStart}' in .gitignore");
        Assert.True(end > start, $"Expected '{GitignoreMarkerEnd}' after start marker in .gitignore");
        return gitignoreContent.Substring(start, end + GitignoreMarkerEnd.Length - start);
    }

    private static int CountOccurrences(string text, string substring)
    {
        int count = 0;
        int index = 0;
        while ((index = text.IndexOf(substring, index, StringComparison.Ordinal)) >= 0)
        {
            count++;
            index += substring.Length;
        }
        return count;
    }

    [Fact]
    public async Task Init_And_ScaffoldExtension_Do_Not_Create_Ai_Tooling_Files()
    {
        // 1. Management API: ExoWorkspace.Initialize + ExoScaffolder.ScaffoldExtension
        string apiUnityRoot = Path.Combine(_tempDir, "ApiUnityProject");
        string apiExoforgeDir = Path.Combine(apiUnityRoot, "Exoforge");
        Directory.CreateDirectory(Path.Combine(apiUnityRoot, "Assets"));
        Directory.CreateDirectory(apiExoforgeDir);

        var ws = ExoWorkspace.Initialize(apiExoforgeDir, "ApiOptInGame");
        ExoScaffolder.ScaffoldExtension(ws.ExtensionsPath, "combat_system");

        AssertNoAiToolingFiles(apiUnityRoot);
        AssertNoAiToolingFiles(apiExoforgeDir);

        // 2. CLI: exo init + exo extension new
        string cliUnityRoot = Path.Combine(_tempDir, "CliUnityProject");
        string cliExoforgeDir = Path.Combine(cliUnityRoot, "Exoforge");
        Directory.CreateDirectory(Path.Combine(cliUnityRoot, "Assets"));
        Directory.CreateDirectory(cliExoforgeDir);

        var (initCode, _) = await RunCliAsync("init", "--dir", cliExoforgeDir, "--name", "CliOptInGame");
        Assert.Equal(0, initCode);

        var (newCode, _) = await RunCliAsync("extension", "new", "quest_system", "--dir", cliExoforgeDir);
        Assert.Equal(0, newCode);

        AssertNoAiToolingFiles(cliUnityRoot);
        AssertNoAiToolingFiles(cliExoforgeDir);
    }

    [Fact]
    public async Task Cli_Agents_Install_Without_Flags_Prints_Help_And_Installs_Nothing()
    {
        string projectRoot = Path.Combine(_tempDir, "NoFlagsUnity");
        Directory.CreateDirectory(Path.Combine(projectRoot, "Assets"));

        var (code, output) = await RunCliAsync("agents", "install", "--dir", projectRoot);

        Assert.Equal(0, code);
        Assert.Contains("--claude", output);
        Assert.Contains("--gemini", output);
        Assert.Contains("--agents", output);
        Assert.Contains("--all", output);
        AssertNoAiToolingFiles(projectRoot);
    }

    [Theory]
    [InlineData(new[] { "--claude" }, new[] { ".claude" }, new[] { ".agents", ".gemini" })]
    [InlineData(new[] { "--gemini" }, new[] { ".gemini" }, new[] { ".agents", ".claude" })]
    [InlineData(new[] { "--agents" }, new[] { ".agents" }, new[] { ".claude", ".gemini" })]
    [InlineData(new[] { "--claude", "--gemini" }, new[] { ".claude", ".gemini" }, new[] { ".agents" })]
    [InlineData(new[] { "--all" }, new[] { ".agents", ".claude", ".gemini" }, new string[0])]
    public async Task Cli_Agents_Install_Respects_Explicit_Target_Flags_And_Writes_Exact_Gitignore(
        string[] targetFlags,
        string[] expectedDirs,
        string[] unexpectedDirs)
    {
        string projectRoot = Path.Combine(_tempDir, "TargetTest_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(Path.Combine(projectRoot, "Assets"));

        var args = new List<string> { "agents", "install", "--dir", projectRoot };
        args.AddRange(targetFlags);

        var (code, _) = await RunCliAsync(args.ToArray());
        Assert.Equal(0, code);

        foreach (string dir in expectedDirs)
        {
            Assert.True(
                File.Exists(Path.Combine(projectRoot, dir, "skills", "exoforge-extensions", "SKILL.md")),
                $"Expected {dir}/skills/exoforge-extensions/SKILL.md to exist");
        }

        foreach (string dir in unexpectedDirs)
        {
            Assert.False(
                Directory.Exists(Path.Combine(projectRoot, dir)),
                $"Did not expect {dir}/ to be created");
        }

        Assert.True(File.Exists(Path.Combine(projectRoot, "AGENTS.md")));
        Assert.True(File.Exists(Path.Combine(projectRoot, "exo")));
        Assert.True(File.Exists(Path.Combine(projectRoot, "exo.cmd")));

        string gitignorePath = Path.Combine(projectRoot, ".gitignore");
        Assert.True(File.Exists(gitignorePath), "Expected .gitignore to be created");
        string gitignore = File.ReadAllText(gitignorePath);

        Assert.Equal(1, CountOccurrences(gitignore, GitignoreMarkerStart));
        Assert.Equal(1, CountOccurrences(gitignore, GitignoreMarkerEnd));

        string block = ExtractMarkedBlock(gitignore);
        var lines = block.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries)
                         .Select(l => l.Trim())
                         .ToHashSet(StringComparer.Ordinal);

        foreach (string dir in expectedDirs)
        {
            Assert.Contains(dir + "/", lines);
        }

        foreach (string dir in unexpectedDirs)
        {
            Assert.DoesNotContain(dir + "/", lines);
        }

        Assert.Contains("AGENTS.md", lines);
    }

    [Fact]
    public void AgentInstaller_Is_Idempotent_And_Preserves_Existing_Gitignore()
    {
        string projectRoot = Path.Combine(_tempDir, "IdempotentUnity");
        Directory.CreateDirectory(Path.Combine(projectRoot, "Assets"));

        string gitignorePath = Path.Combine(projectRoot, ".gitignore");
        File.WriteAllText(gitignorePath, "Library/\nTemp/\n");

        string? pkgRoot = ExoAgentInstaller.FindPackageRoot(AppContext.BaseDirectory) ??
                          ExoAgentInstaller.FindPackageRoot(Directory.GetCurrentDirectory());
        Assert.NotNull(pkgRoot);

        // 1. First install writes everything and preserves existing .gitignore lines
        var result1 = ExoAgentInstaller.Install(projectRoot, "all", pkgRoot);
        Assert.NotEmpty(result1.UpdatedFiles);
        Assert.Contains(gitignorePath, result1.UpdatedFiles);

        string gitignoreAfterFirst = File.ReadAllText(gitignorePath);
        Assert.Contains("Library/", gitignoreAfterFirst);
        Assert.Contains("Temp/", gitignoreAfterFirst);
        Assert.Equal(1, CountOccurrences(gitignoreAfterFirst, GitignoreMarkerStart));
        Assert.Equal(1, CountOccurrences(gitignoreAfterFirst, GitignoreMarkerEnd));

        var trackedPaths = result1.UpdatedFiles.Distinct().ToList();
        var mtimesBefore = trackedPaths.ToDictionary(p => p, File.GetLastWriteTimeUtc);
        var contentsBefore = trackedPaths.ToDictionary(p => p, File.ReadAllText);

        Thread.Sleep(50);

        // 2. Second install must be a true no-op
        var result2 = ExoAgentInstaller.Install(projectRoot, "all", pkgRoot);
        Assert.Empty(result2.UpdatedFiles);

        foreach (string path in trackedPaths)
        {
            Assert.Equal(mtimesBefore[path], File.GetLastWriteTimeUtc(path));
            Assert.Equal(contentsBefore[path], File.ReadAllText(path));
        }

        string gitignoreAfterSecond = File.ReadAllText(gitignorePath);
        Assert.Equal(1, CountOccurrences(gitignoreAfterSecond, GitignoreMarkerStart));
        Assert.Equal(1, CountOccurrences(gitignoreAfterSecond, GitignoreMarkerEnd));
    }

    [Fact]
    public async Task Cli_Agents_Install_Incremental_Targets_Merge_Into_Single_Gitignore_Block()
    {
        string projectRoot = Path.Combine(_tempDir, "IncrementalUnity");
        Directory.CreateDirectory(Path.Combine(projectRoot, "Assets"));

        var (code1, _) = await RunCliAsync("agents", "install", "--claude", "--dir", projectRoot);
        Assert.Equal(0, code1);

        var (code2, _) = await RunCliAsync("agents", "install", "--gemini", "--dir", projectRoot);
        Assert.Equal(0, code2);

        Assert.True(Directory.Exists(Path.Combine(projectRoot, ".claude", "skills")));
        Assert.True(Directory.Exists(Path.Combine(projectRoot, ".gemini", "skills")));
        Assert.False(Directory.Exists(Path.Combine(projectRoot, ".agents")));

        string gitignorePath = Path.Combine(projectRoot, ".gitignore");
        string gitignore = File.ReadAllText(gitignorePath);

        Assert.Equal(1, CountOccurrences(gitignore, GitignoreMarkerStart));
        Assert.Equal(1, CountOccurrences(gitignore, GitignoreMarkerEnd));

        string block = ExtractMarkedBlock(gitignore);
        var lines = block.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries)
                         .Select(l => l.Trim())
                         .ToHashSet(StringComparer.Ordinal);

        Assert.Contains(".claude/", lines);
        Assert.Contains(".gemini/", lines);
        Assert.DoesNotContain(".agents/", lines);
        Assert.Contains("AGENTS.md", lines);

        // Repeating --gemini does not duplicate anything
        var (code3, _) = await RunCliAsync("agents", "install", "--gemini", "--dir", projectRoot);
        Assert.Equal(0, code3);
        Assert.Equal(gitignore, File.ReadAllText(gitignorePath));
    }

    [Fact]
    public void AgentInstaller_Empty_Targets_Writes_Nothing_And_Unknown_Throws()
    {
        string projectRoot = Path.Combine(_tempDir, "EmptyAndInvalid");
        Directory.CreateDirectory(Path.Combine(projectRoot, "Assets"));

        string? pkgRoot = ExoAgentInstaller.FindPackageRoot(AppContext.BaseDirectory) ??
                          ExoAgentInstaller.FindPackageRoot(Directory.GetCurrentDirectory());
        Assert.NotNull(pkgRoot);

        var emptyRes = ExoAgentInstaller.Install(projectRoot, Array.Empty<string>(), pkgRoot);
        Assert.Empty(emptyRes.UpdatedFiles);
        Assert.Empty(emptyRes.InstalledSkills);
        AssertNoAiToolingFiles(projectRoot);

        Assert.Throws<ArgumentException>(() => ExoAgentInstaller.Install(projectRoot, "invalid_target", pkgRoot));
    }

    [Fact]
    public void UnityPackage_Bundles_Agents_And_Staged_Cli_Binaries()
    {
        string? pkgRoot = ExoAgentInstaller.FindPackageRoot(AppContext.BaseDirectory) ??
                          ExoAgentInstaller.FindPackageRoot(Directory.GetCurrentDirectory());
        Assert.NotNull(pkgRoot);

        Assert.True(File.Exists(Path.Combine(pkgRoot!, "Agents~", "AGENTS.md")));
        Assert.True(File.Exists(Path.Combine(pkgRoot, "Agents~", "skills", "exoforge-connection", "SKILL.md")));
        Assert.True(File.Exists(Path.Combine(pkgRoot, "Agents~", "skills", "exoforge-extensions", "SKILL.md")));
        Assert.True(File.Exists(Path.Combine(pkgRoot, "Agents~", "skills", "exoforge-resources", "SKILL.md")));

        Assert.True(File.Exists(Path.Combine(pkgRoot, "Editor", "Cli~", "exo")),
            "Editor/Cli~/exo is missing - run 'just build-unity-sdk'");
        Assert.True(File.Exists(Path.Combine(pkgRoot, "Editor", "Cli~", "exo.cmd")),
            "Editor/Cli~/exo.cmd is missing - run 'just build-unity-sdk'");
        Assert.True(File.Exists(Path.Combine(pkgRoot, "Editor", "Cli~", "exo.dll")),
            "Editor/Cli~/exo.dll is missing - run 'just build-unity-sdk'");
    }
}
