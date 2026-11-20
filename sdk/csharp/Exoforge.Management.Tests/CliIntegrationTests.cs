using System;
using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Xunit;

namespace Exoforge.Management.Tests;

public class CliIntegrationTests : IDisposable
{
    private readonly string _tempDir;
    private static readonly SemaphoreSlim CliLock = new(1, 1);

    public CliIntegrationTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), $"exo_cli_test_{Guid.NewGuid():N}");
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
        await CliLock.WaitAsync();
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
            CliLock.Release();
        }
    }

    private static string ExtractJson(string text)
    {
        int start = text.IndexOfAny(new[] { '{', '[' });
        if (start < 0) return text;
        int end = text.LastIndexOfAny(new[] { '}', ']' });
        if (end < start) return text;
        return text.Substring(start, end - start + 1);
    }

    [Fact]
    public async Task Cli_Help_Returns_Zero_Exit_Code()
    {
        int code = await Exoforge.CLI.Program.Main(new[] { "--help" });
        Assert.Equal(0, code);
    }

    [Fact]
    public async Task Cli_Unknown_Command_Returns_NonZero_Exit_Code()
    {
        int code = await Exoforge.CLI.Program.Main(new[] { "unknown_nonexistent_command" });
        Assert.Equal(1, code);
    }

    [Fact]
    public async Task Cli_Init_Creates_Valid_Workspace()
    {
        int code = await Exoforge.CLI.Program.Main(new[]
        {
            "init",
            "--dir", _tempDir,
            "--name", "MyAwesomeGame"
        });

        Assert.Equal(0, code);
        Assert.True(ExoWorkspace.Exists(_tempDir));
        Assert.True(File.Exists(Path.Combine(_tempDir, "exoforge.json")));
        Assert.True(Directory.Exists(Path.Combine(_tempDir, "extensions")) || Directory.Exists(Path.Combine(_tempDir, "plugins")));

        string configJson = File.ReadAllText(Path.Combine(_tempDir, "exoforge.json"));
        Assert.Contains("MyAwesomeGame", configJson);
    }

    [Fact]
    public async Task Cli_Legacy_Plugin_Command_Is_Rejected()
    {
        await Exoforge.CLI.Program.Main(new[] { "init", "--dir", _tempDir, "--name", "Game" });

        // `plugin` command was bulldoze-removed in favor of `extension`
        int code = await Exoforge.CLI.Program.Main(new[]
        {
            "plugin", "new", "combat_system",
            "--dir", _tempDir
        });

        Assert.Equal(1, code);
    }

    [Fact]
    public async Task Cli_Extension_New_Scaffolds_Extension_Directory_And_Files()
    {
        await Exoforge.CLI.Program.Main(new[] { "init", "--dir", _tempDir, "--name", "Game" });

        int code = await Exoforge.CLI.Program.Main(new[]
        {
            "extension", "new", "economy_system",
            "--dir", _tempDir
        });

        Assert.Equal(0, code);

        var ws = ExoWorkspace.Load(_tempDir);
        string extDir = Path.Combine(ws.ExtensionsPath, "economy_system");
        Assert.True(Directory.Exists(extDir));
        Assert.True(File.Exists(Path.Combine(extDir, "economy_system.sln")));
        Assert.True(File.Exists(Path.Combine(extDir, "src", "economy_system.csproj")));
        Assert.True(File.Exists(Path.Combine(extDir, "src", "EconomySystemExtension.cs")));

        // the extension's own page in the Developer Guide
        string overview = File.ReadAllText(Path.Combine(extDir, "docs", "overview.md"));
        Assert.StartsWith("---\nnav: Overview", overview);
        Assert.Contains("# EconomySystem", overview);
        Assert.Contains("{{actions}}", overview);
    }

    [Fact]
    public void Cli_Executable_Runs_From_Subprocess()
    {
        // Find exo.dll in bin output
        string currentDir = AppContext.BaseDirectory;
        string exoDll = Path.GetFullPath(Path.Combine(currentDir, "..", "..", "..", "..", "Exoforge.CLI", "bin", "Debug", "net10.0", "exo.dll"));

        if (!File.Exists(exoDll))
        {
            // In case of release build or direct run
            exoDll = Path.Combine(currentDir, "exo.dll");
        }

        if (File.Exists(exoDll))
        {
            var psi = new ProcessStartInfo("dotnet", $"exec \"{exoDll}\" --help")
            {
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false
            };

            using var proc = Process.Start(psi);
            Assert.NotNull(proc);
            string output = proc.StandardOutput.ReadToEnd();
            proc.WaitForExit();

            Assert.Equal(0, proc.ExitCode);
            Assert.Contains("EXOFORGE DEVELOPER CLI", output);
            Assert.Contains("Usage: exo <command>", output);
        }
    }

    [Fact]
    public async Task Cli_Env_Add_And_List_With_Json_Flag()
    {
        await Exoforge.CLI.Program.Main(new[] { "init", "--dir", _tempDir, "--name", "EnvTestGame" });

        var (addCode, addOut) = await RunCliAsync(
            "env", "add", "staging",
            "--ws", "ws://localhost:5000/ws",
            "--http", "http://localhost:5001",
            "--default",
            "--dir", _tempDir,
            "--json"
        );

        Assert.Equal(0, addCode);
        using (var addDoc = JsonDocument.Parse(ExtractJson(addOut)))
        {
            var root = addDoc.RootElement;
            Assert.Equal("ok", root.GetProperty("status").GetString());
            Assert.Equal("staging", root.GetProperty("environment").GetString());
            Assert.True(root.GetProperty("is_default").GetBoolean());
            Assert.Equal("ws://localhost:5000/ws", root.GetProperty("ws_url").GetString());
            Assert.Equal("http://localhost:5001", root.GetProperty("http_url").GetString());
        }

        var (listCode, listOut) = await RunCliAsync(
            "env", "list",
            "--dir", _tempDir,
            "--json"
        );

        Assert.Equal(0, listCode);
        using (var listDoc = JsonDocument.Parse(ExtractJson(listOut)))
        {
            var root = listDoc.RootElement;
            Assert.Equal("staging", root.GetProperty("default_environment").GetString());
            var envs = root.GetProperty("environments");
            Assert.Equal(JsonValueKind.Array, envs.ValueKind);

            bool foundStaging = false;
            foreach (var env in envs.EnumerateArray())
            {
                if (env.GetProperty("name").GetString() == "staging")
                {
                    foundStaging = true;
                    Assert.True(env.GetProperty("is_default").GetBoolean());
                    Assert.Equal("ws://localhost:5000/ws", env.GetProperty("ws_url").GetString());
                    Assert.Equal("http://localhost:5001", env.GetProperty("http_url").GetString());
                }
            }
            Assert.True(foundStaging);
        }

        var ws = ExoWorkspace.Load(_tempDir);
        Assert.Equal("staging", ws.Config.DefaultEnvironment);
        Assert.True(ws.Config.Environments.ContainsKey("staging"));
    }

    [Fact]
    public async Task Cli_Agents_Install_And_Status_With_Json_Flag()
    {
        string tempUnityProject = Path.Combine(_tempDir, "SampleUnityGame");
        Directory.CreateDirectory(tempUnityProject);
        Directory.CreateDirectory(Path.Combine(tempUnityProject, "Assets"));

        var (installCode, installOut) = await RunCliAsync(
            "agents", "install",
            "--dir", tempUnityProject,
            "--all",
            "--json"
        );

        Assert.Equal(0, installCode);
        using (var installDoc = JsonDocument.Parse(ExtractJson(installOut)))
        {
            var root = installDoc.RootElement;
            Assert.Equal(Path.GetFullPath(tempUnityProject), Path.GetFullPath(root.GetProperty("project_root").GetString()!));
            Assert.True(root.GetProperty("installed_skills").GetArrayLength() > 0);
        }

        // Verify creation of skills files across all targets (.agents, .claude, .gemini)
        string skillFileAgents = Path.Combine(tempUnityProject, ".agents", "skills", "exoforge-extensions", "SKILL.md");
        string skillFileClaude = Path.Combine(tempUnityProject, ".claude", "skills", "exoforge-extensions", "SKILL.md");
        string skillFileGemini = Path.Combine(tempUnityProject, ".gemini", "skills", "exoforge-extensions", "SKILL.md");
        string agentsMdFile = Path.Combine(tempUnityProject, "AGENTS.md");
        string exoWrapperFile = Path.Combine(tempUnityProject, "exo");
        string exoCmdWrapperFile = Path.Combine(tempUnityProject, "exo.cmd");

        Assert.True(File.Exists(skillFileAgents), "Expected .agents/skills/exoforge-extensions/SKILL.md to exist");
        Assert.True(File.Exists(skillFileClaude), "Expected .claude/skills/exoforge-extensions/SKILL.md to exist");
        Assert.True(File.Exists(skillFileGemini), "Expected .gemini/skills/exoforge-extensions/SKILL.md to exist");
        Assert.True(File.Exists(agentsMdFile), "Expected AGENTS.md to exist");
        Assert.True(File.Exists(exoWrapperFile), "Expected exo wrapper script to exist");
        Assert.True(File.Exists(exoCmdWrapperFile), "Expected exo.cmd wrapper script to exist");

        string wrapperContent = File.ReadAllText(exoWrapperFile);
        Assert.Contains("exo.dll", wrapperContent);

        string gitignoreFile = Path.Combine(tempUnityProject, ".gitignore");
        Assert.True(File.Exists(gitignoreFile), "Expected .gitignore to exist");
        string gitignoreContent = File.ReadAllText(gitignoreFile);
        Assert.Contains("# >>> EXOFORGE-AGENT-TOOLING:START", gitignoreContent);
        Assert.Contains("# <<< EXOFORGE-AGENT-TOOLING:END", gitignoreContent);

        var (statusCode, statusOut) = await RunCliAsync(
            "agents", "status",
            "--dir", tempUnityProject,
            "--json"
        );

        Assert.Equal(0, statusCode);
        using (var statusDoc = JsonDocument.Parse(ExtractJson(statusOut)))
        {
            var root = statusDoc.RootElement;
            Assert.True(root.GetProperty("agents_guide_installed").GetBoolean());
            Assert.True(root.GetProperty("wrapper_installed").GetBoolean());
            Assert.True(root.GetProperty("cli_available").GetBoolean());

            var installedSkills = root.GetProperty("installed_skills");
            Assert.True(installedSkills.GetArrayLength() > 0);
            bool hasExtSkill = false;
            foreach (var skill in installedSkills.EnumerateArray())
            {
                if (skill.GetString() == "exoforge-extensions")
                {
                    hasExtSkill = true;
                    break;
                }
            }
            Assert.True(hasExtSkill);
        }
    }
}
