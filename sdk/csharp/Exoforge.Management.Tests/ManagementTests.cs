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

        // Per-plugin solution + src/ layout.
        string slnFile = Path.Combine(createdDir, "guild_system.slnx");
        Assert.True(File.Exists(slnFile));
        Assert.Contains("src/guild_system.csproj", File.ReadAllText(slnFile));

        string csprojFile = Path.Combine(createdDir, "src", "guild_system.csproj");
        Assert.True(File.Exists(csprojFile));
        Assert.Contains("Exoforge.Plugin.SDK", File.ReadAllText(csprojFile));

        string serviceFile = Path.Combine(createdDir, "src", "GuildSystemPlugin.cs");
        Assert.True(File.Exists(serviceFile));
        string serviceText = File.ReadAllText(serviceFile);
        Assert.Contains("[ExoService(\"guild_system\"", serviceText);
        Assert.Contains("public class GuildSystemPlugin", serviceText);
        Assert.Contains("[ExoAction]", serviceText);
        Assert.Contains("PluginHost.Run<GuildSystemPlugin, GuildSystemJsonContext>()", serviceText);
        Assert.Contains("[ExoResource(\"guild_system_items\"", serviceText);

        string contextFile = Path.Combine(createdDir, "src", "GuildSystemJsonContext.cs");
        Assert.True(File.Exists(contextFile));
        Assert.Contains("[JsonSerializable(typeof(GuildSystemItem))]", File.ReadAllText(contextFile));

        Assert.True(File.Exists(Path.Combine(createdDir, ".gitignore")));
    }

    [Fact]
    public void BuildPlugin_Throws_When_Plugin_Directory_Missing()
    {
        var ws = ExoWorkspace.Initialize(_tempDir, "TestGameProject");
        var deployer = new ExoDeployer(ws);

        Assert.Throws<DirectoryNotFoundException>(() => deployer.BuildPlugin("does_not_exist"));
    }

    [Fact]
    public void PluginStubs_GenerateTypedClientFromContract()
    {
        string json = """
        {
          "export": { "plugins": [ { "services": [
            {
              "name": "player_data",
              "actions": [ { "name": "get_player", "params": [{"name":"player_id","type":"string"}], "returns": {"player":"map"} } ],
              "resources": [ { "name": "players", "columns": [ {"name":"player_id","type":"string"}, {"name":"name","type":"string"} ] } ]
            }
          ] } ] }
        }
        """;

        string code = ExoCodeGenerator.GeneratePluginStubs(json, "Exoforge.Test.Generated");

        Assert.Contains("class PlayerDataServiceClient", code);
        Assert.Contains("Task<PlayerDataGetPlayerResponse?> GetPlayerAsync(PlayerDataGetPlayerRequest request)", code);
        Assert.Contains("CallActionAsync<PlayerDataGetPlayerResponse>(\"player_data\", \"get_player\", request)", code);
        Assert.Contains("public PlayerDataPlayer Player", code);
        Assert.Contains("public string Name", code);
        Assert.Contains("PluginJson.AddContext(GeneratedServicesJsonContext.Default)", code);
    }

    [Fact]
    public void ResolveDotnetPath_KeepsExplicitPath()
    {
        Assert.Equal("/opt/custom/dotnet", ExoDeployer.ResolveDotnetPath("/opt/custom/dotnet"));
    }

    [Fact]
    public void ResolveDotnetPath_ResolvesBareCommandToExistingFile()
    {
        // The test host runs under dotnet, so the resolver must find it even without assuming PATH.
        string resolved = ExoDeployer.ResolveDotnetPath("dotnet");
        Assert.True(File.Exists(resolved), $"Expected an existing dotnet path, got '{resolved}'.");
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
                        "id": "sample_wasm",
                        "name": "SampleWasm",
                        "provides": ["sample_wasm"],
                        "services": [
                            {
                                "name": "sample_wasm",
                                "doc": "Sample calculations.",
                                "actions": [
                                    {
                                        "name": "ping",
                                        "doc": "Ping health check.",
                                        "scope": "global",
                                        "params": []
                                    },
                                    {
                                        "name": "increment",
                                        "doc": "Increment action.",
                                        "scope": "global",
                                        "params": [
                                            { "name": "counter_id", "type": "integer" },
                                            { "name": "amount", "type": "integer" }
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

        Assert.Contains("namespace MyGame.Client", code);
        Assert.Contains("public static class ExoClientGeneratedExtensions", code);
        Assert.Contains("public static SampleWasmServiceClient SampleWasm(this ExoClient client)", code);
        Assert.Contains("public class ExoforgeServicesHub", code);
        Assert.Contains("public class SampleWasmServiceClient", code);
        Assert.Contains("public class SampleWasmIncrementRequest", code);
        Assert.Contains("public long CounterId { get; set; }", code);
        Assert.Contains("public long Amount { get; set; }", code);
        Assert.Contains("public Task<JsonElement> IncrementAsync(long counterId, long amount, CancellationToken cancellationToken = default)", code);
        Assert.Contains("public Task<JsonElement> IncrementAsync(SampleWasmIncrementRequest request, CancellationToken cancellationToken = default)", code);
        Assert.Contains("public Task<JsonElement> IncrementAsync(object? payload = null, CancellationToken cancellationToken = default)", code);
        Assert.Contains("public Task<JsonElement> PingAsync(", code);
    }

    [Fact]
    public void CodeGenerator_Generates_Strongly_Typed_Events_Responses_And_Http_Transport()
    {
        string exportJson = """
        {
            "export": {
                "plugins": [
                    {
                        "id": "snake_game",
                        "services": [
                            {
                                "name": "snake_game",
                                "actions": [
                                    {
                                        "name": "submit_score",
                                        "transport": "http",
                                        "params": [
                                            { "name": "score", "type": "integer" },
                                            { "name": "snake_length", "type": "integer" }
                                        ],
                                        "returns": [
                                            { "name": "rank", "type": "integer" },
                                            { "name": "new_high_score", "type": "boolean" }
                                        ]
                                    }
                                ],
                                "events": [
                                    {
                                        "name": "food_spawned",
                                        "topic": "snake:events",
                                        "payload": [
                                            { "name": "x", "type": "integer" },
                                            { "name": "y", "type": "integer" },
                                            { "name": "points", "type": "integer" }
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

        string code = ExoCodeGenerator.GenerateFromExportJson(exportJson, "Snake.Client");

        // Request & Response models
        Assert.Contains("public class SnakeGameSubmitScoreRequest", code);
        Assert.Contains("public class SnakeGameSubmitScoreResponse", code);
        Assert.Contains("public long Rank { get; set; }", code);
        Assert.Contains("public bool NewHighScore { get; set; }", code);

        // Event model and event subscription
        Assert.Contains("public class SnakeGameFoodSpawnedEvent", code);
        Assert.Contains("public long X { get; set; }", code);
        Assert.Contains("public long Y { get; set; }", code);
        Assert.Contains("public long Points { get; set; }", code);
        Assert.Contains("public event Action<SnakeGameFoodSpawnedEvent>? OnFoodSpawned;", code);

        // HTTP transport preference and typed return type
        Assert.Contains("public Task<SnakeGameSubmitScoreResponse> SubmitScoreAsync(long score, long snakeLength, CancellationToken cancellationToken = default)", code);
        Assert.Contains("ExoTransportPreference.Http", code);
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
        Assert.True(File.Exists(Path.Combine(editorDir, "ExoforgeBehaviourEditor.cs")));

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
        Assert.Equal("ws://127.0.0.1:4000/ws", Exoforge.Unity.Editor.ExoforgeEditorConfig.DefaultServerUrl);
        Assert.Equal("dev:developer", Exoforge.Unity.Editor.ExoforgeEditorConfig.DefaultAdminToken);
        Assert.Equal("Exoforge", Exoforge.Unity.Editor.ExoforgeEditorConfig.DefaultWorkspaceRelPath);
        Assert.Equal("Assets/Exoforge/Generated/ExoforgeServices.g.cs", Exoforge.Unity.Editor.ExoforgeEditorConfig.DefaultGeneratedScriptRelPath);
    }

    [Fact]
    public void EditorConfig_Session_Management_Works()
    {
        Exoforge.Unity.Editor.ExoforgeEditorConfig.SaveSession("custom_token_123", "player_456", new[] { "admin", "player" });
        Assert.Equal("custom_token_123", Exoforge.Unity.Editor.ExoforgeEditorConfig.AdminToken);
        Assert.Equal("player_456", Exoforge.Unity.Editor.ExoforgeEditorConfig.PlayerId);
        Assert.Equal("admin,player", Exoforge.Unity.Editor.ExoforgeEditorConfig.Scopes);

        Exoforge.Unity.Editor.ExoforgeEditorConfig.LastSyncTime = "2026-10-03 18:00:00";
        Assert.Equal("2026-10-03 18:00:00", Exoforge.Unity.Editor.ExoforgeEditorConfig.LastSyncTime);

        Exoforge.Unity.Editor.ExoforgeEditorConfig.ClearSession();
        Assert.Empty(Exoforge.Unity.Editor.ExoforgeEditorConfig.AdminToken);
        Assert.Empty(Exoforge.Unity.Editor.ExoforgeEditorConfig.PlayerId);
        Assert.Empty(Exoforge.Unity.Editor.ExoforgeEditorConfig.Scopes);
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
