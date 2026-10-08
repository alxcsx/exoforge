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

        // The temp workspace has no repo above it, so point the scaffolder at the real SDK.
        string createdDir = ExoScaffolder.ScaffoldPlugin(ws.PluginsPath, "guild_system");

        Assert.True(Directory.Exists(createdDir));

        // Per-plugin solution + src/ layout.
        string slnFile = Path.Combine(createdDir, "guild_system.slnx");
        Assert.True(File.Exists(slnFile));
        Assert.Contains("src/guild_system.csproj", File.ReadAllText(slnFile));

        string csprojFile = Path.Combine(createdDir, "src", "guild_system.csproj");
        Assert.True(File.Exists(csprojFile));

        string csprojText = File.ReadAllText(csprojFile);
        // The whole point: a plugin project names the package and no path, so it builds from a feed
        // wherever it is put. The generator and the manifest plumbing arrive with the package.
        Assert.Contains("<PackageReference Include=\"Exoforge.Plugin.SDK\"", csprojText);
        Assert.DoesNotContain("ProjectReference", csprojText);
        Assert.DoesNotContain("sdk/csharp", csprojText);

        string serviceFile = Path.Combine(createdDir, "src", "GuildSystemPlugin.cs");
        Assert.True(File.Exists(serviceFile));
        string serviceText = File.ReadAllText(serviceFile);
        Assert.Contains("[ExoService(\"guild_system\"", serviceText);
        Assert.Contains("public class GuildSystemPlugin", serviceText);
        Assert.Contains("[ExoAction]", serviceText);
        Assert.Contains("[ExoResource(\"guild_system_items\"", serviceText);

        // Injection is per instance, and the entry point, the dispatch table and the JSON context are
        // all generated - the scaffold writes none of them.
        Assert.Contains("public IDatabase? Database { get; set; }", serviceText);
        Assert.DoesNotContain("public static void Main", serviceText);
        Assert.DoesNotContain("JsonContext", serviceText);
        Assert.False(File.Exists(Path.Combine(createdDir, "src", "GuildSystemJsonContext.cs")));

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
    public void PluginStubs_FiltersToRequestedServices()
    {
        string json = """
        {
          "export": { "plugins": [ { "services": [
            { "name": "player_data", "actions": [ { "name": "get_player", "params": [{"name":"player_id","type":"string"}], "returns": {} } ] },
            { "name": "auth", "actions": [ { "name": "login", "params": [{"name":"email","type":"string"}], "returns": {} } ] }
          ] } ] }
        }
        """;

        string scoped = ExoCodeGenerator.GeneratePluginStubs(json, "Exoforge.Test.Generated", new[] { "player_data" });

        Assert.Contains("PlayerDataServiceClient", scoped);
        Assert.DoesNotContain("AuthServiceClient", scoped);
    }

    [Fact]
    public void ReadManifestDependencies_ParsesAndFallsBack()
    {
        string pluginDir = Path.Combine(_tempDir, "plugin");
        Directory.CreateDirectory(pluginDir);
        File.WriteAllText(Path.Combine(pluginDir, "manifest.exs"), "%{\n  dependencies: [:database, :player_data],\n}");

        var deps = ExoDeployer.ReadManifestDependencies(pluginDir);
        Assert.NotNull(deps);
        Assert.Equal(new[] { "database", "player_data" }, deps!);
        Assert.Null(ExoDeployer.ReadManifestDependencies(_tempDir));
    }

    [Fact]
    public void SourceFingerprint_ChangesWithContent()
    {
        string dir = Path.Combine(_tempDir, "fp");
        Directory.CreateDirectory(dir);
        File.WriteAllText(Path.Combine(dir, "a.cs"), "class A {}");

        string first = ExoDeployer.ComputeSourceFingerprint(dir);
        File.WriteAllText(Path.Combine(dir, "a.cs"), "class A { int X; }");
        string second = ExoDeployer.ComputeSourceFingerprint(dir);

        Assert.Equal(8, first.Length);
        Assert.NotEqual(first, second);
    }

    [Fact]
    public void ReadManifestVersion_ReturnsBuildMetadata()
    {
        string dir = Path.Combine(_tempDir, "mv");
        Directory.CreateDirectory(dir);
        File.WriteAllText(Path.Combine(dir, "manifest.exs"), "%{\n  version: \"1.0.0+abc12345\",\n}");

        Assert.Equal("1.0.0+abc12345", ExoDeployer.ReadManifestVersion(dir));
        Assert.Null(ExoDeployer.ReadManifestVersion(_tempDir));
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
                                        ],
                                        "returns": "integer"
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
        // A declared return type is honoured; there is no untyped object overload to fall back to.
        Assert.Contains("public Task<long> IncrementAsync(long counterId, long amount, CancellationToken cancellationToken = default)", code);
        Assert.Contains("public Task<long> IncrementAsync(SampleWasmIncrementRequest request, CancellationToken cancellationToken = default)", code);
        Assert.DoesNotContain("object? payload = null", code);
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

        // Runtime holds the Unity wrappers, and nothing engine-agnostic.
        string runtimeDir = Path.Combine(unityPkgDir, "Runtime");
        Assert.True(Directory.Exists(runtimeDir));
        Assert.True(File.Exists(Path.Combine(runtimeDir, "Exoforge.SDK.asmdef")));
        Assert.True(File.Exists(Path.Combine(runtimeDir, "ExoforgeManager.cs")));
        Assert.True(File.Exists(Path.Combine(runtimeDir, "ExoforgeSDK.cs")));
        Assert.True(File.Exists(Path.Combine(runtimeDir, "ExoforgeAuth.cs")));
        Assert.True(File.Exists(Path.Combine(runtimeDir, "ExoTokenStore.cs")));

        // Editor holds the Control Center and the editor tooling.
        string editorDir = Path.Combine(unityPkgDir, "Editor");
        Assert.True(Directory.Exists(editorDir));
        Assert.True(File.Exists(Path.Combine(editorDir, "Exoforge.SDK.Editor.asmdef")));
        Assert.True(File.Exists(Path.Combine(editorDir, "ExoforgeControlCenter.cs")));
        Assert.True(File.Exists(Path.Combine(editorDir, "ExoforgeEditorConfig.cs")));
        Assert.True(File.Exists(Path.Combine(editorDir, "ExoforgeSceneSetup.cs")));
        Assert.True(File.Exists(Path.Combine(editorDir, "ExoforgeManagerEditor.cs")));

        // The engine-agnostic libraries arrive as assemblies, not as source (M29). If any of these
        // reappears as .cs in the package, the package has started owning code that is not Unity's
        // and the next engine can no longer reuse it.
        Assert.True(File.Exists(Path.Combine(runtimeDir, "Plugins", "Exoforge.Client.dll")),
            "Runtime/Plugins/Exoforge.Client.dll is missing - run 'just build-unity-sdk'");
        Assert.True(File.Exists(Path.Combine(editorDir, "Plugins", "Exoforge.Management.dll")),
            "Editor/Plugins/Exoforge.Management.dll is missing - run 'just build-unity-sdk'");

        string[] engineAgnostic =
        {
            "ExoClient", "ExoTransport", "ExoDispatcher", "Protocol", "ExoBackoff",
            "ExoDeployer", "ExoWorkspace", "ExoScaffolder", "ExoCodeGenerator",
        };

        foreach (string name in engineAgnostic)
        {
            Assert.False(
                File.Exists(Path.Combine(runtimeDir, name + ".cs")) ||
                File.Exists(Path.Combine(editorDir, name + ".cs")) ||
                File.Exists(Path.Combine(editorDir, "Management", name + ".cs")),
                name + ".cs is engine-agnostic and must not live in the Unity package");
        }


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
    public void EditorConfig_Holds_Only_Editor_Local_State()
    {
        // The connection and the session live in exoforge.json and the token store. What is left here
        // is genuinely per-editor: where the workspace is, which environment is selected, local paths.
        Assert.Equal("Exoforge", Exoforge.Unity.Editor.ExoforgeEditorConfig.DefaultWorkspaceRelPath);
        Assert.Equal("Assets/Exoforge/Generated/ExoforgeServices.g.cs", Exoforge.Unity.Editor.ExoforgeEditorConfig.DefaultGeneratedScriptRelPath);

        Exoforge.Unity.Editor.ExoforgeEditorConfig.SelectedEnvironment = "staging";
        Assert.Equal("staging", Exoforge.Unity.Editor.ExoforgeEditorConfig.SelectedEnvironment);

        Exoforge.Unity.Editor.ExoforgeEditorConfig.LastSyncTime = "2026-10-03 18:00:00";
        Assert.Equal("2026-10-03 18:00:00", Exoforge.Unity.Editor.ExoforgeEditorConfig.LastSyncTime);
    }

    [Fact]
    public void EditorConfig_Does_Not_Shadow_The_Workspace_Or_The_Token_Store()
    {
        // These were duplicated here, so the editor had three places to configure one thing. If any
        // of them comes back, it has started mirroring the workspace again.
        var type = typeof(Exoforge.Unity.Editor.ExoforgeEditorConfig);

        var members = type.GetProperties().Select(p => p.Name)
            .Concat(type.GetMethods().Select(m => m.Name))
            .ToList();

        string[] shadowed =
        {
            "ServerUrl", "AdminToken", "PlayerId", "Scopes",
            "SaveSession", "ClearSession", "EnvironmentPresets",
        };

        foreach (string name in shadowed)
        {
            Assert.DoesNotContain(name, members);
        }
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

    /// <summary>
    /// A plugin's own records need source-generated JSON metadata, and its own compile cannot supply
    /// it - a source generator's output is invisible to the System.Text.Json generator. The stubs are
    /// a real file, so they carry it.
    /// </summary>
    [Fact]
    public void PluginStubs_Register_The_Plugins_Own_Records_For_Json()
    {
        string exportJson = """
        {
            "plugins": [
                {
                    "id": "snake_leaderboard",
                    "services": [
                        {
                            "name": "snake_leaderboard",
                            "actions": [
                                {
                                    "name": "get_leaderboard",
                                    "scope": "global",
                                    "params": [],
                                    "returns": { "player_id": "string" },
                                    "returns_list": true,
                                    "returns_type": "global::MyGame.SnakeLeaderboardEntry"
                                }
                            ],
                            "events": [
                                { "name": "score_submitted", "payload_type": "global::MyGame.SnakeScoreSubmitted" }
                            ],
                            "resources": [
                                {
                                    "name": "snake_scores",
                                    "primary_key": "player_id",
                                    "columns": [ { "name": "player_id", "type": "string" } ],
                                    "type": "global::MyGame.SnakeScoreRecord"
                                }
                            ]
                        }
                    ]
                }
            ]
        }
        """;

        string code = ExoCodeGenerator.GeneratePluginStubs(exportJson, pluginId: "snake_leaderboard");

        Assert.Contains("[JsonSerializable(typeof(global::MyGame.SnakeScoreRecord))]", code);
        Assert.Contains("[JsonSerializable(typeof(global::MyGame.SnakeScoreSubmitted))]", code);
        Assert.Contains("[JsonSerializable(typeof(global::MyGame.SnakeLeaderboardEntry))]", code);

        // The model is named after the contract's record, not after the action.
        Assert.Contains("public class SnakeLeaderboardEntry", code);

        // Another plugin's records are not this plugin's business.
        string other = ExoCodeGenerator.GeneratePluginStubs(exportJson, pluginId: "something_else");
        Assert.DoesNotContain("MyGame.SnakeScoreRecord", other);
    }
}
