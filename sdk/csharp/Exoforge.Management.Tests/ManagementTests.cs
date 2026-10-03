using System;
using System.IO;
using Xunit;
using Exoforge.Management;

namespace Exoforge.Management.Tests;

public class ManagementTests : IDisposable
{
    private readonly string _tempDir;

    public ManagementTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), $"exo_test_{Guid.NewGuid():N}");
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
    public void Workspace_Initialize_Creates_Configuration_And_Directories()
    {
        var ws = ExoWorkspace.Initialize(_tempDir, "TestGameProject");

        Assert.True(File.Exists(ws.ConfigPath));
        Assert.True(Directory.Exists(ws.PluginsPath));
        Assert.Equal("TestGameProject", ws.Config.ProjectName);
        Assert.Equal("local", ws.Config.DefaultEnvironment);

        var env = ws.GetActiveEnvironment();
        Assert.Equal("ws://127.0.0.1:4000/ws", env.WsUrl);
        Assert.Equal("http://127.0.0.1:4001", env.HttpUrl);

        // Verify reloading workspace from disk
        var loaded = ExoWorkspace.Load(_tempDir);
        Assert.Equal("TestGameProject", loaded.Config.ProjectName);
    }

    [Fact]
    public void Scaffolder_Creates_Complete_Plugin_Boilerplate()
    {
        var ws = ExoWorkspace.Initialize(_tempDir, "TestGameProject");
        string createdDir = ExoScaffolder.ScaffoldPlugin(ws.PluginsPath, "guild_system");

        Assert.True(Directory.Exists(createdDir));

        string csprojFile = Path.Combine(createdDir, "guild_system.csproj");
        Assert.True(File.Exists(csprojFile));
        string csprojText = File.ReadAllText(csprojFile);
        Assert.Contains("Exoforge.Plugin.SDK", csprojText);

        string serviceFile = Path.Combine(createdDir, "GuildSystemPlugin.cs");
        Assert.True(File.Exists(serviceFile));
        string serviceText = File.ReadAllText(serviceFile);
        Assert.Contains("[ExoService(\"guild_system\"", serviceText);
        Assert.Contains("public class GuildSystemPlugin : PluginBehaviour", serviceText);
        Assert.Contains("[ExoAction(\"ping\"", serviceText);
        Assert.Contains("[ExoAction(\"execute\"", serviceText);
        Assert.Contains("[ExoResource(\"guild_system_items\"", serviceText);
    }

    [Fact]
    public void CodeGenerator_Generates_Valid_CSharp_Client_From_Export_Json()
    {
        string exportJson = """
        {
            "export": {
                "cluster": "test@cluster",
                "plugins_count": 2,
                "plugins": [
                    {
                        "id": "combat_wasm",
                        "name": "CombatWasm",
                        "provides": ["combat"],
                        "services": [
                            {
                                "name": "combat",
                                "doc": "Sandboxed combat calculations.",
                                "actions": [
                                    {
                                        "name": "ping",
                                        "doc": "Ping health check.",
                                        "scope": "global",
                                        "params": []
                                    },
                                    {
                                        "name": "attack",
                                        "doc": "Attack action.",
                                        "scope": "global",
                                        "params": [
                                            { "name": "attacker_id", "type": "integer" },
                                            { "name": "damage", "type": "integer" }
                                        ]
                                    }
                                ]
                            }
                        ]
                    }
                ]
            }
        }
        """;

        string code = ExoCodeGenerator.GenerateFromExportJson(exportJson, "MyGame.Client");

        Assert.Contains("namespace MyGame.Client;", code);
        Assert.Contains("public static class ExoClientGeneratedExtensions", code);
        Assert.Contains("public static CombatServiceClient Combat(this ExoClient client)", code);
        Assert.Contains("public class ExoforgeServicesHub", code);
        Assert.Contains("public class CombatServiceClient", code);
        Assert.Contains("public Task<JsonElement> PingAsync(", code);
        Assert.Contains("public Task<JsonElement> AttackAsync(", code);
    }

    [Fact]
    public void UnityPackage_Structure_And_Manifest_Are_Valid()
    {
        string repoRoot = FindRepoRoot();
        string unityPkgDir = Path.Combine(repoRoot, "sdk", "unity", "Exoforge.SDK");

        Assert.True(Directory.Exists(unityPkgDir), $"Unity SDK directory not found at: {unityPkgDir}");

        // Validate package.json
        string packageJsonPath = Path.Combine(unityPkgDir, "package.json");
        Assert.True(File.Exists(packageJsonPath));
        string pkgJson = File.ReadAllText(packageJsonPath);
        using var doc = System.Text.Json.JsonDocument.Parse(pkgJson);
        Assert.True(doc.RootElement.TryGetProperty("name", out var nameProp));
        Assert.Equal("com.exoforge.sdk", nameProp.GetString());
        Assert.True(doc.RootElement.TryGetProperty("version", out _));
        Assert.True(doc.RootElement.TryGetProperty("displayName", out _));

        // Validate Runtime assembly and core scripts
        string runtimeDir = Path.Combine(unityPkgDir, "Runtime");
        Assert.True(Directory.Exists(runtimeDir));
        Assert.True(File.Exists(Path.Combine(runtimeDir, "Exoforge.SDK.asmdef")));
        Assert.True(File.Exists(Path.Combine(runtimeDir, "ExoforgeBehaviour.cs")));
        Assert.True(File.Exists(Path.Combine(runtimeDir, "ExoClient.cs")));
        Assert.True(File.Exists(Path.Combine(runtimeDir, "ExoDispatcher.cs")));
        Assert.True(File.Exists(Path.Combine(runtimeDir, "ExoTransport.cs")));
        Assert.True(File.Exists(Path.Combine(runtimeDir, "Protocol.cs")));
        Assert.True(File.Exists(Path.Combine(runtimeDir, "IsExternalInit.cs")));

        // Validate Editor assembly and management studio scripts
        string editorDir = Path.Combine(unityPkgDir, "Editor");
        Assert.True(Directory.Exists(editorDir));
        Assert.True(File.Exists(Path.Combine(editorDir, "Exoforge.SDK.Editor.asmdef")));
        Assert.True(File.Exists(Path.Combine(editorDir, "ExoforgeControlCenter.cs")));
        Assert.True(File.Exists(Path.Combine(editorDir, "ExoforgeEditorConfig.cs")));
        Assert.True(File.Exists(Path.Combine(editorDir, "ExoforgeMenu.cs")));

        // Validate Editor Management engine
        string mgmtDir = Path.Combine(editorDir, "Management");
        Assert.True(Directory.Exists(mgmtDir));
        Assert.True(File.Exists(Path.Combine(mgmtDir, "ExoWorkspace.cs")));
        Assert.True(File.Exists(Path.Combine(mgmtDir, "ExoScaffolder.cs")));
        Assert.True(File.Exists(Path.Combine(mgmtDir, "ExoCodeGenerator.cs")));
        Assert.True(File.Exists(Path.Combine(mgmtDir, "ExoDeployer.cs")));

        // Validate Editor asmdef references Runtime
        string editorAsmdefPath = Path.Combine(editorDir, "Exoforge.SDK.Editor.asmdef");
        string editorAsmdefJson = File.ReadAllText(editorAsmdefPath);
        using var asmDoc = System.Text.Json.JsonDocument.Parse(editorAsmdefJson);
        Assert.True(asmDoc.RootElement.TryGetProperty("references", out var refs));
        bool hasRuntimeRef = false;
        foreach (var r in refs.EnumerateArray())
        {
            if (r.GetString() == "Exoforge.SDK") hasRuntimeRef = true;
        }
        Assert.True(hasRuntimeRef, "Editor asmdef must reference Exoforge.SDK runtime");
    }

    [Fact]
    public void EditorConfig_Returns_Sensible_Defaults()
    {
        Assert.Equal("ws://localhost:4000/ws", Exoforge.Unity.Editor.ExoforgeEditorConfig.DefaultServerUrl);
        Assert.Equal("admin", Exoforge.Unity.Editor.ExoforgeEditorConfig.DefaultAdminToken);
        Assert.Equal("exoforge", Exoforge.Unity.Editor.ExoforgeEditorConfig.DefaultWorkspaceRelPath);
        Assert.Equal("Assets/Exoforge/Generated/ExoforgeServices.g.cs", Exoforge.Unity.Editor.ExoforgeEditorConfig.DefaultGeneratedScriptRelPath);
    }

    private static string FindRepoRoot()
    {
        string current = AppContext.BaseDirectory;
        while (!string.IsNullOrEmpty(current))
        {
            if (File.Exists(Path.Combine(current, "Justfile")) || Directory.Exists(Path.Combine(current, "sdk", "unity")))
            {
                return current;
            }
            string? parent = Path.GetDirectoryName(current);
            if (parent == null || parent == current) break;
            current = parent;
        }
        return Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "../../../../.."));
    }
}
