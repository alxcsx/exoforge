using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Exoforge.Management;

public class ExoProjectConfig
{
    [JsonPropertyName("project_name")]
    public string ProjectName { get; set; } = "ExoforgeProject";

    [JsonPropertyName("studio_name")]
    public string StudioName { get; set; } = "Exoforge Studio";

    [JsonPropertyName("description")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Description { get; set; }

    [JsonPropertyName("website_url")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? WebsiteUrl { get; set; }

    [JsonPropertyName("custom_metadata")]
    public Dictionary<string, string> CustomMetadata { get; set; } = new();

    [JsonPropertyName("default_environment")]
    public string DefaultEnvironment { get; set; } = "local";

    [JsonPropertyName("setup_completed")]
    public bool SetupCompleted { get; set; } = false;

    [JsonPropertyName("environments")]
    public Dictionary<string, ExoEnvironmentConfig> Environments { get; set; } = new()
    {
        ["local"] = new ExoEnvironmentConfig
        {
            WsUrl = "ws://localhost:4000/ws",
            HttpUrl = "http://localhost:4001",
            Token = ""
        }
    };

    [JsonPropertyName("codegen")]
    public ExoCodegenConfig Codegen { get; set; } = new();

    [JsonPropertyName("extensions_dir")]
    public string ExtensionsDir { get; set; } = "extensions";
}

public class ExoEnvironmentConfig
{
    [JsonPropertyName("ws_url")]
    public string WsUrl { get; set; } = "ws://localhost:4000/ws";

    [JsonPropertyName("http_url")]
    public string HttpUrl { get; set; } = "http://localhost:4001";

    [JsonPropertyName("token")]
    public string Token { get; set; } = "";
}

public class ExoCodegenConfig
{
    [JsonPropertyName("output_path")]
    public string OutputPath { get; set; } = "Assets/Exoforge/Generated/ExoforgeServices.g.cs";

    [JsonPropertyName("namespace")]
    public string Namespace { get; set; } = "Exoforge.Client";
}

public class ExoWorkspace
{
    public const string ConfigFileName = "exoforge.json";

    public string RootPath { get; }
    public string ConfigPath { get; }
    public ExoProjectConfig Config { get; private set; }

    public string ExtensionsPath => ResolveWorkspacePath(Config.ExtensionsDir);
    public string GeneratedPath => ResolveWorkspacePath(Config.Codegen.OutputPath);

    private string ResolveWorkspacePath(string path)
    {
        if (Path.IsPathRooted(path)) return path;

        string normPath = path.Replace('\\', '/').TrimStart('/');

        // Unity-consumed artifacts (generated client, runtime config) live under Assets/,
        // which is project-root relative — not workspace relative. The workspace itself
        // (exoforge.json + plugins) sits outside Assets/ so dotnet tooling is unconstrained.
        if (normPath.StartsWith("Assets/", StringComparison.OrdinalIgnoreCase))
        {
            if (Directory.Exists(Path.Combine(RootPath, "Assets")))
            {
                return Path.GetFullPath(Path.Combine(RootPath, normPath));
            }

            string projectRoot = Directory.GetParent(RootPath)?.FullName ?? RootPath;

            if (Directory.Exists(Path.Combine(projectRoot, "Assets")))
            {
                return Path.GetFullPath(Path.Combine(projectRoot, normPath));
            }
        }

        return Path.GetFullPath(Path.Combine(RootPath, normPath));
    }

    public ExoWorkspace(string rootPath, ExoProjectConfig config)
    {
        RootPath = Path.GetFullPath(rootPath);
        ConfigPath = Path.Combine(RootPath, ConfigFileName);
        Config = config;
    }

    public static string? FindRoot(string startPath)
    {
        string current = Path.GetFullPath(startPath);
        var dir = new DirectoryInfo(current);

        while (dir != null)
        {
            string direct = Path.Combine(dir.FullName, ConfigFileName);
            if (File.Exists(direct))
            {
                return dir.FullName;
            }

            string projectSub = Path.Combine(dir.FullName, "Exoforge", ConfigFileName);
            if (File.Exists(projectSub))
            {
                return Path.Combine(dir.FullName, "Exoforge");
            }

            string unitySub = Path.Combine(dir.FullName, "Assets", "Exoforge", ConfigFileName);
            if (File.Exists(unitySub))
            {
                return Path.Combine(dir.FullName, "Assets", "Exoforge");
            }

            string legacySub = Path.Combine(dir.FullName, "exoforge", ConfigFileName);
            if (File.Exists(legacySub))
            {
                return Path.Combine(dir.FullName, "exoforge");
            }

            dir = dir.Parent;
        }

        return null;
    }

    public static bool Exists(string rootPath)
    {
        string fullRoot = Path.GetFullPath(rootPath);
        return File.Exists(Path.Combine(fullRoot, ConfigFileName)) ||
               File.Exists(Path.Combine(fullRoot, "Exoforge", ConfigFileName)) ||
               File.Exists(Path.Combine(fullRoot, "Assets", "Exoforge", ConfigFileName)) ||
               File.Exists(Path.Combine(fullRoot, "exoforge", ConfigFileName)) ||
               FindRoot(fullRoot) != null;
    }

    public static ExoWorkspace Load(string rootPath)
    {
        string fullRoot = Path.GetFullPath(rootPath);
        string configPath = Path.Combine(fullRoot, ConfigFileName);

        if (!File.Exists(configPath))
        {
            // Project-level workspace: rootPath/Exoforge/exoforge.json
            string projectSubPath = Path.Combine(fullRoot, "Exoforge", ConfigFileName);
            string unitySubPath = Path.Combine(fullRoot, "Assets", "Exoforge", ConfigFileName);
            string legacySubPath = Path.Combine(fullRoot, "exoforge", ConfigFileName);

            string? subPath =
                File.Exists(projectSubPath) ? projectSubPath :
                File.Exists(unitySubPath) ? unitySubPath :
                File.Exists(legacySubPath) ? legacySubPath : null;

            if (subPath != null)
            {
                configPath = subPath;
                fullRoot = Path.GetDirectoryName(configPath)!;
            }
            else
            {
                string? discovered = FindRoot(fullRoot);
                if (discovered != null)
                {
                    fullRoot = discovered;
                    configPath = Path.Combine(fullRoot, ConfigFileName);
                }
            }
        }

        if (File.Exists(configPath))
        {
            string json = File.ReadAllText(configPath);
            var cfg = JsonSerializer.Deserialize<ExoProjectConfig>(json) ?? new ExoProjectConfig();
            return new ExoWorkspace(fullRoot, cfg);
        }

        return new ExoWorkspace(fullRoot, new ExoProjectConfig());
    }

    public static ExoWorkspace Initialize(string rootPath, string projectName = "ExoforgeProject")
    {
        string fullRoot = Path.GetFullPath(rootPath);
        string configPath = Path.Combine(fullRoot, ConfigFileName);

        var config = new ExoProjectConfig
        {
            ProjectName = projectName
        };

        var ws = new ExoWorkspace(fullRoot, config);

        // Create the workspace root before writing into it. On a new project nothing exists yet, and
        // Save would fail with "Could not find a part of the path .../exoforge.json" — the sample
        // project hid this because its Exoforge/ folder is committed.
        Directory.CreateDirectory(fullRoot);
        ws.Save();

        Directory.CreateDirectory(ws.ExtensionsPath);
        string genDir = Path.GetDirectoryName(ws.GeneratedPath)!;
        if (!string.IsNullOrEmpty(genDir))
        {
            Directory.CreateDirectory(genDir);
        }

        return ws;
    }

    public void Save()
    {
        string json = JsonSerializer.Serialize(Config, new JsonSerializerOptions { WriteIndented = true });
        File.WriteAllText(ConfigPath, json);
    }

    public ExoEnvironmentConfig GetActiveEnvironment(string? envName = null)
    {
        string target = envName ?? Config.DefaultEnvironment;
        if (Config.Environments.TryGetValue(target, out var env))
        {
            return env;
        }

        return new ExoEnvironmentConfig();
    }
}
