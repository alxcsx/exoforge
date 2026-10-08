using System;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;
using Xunit;

namespace Exoforge.Management.Tests;

public class CliIntegrationTests : IDisposable
{
    private readonly string _tempDir;

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
        Assert.True(Directory.Exists(Path.Combine(_tempDir, "plugins")));

        string configJson = File.ReadAllText(Path.Combine(_tempDir, "exoforge.json"));
        Assert.Contains("MyAwesomeGame", configJson);
    }

    [Fact]
    public async Task Cli_Plugin_New_Scaffolds_Plugin_Directory_And_Files()
    {
        // First init workspace
        await Exoforge.CLI.Program.Main(new[] { "init", "--dir", _tempDir, "--name", "Game" });

        // The temp workspace has no repository above it, which is exactly the case a scaffolded
        // plugin has to work in: the project it writes references the package, not a checkout.
        int code = await Exoforge.CLI.Program.Main(new[]
        {
            "plugin", "new", "inventory_system",
            "--dir", _tempDir
        });

        Assert.Equal(0, code);

        string pluginDir = Path.Combine(_tempDir, "plugins", "inventory_system");
        Assert.True(Directory.Exists(pluginDir));
        Assert.True(File.Exists(Path.Combine(pluginDir, "inventory_system.slnx")));
        Assert.True(File.Exists(Path.Combine(pluginDir, "src", "inventory_system.csproj")));
        Assert.True(File.Exists(Path.Combine(pluginDir, "src", "InventorySystemPlugin.cs")));
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
}
