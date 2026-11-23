using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
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

    /// <summary>
    /// Extensions in <see cref="ExtensionsDir"/> this project leaves out (an arcade sample that does not need them).
    /// Everything else in the directory is included. Omitted from the file when empty.
    /// </summary>
    [JsonPropertyName("excluded_extensions")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public List<string>? ExcludedExtensions { get; set; }
}

public class ExoEnvironmentConfig
{
    [JsonPropertyName("ws_url")]
    public string WsUrl { get; set; } = "ws://localhost:4000/ws";

    [JsonPropertyName("http_url")]
    public string HttpUrl { get; set; } = "http://localhost:4001";

    [JsonPropertyName("token")]
    public string Token { get; set; } = "";

    /// <summary>
    /// The single-use credential that mints the next access token. A saved CLI session is the
    /// same pair a client holds, so `exo connect --save` keeps working past the access token's hour
    /// instead of minting a long-lived service credential.
    /// </summary>
    [JsonPropertyName("refresh_token")]
    public string RefreshToken { get; set; } = "";
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

    public bool IsExcluded(string name) =>
        Config.ExcludedExtensions is { Count: > 0 } excluded &&
        excluded.Contains(ExoScaffolder.NormalizeExtensionName(name), StringComparer.Ordinal);

    /// <summary>A folder in the extensions directory that is an extension at all: not hidden (<c>.feed</c>) and not a dotted project folder (<c>wallet.Tests</c>).</summary>
    public static bool IsExtensionFolder(string? name) =>
        !string.IsNullOrEmpty(name) && !name!.StartsWith('.') && !name.Contains('.');

    /// <summary>
    /// A test extension, hidden from the editor lists: named <c>test_*</c>, <c>*_test</c> or <c>*_tests</c>, or
    /// declaring itself one in its manifest (<c>"test": true</c>, or <c>"category": "Test"</c>).
    /// </summary>
    public static bool IsTestExtension(string dir)
    {
        string name = Path.GetFileName(dir.TrimEnd('/', '\\'));
        if (name.StartsWith("test_", StringComparison.OrdinalIgnoreCase) ||
            name.EndsWith("_test", StringComparison.OrdinalIgnoreCase) ||
            name.EndsWith("_tests", StringComparison.OrdinalIgnoreCase)) return true;
        try
        {
            string manifest = Path.Combine(dir, "manifest.json");
            if (!File.Exists(manifest)) return false;
            using var doc = System.Text.Json.JsonDocument.Parse(File.ReadAllText(manifest));
            var root = doc.RootElement;
            if (root.TryGetProperty("test", out var t) && t.ValueKind == System.Text.Json.JsonValueKind.True) return true;
            return root.TryGetProperty("category", out var c) && c.ValueKind == System.Text.Json.JsonValueKind.String &&
                   string.Equals(c.GetString(), "Test", StringComparison.OrdinalIgnoreCase);
        }
        catch { return false; }
    }

    /// <summary>Every extension folder in the extensions directory, included or not, in name order.</summary>
    public List<string> AllExtensions() =>
        Directory.Exists(ExtensionsPath)
            ? Directory.GetDirectories(ExtensionsPath).Select(Path.GetFileName).Where(IsExtensionFolder).Select(n => n!).OrderBy(n => n, StringComparer.Ordinal).ToList()
            : new List<string>();

    /// <summary>The extensions to build and deploy: the extensions directory minus <c>excluded_extensions</c>.</summary>
    public List<string> IncludedExtensions() => AllExtensions().Where(n => !IsExcluded(n)).ToList();

    /// <summary>Marks extensions excluded or included again (names are normalized) and saves exoforge.json. Returns whether anything changed.</summary>
    public bool SetExcluded(IEnumerable<string> names, bool excluded)
    {
        var list = (Config.ExcludedExtensions ?? new List<string>()).ToList();
        bool changed = false;
        foreach (string raw in names)
        {
            string name = ExoScaffolder.NormalizeExtensionName(raw);
            if (excluded && !list.Contains(name, StringComparer.Ordinal)) { list.Add(name); changed = true; }
            else if (!excluded && list.RemoveAll(n => string.Equals(n, name, StringComparison.Ordinal)) > 0) changed = true;
        }

        if (!changed) return false;
        list.Sort(StringComparer.Ordinal);
        Config.ExcludedExtensions = list.Count == 0 ? null : list;
        Save();
        return true;
    }

    /// <summary>The problems with the included set: an included extension that needs a provider that is excluded.</summary>
    public IReadOnlyList<string> ValidateIncluded() =>
        ExoDeployOrder.ValidateIncluded(ExtensionsPath, AllExtensions(), Config.ExcludedExtensions ?? new List<string>());

    public IReadOnlyList<ExclusionProblem> FindExclusionProblems() =>
        ExoDeployOrder.FindExclusionProblems(ExtensionsPath, AllExtensions(), Config.ExcludedExtensions ?? new List<string>());

    public void Save()
    {
        string json = JsonSerializer.Serialize(Config, new JsonSerializerOptions { WriteIndented = true });
        File.WriteAllText(ConfigPath, json);
    }

    public void SaveSessionToken(string token, string? refreshToken = null, string? environmentName = null)
    {
        if (string.IsNullOrWhiteSpace(token)) return;

        string target = environmentName ?? Config.DefaultEnvironment;
        if (!Config.Environments.TryGetValue(target, out var env))
        {
            env = new ExoEnvironmentConfig();
            Config.Environments[target] = env;
        }

        env.Token = token;
        if (!string.IsNullOrEmpty(refreshToken))
        {
            env.RefreshToken = refreshToken;
        }

        Save();
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
