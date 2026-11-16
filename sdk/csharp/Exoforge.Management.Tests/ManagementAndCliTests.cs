using System;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using Xunit;

namespace Exoforge.Management.Tests;

public class ManagementAndCliTests : IDisposable
{
    private readonly string _tempDir;

    public ManagementAndCliTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), $"exo_mgmt_test_{Guid.NewGuid():N}");
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

    [Fact]
    public void Workspace_FindRoot_And_Load_Unity_Project_Topology()
    {
        // Mock a Unity project structure:
        // tempDir/
        //   Assets/
        //   Exoforge/
        //     exoforge.json
        string assetsDir = Path.Combine(_tempDir, "Assets");
        string exoforgeDir = Path.Combine(_tempDir, "Exoforge");
        Directory.CreateDirectory(assetsDir);
        Directory.CreateDirectory(exoforgeDir);

        var wsDirect = ExoWorkspace.Initialize(exoforgeDir, "TestUnityGame");
        Assert.True(File.Exists(wsDirect.ConfigPath));

        // 1. Load passing <projectRoot> (which has Assets/ and Exoforge/)
        var wsFromProject = ExoWorkspace.Load(_tempDir);
        Assert.Equal(Path.GetFullPath(exoforgeDir), Path.GetFullPath(wsFromProject.RootPath));
        Assert.True(File.Exists(wsFromProject.ConfigPath));

        // 2. Load passing <projectRoot>/Exoforge
        var wsFromExoforge = ExoWorkspace.Load(exoforgeDir);
        Assert.Equal(Path.GetFullPath(exoforgeDir), Path.GetFullPath(wsFromExoforge.RootPath));

        // 3. FindRoot from a nested folder (e.g., inside Assets)
        string nested = Path.Combine(assetsDir, "Scripts", "Gameplay");
        Directory.CreateDirectory(nested);
        string? root = ExoWorkspace.FindRoot(nested);
        Assert.NotNull(root);
        Assert.Equal(Path.GetFullPath(exoforgeDir), Path.GetFullPath(root));
    }

    [Fact]
    public async Task Cli_Env_Commands_Work_Correctly()
    {
        await Exoforge.CLI.Program.Main(new[] { "init", "--dir", _tempDir, "--name", "EnvTestGame" });

        // Add staging environment
        int addCode = await Exoforge.CLI.Program.Main(new[]
        {
            "env", "add", "staging",
            "--ws", "ws://staging.exoforge.local:4000/ws",
            "--http", "http://staging.exoforge.local:4001",
            "--token", "stage_secret_token_12345",
            "--dir", _tempDir,
            "--json"
        });
        Assert.Equal(0, addCode);

        // Verify it was added
        var ws = ExoWorkspace.Load(_tempDir);
        Assert.True(ws.Config.Environments.ContainsKey("staging"));
        Assert.Equal("ws://staging.exoforge.local:4000/ws", ws.Config.Environments["staging"].WsUrl);
        Assert.Equal("stage_secret_token_12345", ws.Config.Environments["staging"].Token);

        // Switch active environment with `exo env use`
        int useCode = await Exoforge.CLI.Program.Main(new[]
        {
            "env", "use", "staging",
            "--dir", _tempDir,
            "--json"
        });
        Assert.Equal(0, useCode);

        ws = ExoWorkspace.Load(_tempDir);
        Assert.Equal("staging", ws.Config.DefaultEnvironment);

        // List environments
        int listCode = await Exoforge.CLI.Program.Main(new[]
        {
            "env", "list",
            "--dir", _tempDir,
            "--json"
        });
        Assert.Equal(0, listCode);
    }

    [Fact]
    public async Task Deployer_ListResourceTables_And_Contracts_From_Sample()
    {
        string monorepoRoot = Directory.GetCurrentDirectory();
        string samplePath = Path.Combine(monorepoRoot, "sdk", "unity", "sample_unity");

        if (!Directory.Exists(samplePath))
        {
            return;
        }

        var ws = ExoWorkspace.Load(samplePath);
        var deployer = new ExoDeployer(ws);

        // Contracts
        var contracts = await deployer.GetContractsExportAsync();
        Assert.Equal(JsonValueKind.Object, contracts.ValueKind);

        // Resource tables
        var tables = await deployer.ListResourceTablesAsync();
        Assert.NotEmpty(tables);
        Assert.Contains(tables, t => t.Name == "snake_config");
        Assert.Contains(tables, t => t.Name == "snake_scores");

        var configTable = tables.First(t => t.Name == "snake_config");
        Assert.True(configTable.Singleton);
        Assert.Equal("key", configTable.PrimaryKey);
        Assert.Contains(configTable.Columns, c => c.Name == "apple_points");
    }

    [Fact]
    public void AgentInstaller_Installs_Idempotently_And_Wrappers_Work()
    {
        string projectRoot = Path.Combine(_tempDir, "SampleUnity");
        string assetsDir = Path.Combine(projectRoot, "Assets");
        string exoforgeDir = Path.Combine(projectRoot, "Exoforge");
        Directory.CreateDirectory(assetsDir);
        Directory.CreateDirectory(exoforgeDir);

        // Locate package via FindPackageRoot
        string? pkgRoot = ExoAgentInstaller.FindPackageRoot(AppContext.BaseDirectory) ??
                          ExoAgentInstaller.FindPackageRoot(Directory.GetCurrentDirectory());
        Assert.NotNull(pkgRoot);
        Assert.True(Directory.Exists(pkgRoot));

        // 1. Initial Install
        var result1 = ExoAgentInstaller.Install(projectRoot, "all", pkgRoot);
        Assert.Equal(Path.GetFullPath(projectRoot), result1.ProjectRoot);
        Assert.NotEmpty(result1.InstalledSkills);
        Assert.Contains("exoforge-extensions", result1.InstalledSkills);

        string agentsMdPath = Path.Combine(projectRoot, "AGENTS.md");
        Assert.True(File.Exists(agentsMdPath));
        string agentsMdContent = File.ReadAllText(agentsMdPath);
        Assert.Contains(ExoAgentInstaller.MarkerStart, agentsMdContent);
        Assert.Contains(ExoAgentInstaller.MarkerEnd, agentsMdContent);

        // Check wrappers created
        Assert.True(File.Exists(Path.Combine(projectRoot, "exo")));
        Assert.True(File.Exists(Path.Combine(projectRoot, "exo.cmd")));
        Assert.True(File.Exists(Path.Combine(exoforgeDir, "exo")));

        // Check skills folders
        Assert.True(Directory.Exists(Path.Combine(projectRoot, ".agents", "skills", "exoforge-extensions")));
        Assert.True(Directory.Exists(Path.Combine(projectRoot, ".claude", "skills", "exoforge-extensions")));
        Assert.True(Directory.Exists(Path.Combine(projectRoot, ".gemini", "skills", "exoforge-extensions")));

        // 2. Secondary Install (Idempotent update test)
        var result2 = ExoAgentInstaller.Install(projectRoot, "all", pkgRoot);
        string updatedAgentsMd = File.ReadAllText(agentsMdPath);
        Assert.Contains(ExoAgentInstaller.MarkerStart, updatedAgentsMd);
        // Ensure marker appears only once
        int startCount = updatedAgentsMd.Split(new[] { ExoAgentInstaller.MarkerStart }, StringSplitOptions.None).Length - 1;
        Assert.Equal(1, startCount);

        // 3. Status check
        var status = ExoAgentInstaller.GetStatus(projectRoot, pkgRoot);
        Assert.True(status.AgentsGuideInstalled);
        Assert.True(status.WrapperInstalled);
        Assert.NotEmpty(status.InstalledSkills);
    }
}
