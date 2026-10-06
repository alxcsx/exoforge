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

    [JsonPropertyName("default_environment")]
    public string DefaultEnvironment { get; set; } = "local";

    [JsonPropertyName("environments")]
    public Dictionary<string, ExoEnvironmentConfig> Environments { get; set; } = new()
    {
        ["local"] = new ExoEnvironmentConfig
        {
            WsUrl = "ws://127.0.0.1:4000/ws",
            HttpUrl = "http://127.0.0.1:4001",
            Token = "dev:developer"
        }
    };

    [JsonPropertyName("codegen")]
    public ExoCodegenConfig Codegen { get; set; } = new();

    [JsonPropertyName("plugins_dir")]
    public string PluginsDir { get; set; } = "plugins";
}

public class ExoEnvironmentConfig
{
    [JsonPropertyName("ws_url")]
    public string WsUrl { get; set; } = "ws://127.0.0.1:4000/ws";

    [JsonPropertyName("http_url")]
    public string HttpUrl { get; set; } = "http://127.0.0.1:4001";

    [JsonPropertyName("token")]
    public string Token { get; set; } = "dev:developer";
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

    public string PluginsPath => ResolveWorkspacePath(Config.PluginsDir);
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

    public static bool Exists(string rootPath)
    {
        string fullRoot = Path.GetFullPath(rootPath);
        return File.Exists(Path.Combine(fullRoot, ConfigFileName)) ||
               File.Exists(Path.Combine(fullRoot, "Exoforge", ConfigFileName)) ||
               File.Exists(Path.Combine(fullRoot, "Assets", "Exoforge", ConfigFileName)) ||
               File.Exists(Path.Combine(fullRoot, "exoforge", ConfigFileName));
    }

    public static ExoWorkspace Load(string rootPath)
    {
        string fullRoot = Path.GetFullPath(rootPath);
        string configPath = Path.Combine(fullRoot, ConfigFileName);

        if (!File.Exists(configPath))
        {
            // First check standard Unity path: rootPath/Assets/Exoforge/exoforge.json
            string unitySubPath = Path.Combine(fullRoot, "Assets", "Exoforge", ConfigFileName);
            if (File.Exists(unitySubPath))
            {
                configPath = unitySubPath;
                fullRoot = Path.GetDirectoryName(configPath)!;
            }
            else
            {
                // Project-level workspace: rootPath/Exoforge/exoforge.json
                string projectSubPath = Path.Combine(fullRoot, "Exoforge", ConfigFileName);

                // Legacy: rootPath/exoforge/exoforge.json
                string legacySubPath = Path.Combine(fullRoot, "exoforge", ConfigFileName);

                string? subPath =
                    File.Exists(projectSubPath) ? projectSubPath :
                    File.Exists(legacySubPath) ? legacySubPath : null;

                if (subPath != null)
                {
                    configPath = subPath;
                    fullRoot = Path.GetDirectoryName(configPath)!;
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
        ws.Save();

        // Ensure folders exist
        Directory.CreateDirectory(ws.PluginsPath);
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
