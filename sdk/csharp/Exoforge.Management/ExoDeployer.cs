using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Exoforge.Client;

namespace Exoforge.Management;

public class ExoDeployer
{
    private readonly ExoWorkspace _workspace;

    public ExoDeployer(ExoWorkspace workspace)
    {
        _workspace = workspace ?? throw new ArgumentNullException(nameof(workspace));
    }

    public async Task<ExoClient> CreateConnectedClientAsync(
        string? environmentName = null,
        CancellationToken cancellationToken = default)
    {
        var env = _workspace.GetActiveEnvironment(environmentName);
        var client = new ExoClient();

        await client.ConnectAsync(new Uri(env.WsUrl), cancellationToken).ConfigureAwait(false);

        if (!string.IsNullOrEmpty(env.Token))
        {
            var auth = await client.AuthenticateAsync(env.Token, cancellationToken: cancellationToken).ConfigureAwait(false);
            if (!auth.IsSuccess)
            {
                throw new InvalidOperationException($"Failed to authenticate with cluster: {auth.Error}");
            }
        }

        return client;
    }

    public async Task<string> UploadPluginAsync(
        string pluginName,
        string? environmentName = null,
        ExoClient? existingClient = null,
        CancellationToken cancellationToken = default)
    {
        string cleanName = pluginName.Trim().ToLowerInvariant().Replace("-", "_");
        string pluginDir = Path.Combine(_workspace.PluginsPath, cleanName);

        // A plugin is either a WASM reactor (.wasm) or a native AOT binary (no extension).
        string? wasmPath = null;
        string wasmCandidate = Path.Combine(pluginDir, $"{cleanName}.wasm");

        if (File.Exists(wasmCandidate))
        {
            wasmPath = wasmCandidate;
        }
        else
        {
            var matches = Directory.GetFiles(pluginDir, "*.wasm", SearchOption.AllDirectories)
                .Where(path => !IsBuildPath(path))
                .ToArray();

            if (matches.Length > 0)
            {
                wasmPath = matches[0];
            }
        }

        string pluginType = wasmPath != null ? "wasm" : "native";
        string binaryPath = wasmPath ?? Path.Combine(pluginDir, cleanName);

        // Windows builds append .exe; native deploys are usually cross-built for a Linux RID.
        if (wasmPath == null && !File.Exists(binaryPath) && File.Exists(binaryPath + ".exe"))
        {
            binaryPath += ".exe";
        }

        if (!File.Exists(binaryPath))
        {
            throw new FileNotFoundException(
                $"No plugin binary found for '{cleanName}' (expected {cleanName}.wasm or {cleanName}). Build it first.");
        }

        byte[] binaryBytes = await File.ReadAllBytesAsync(binaryPath, cancellationToken).ConfigureAwait(false);
        string binaryBase64 = Convert.ToBase64String(binaryBytes);

        string? manifestContent = null;
        string manifestPath = Path.Combine(pluginDir, "manifest.exs");
        if (File.Exists(manifestPath))
        {
            manifestContent = await File.ReadAllTextAsync(manifestPath, cancellationToken).ConfigureAwait(false);
        }

        var client = existingClient ?? await CreateConnectedClientAsync(environmentName, cancellationToken).ConfigureAwait(false);
        try
        {
            var payload = new
            {
                name = cleanName,
                type = pluginType,
                // Named 'binary', not 'wasm_binary': the same field carries the NativeAOT
                // executable for native plugins, which confused anyone reading the protocol.
                binary = binaryBase64,
                manifest = manifestContent
            };

            var result = await client.SendActionAsync<JsonElement>("plugin_manager", "upload_plugin", payload, cancellationToken: cancellationToken).ConfigureAwait(false);
            return result.ToString();
        }
        finally
        {
            if (existingClient == null)
            {
                client.Dispose();
            }
        }
    }

    /// <summary>
    /// Confirms the cluster really has the plugin, and reports the version it is running.
    ///
    /// <c>upload_plugin</c> returning <c>installed</c> only means the files landed. A plugin that
    /// fails to boot afterwards is otherwise invisible until you try to call one of its actions —
    /// which is exactly the wrong moment to find out.
    /// </summary>
    public async Task<PluginDeploymentStatus> VerifyPluginAsync(
        string pluginName,
        string? expectedVersion = null,
        string? environmentName = null,
        ExoClient? existingClient = null,
        CancellationToken cancellationToken = default)
    {
        string cleanName = NormalizePluginName(pluginName);
        var client = existingClient ?? await CreateConnectedClientAsync(environmentName, cancellationToken).ConfigureAwait(false);

        try
        {
            JsonElement result;
            try
            {
                result = await client.SendActionAsync<JsonElement>(
                    "plugin_manager", "get_plugin", new { id = cleanName }, cancellationToken: cancellationToken).ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                return new PluginDeploymentStatus(false, null, null, $"cluster does not have '{cleanName}': {ex.Message}");
            }

            string? version = ReadString(result, "plugin", "version");
            string? type = ReadString(result, "plugin", "type");

            if (version == null)
            {
                return new PluginDeploymentStatus(false, null, null, $"cluster does not have '{cleanName}'");
            }

            if (expectedVersion != null && !string.Equals(version, expectedVersion, StringComparison.Ordinal))
            {
                return new PluginDeploymentStatus(
                    true, version, type,
                    $"cluster is running {version}, but {expectedVersion} was just deployed");
            }

            return new PluginDeploymentStatus(true, version, type, "loaded");
        }
        finally
        {
            if (existingClient == null)
            {
                client.Dispose();
            }
        }
    }

    /// <summary>
    /// Re-boots an installed plugin from the files already on the cluster. No rebuild, no re-upload.
    /// </summary>
    public async Task<JsonElement> ReloadPluginAsync(
        string pluginName,
        string? environmentName = null,
        ExoClient? existingClient = null,
        CancellationToken cancellationToken = default)
    {
        string cleanName = NormalizePluginName(pluginName);
        var client = existingClient ?? await CreateConnectedClientAsync(environmentName, cancellationToken).ConfigureAwait(false);

        try
        {
            return await client.SendActionAsync<JsonElement>(
                "plugin_manager", "reload_plugin", new { id = cleanName }, cancellationToken: cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            if (existingClient == null)
            {
                client.Dispose();
            }
        }
    }

    /// <summary>
    /// Recent log lines the plugin emitted. Without this a plugin author has no way to see their own
    /// plugin running — the output only reaches the server's log.
    /// </summary>
    public async Task<List<PluginLogLine>> GetPluginLogsAsync(
        string pluginName,
        int limit = 100,
        string? environmentName = null,
        ExoClient? existingClient = null,
        CancellationToken cancellationToken = default)
    {
        string cleanName = NormalizePluginName(pluginName);
        var client = existingClient ?? await CreateConnectedClientAsync(environmentName, cancellationToken).ConfigureAwait(false);

        try
        {
            var result = await client.SendActionAsync<JsonElement>(
                "plugin_manager",
                "logs",
                new { id = cleanName, limit },
                cancellationToken: cancellationToken).ConfigureAwait(false);

            var lines = new List<PluginLogLine>();

            if (result.ValueKind == JsonValueKind.Object &&
                result.TryGetProperty("lines", out var array) &&
                array.ValueKind == JsonValueKind.Array)
            {
                foreach (var entry in array.EnumerateArray())
                {
                    lines.Add(new PluginLogLine(
                        entry.TryGetProperty("at", out var at) && at.TryGetInt64(out long millis) ? millis : 0,
                        entry.TryGetProperty("level_name", out var name) ? name.GetString() ?? "info" : "info",
                        entry.TryGetProperty("message", out var message) ? message.GetString() ?? "" : ""));
                }
            }

            return lines;
        }
        finally
        {
            if (existingClient == null)
            {
                client.Dispose();
            }
        }
    }

    private static string? ReadString(JsonElement root, string outer, string inner)
    {
        if (root.ValueKind != JsonValueKind.Object) return null;
        if (!root.TryGetProperty(outer, out var obj) || obj.ValueKind != JsonValueKind.Object) return null;
        return obj.TryGetProperty(inner, out var value) ? value.ToString() : null;
    }

    public async Task<string> RemovePluginAsync(
        string pluginId,
        string? environmentName = null,
        ExoClient? existingClient = null,
        bool deleteFiles = false,
        CancellationToken cancellationToken = default)
    {
        var client = existingClient ?? await CreateConnectedClientAsync(environmentName, cancellationToken).ConfigureAwait(false);
        try
        {
            var result = await client.SendActionAsync<JsonElement>(
                "plugin_manager",
                "remove_plugin",
                new { id = pluginId, delete_files = deleteFiles },
                cancellationToken: cancellationToken).ConfigureAwait(false);
            return result.ToString();
        }
        finally
        {
            if (existingClient == null)
            {
                client.Dispose();
            }
        }
    }

    /// <summary>Fetches the raw contract export (what <c>plugin_manager.export_plugin_info</c> returns).</summary>
    public async Task<string> GetContractsExportJsonAsync(
        string? environmentName = null,
        ExoClient? existingClient = null,
        CancellationToken cancellationToken = default)
    {
        var client = existingClient ?? await CreateConnectedClientAsync(environmentName, cancellationToken).ConfigureAwait(false);
        try
        {
            var export = await client.SendActionAsync<JsonElement>(
                "plugin_manager", "export_plugin_info", null, cancellationToken: cancellationToken).ConfigureAwait(false);
            return export.GetRawText();
        }
        finally
        {
            if (existingClient == null)
            {
                client.Dispose();
            }
        }
    }

    /// <summary>Fetches the contracts and writes typed stubs into the plugin's <c>src/Generated</c> folder.</summary>
    public async Task<string> GeneratePluginStubsAsync(
        string pluginName,
        ExoClient? existingClient = null,
        CancellationToken cancellationToken = default)
    {
        string cleanName = NormalizePluginName(pluginName);
        string pluginDir = Path.Combine(_workspace.PluginsPath, cleanName);
        string output = Path.Combine(pluginDir, "src", "Generated", "PluginServices.g.cs");
        string exportJson = await GetContractsExportJsonAsync(existingClient: existingClient, cancellationToken: cancellationToken).ConfigureAwait(false);
        ExoCodeGenerator.GeneratePluginStubsToFile(exportJson, output, services: ReadManifestDependencies(pluginDir));
        return output;
    }

    /// <summary>
    /// Reads service dependencies from a plugin's generated <c>manifest.exs</c>, so stubs are only
    /// generated for the contracts it actually calls. Returns null when there is no manifest yet.
    /// </summary>
    public static IReadOnlyList<string>? ReadManifestDependencies(string pluginDir)
    {
        string manifestPath = Path.Combine(pluginDir, "manifest.exs");
        if (!File.Exists(manifestPath)) return null;

        var match = System.Text.RegularExpressions.Regex.Match(
            File.ReadAllText(manifestPath), @"dependencies:\s*\[([^\]]*)\]");

        if (!match.Success) return null;

        var dependencies = match.Groups[1].Value
            .Split(',')
            .Select(dep => dep.Trim().TrimStart(':'))
            .Where(dep => dep.Length > 0)
            .ToList();

        return dependencies.Count > 0 ? dependencies : null;
    }

    /// <summary>Generates typed stubs for every plugin in the workspace that has a project.</summary>
    public async Task<List<string>> GenerateAllPluginStubsAsync(
        string? environmentName = null,
        ExoClient? existingClient = null,
        CancellationToken cancellationToken = default)
    {
        var outputs = new List<string>();
        string pluginsDir = _workspace.PluginsPath;

        if (!Directory.Exists(pluginsDir)) return outputs;

        // One export for all plugins.
        string exportJson = await GetContractsExportJsonAsync(environmentName, existingClient, cancellationToken).ConfigureAwait(false);

        foreach (string dir in Directory.GetDirectories(pluginsDir))
        {
            string name = Path.GetFileName(dir);
            if (FindPluginCsproj(dir, name) == null) continue;

            string output = Path.Combine(dir, "src", "Generated", "PluginServices.g.cs");
            ExoCodeGenerator.GeneratePluginStubsToFile(exportJson, output, services: ReadManifestDependencies(dir));
            outputs.Add(output);
        }

        return outputs;
    }

    public async Task<int> SyncContractsAsync(
        string? environmentName = null,
        string? outputPathOverride = null,
        ExoClient? existingClient = null,
        CancellationToken cancellationToken = default)
    {
        var client = existingClient ?? await CreateConnectedClientAsync(environmentName, cancellationToken).ConfigureAwait(false);
        try
        {
            var exportResult = await client.SendActionAsync<JsonElement>("plugin_manager", "export_plugin_info", null, cancellationToken: cancellationToken).ConfigureAwait(false);

            string rawJson = exportResult.GetRawText();
            string targetPath = outputPathOverride ?? _workspace.GeneratedPath;
            ExoCodeGenerator.GenerateToFile(rawJson, targetPath, _workspace.Config.Codegen.Namespace);

            return 1;
        }
        finally
        {
            if (existingClient == null)
            {
                client.Dispose();
            }
        }
    }

    public async Task<JsonElement> GetSystemStatusAsync(
        string? environmentName = null,
        CancellationToken cancellationToken = default)
    {
        using var client = await CreateConnectedClientAsync(environmentName, cancellationToken).ConfigureAwait(false);
        return await client.SendActionAsync<JsonElement>("plugin_manager", "get_system_info", null, cancellationToken: cancellationToken).ConfigureAwait(false);
    }

    public async Task<JsonElement> ListPluginsAsync(
        string? environmentName = null,
        CancellationToken cancellationToken = default)
    {
        using var client = await CreateConnectedClientAsync(environmentName, cancellationToken).ConfigureAwait(false);
        return await client.SendActionAsync<JsonElement>("plugin_manager", "list_plugins", null, cancellationToken: cancellationToken).ConfigureAwait(false);
    }

    // -- Build --

    /// <summary>
    /// Builds a local plugin in the workspace:
    /// <list type="bullet">
    /// <item><c>build.sh</c> present → run it (WASM reactor guest).</item>
    /// <item>otherwise → <c>dotnet publish</c> a NativeAOT binary and regenerate <c>manifest.exs</c>.</item>
    /// </list>
    /// The result is staged next to <c>manifest.exs</c>, ready for <see cref="UploadPluginAsync"/>.
    /// </summary>
    public ExoPluginBuild BuildPlugin(string pluginName, string? rid = null, string dotnetPath = "dotnet", Action<string>? log = null)
    {
        string cleanName = NormalizePluginName(pluginName);
        string pluginDir = Path.Combine(_workspace.PluginsPath, cleanName);

        if (!Directory.Exists(pluginDir))
        {
            throw new DirectoryNotFoundException($"Plugin directory not found: {pluginDir}");
        }

        var output = new StringBuilder();
        void Emit(string line)
        {
            output.AppendLine(line);
            log?.Invoke(line);
        }

        string? csproj = FindPluginCsproj(pluginDir, cleanName);
        string dotnet = ResolveDotnetPath(dotnetPath);
        if (dotnet != dotnetPath)
        {
            Emit($"[build] dotnet -> {dotnet}");
        }

        string fingerprint = ComputeSourceFingerprint(pluginDir);
        // Peek, don't commit: a failed build must not burn a build number, or the numbers you see
        // in a manifest cannot be correlated with the builds that produced them.
        int buildNumber = PeekBuildNumber(pluginDir);
        string buildStamp = $"{buildNumber}.{fingerprint}";
        Emit($"[build] build {buildStamp}");

        string buildSh = Path.Combine(pluginDir, "build.sh");
        string pluginType;
        string binaryPath;

        if (File.Exists(buildSh))
        {
            pluginType = "wasm";
            Emit("[build] bash build.sh");
            RunProcess("bash", $"\"{buildSh}\"", pluginDir, Emit);
            binaryPath = FindFile(pluginDir, cleanName + ".wasm")
                ?? throw new FileNotFoundException($"build.sh did not produce a .wasm for '{cleanName}'.");
        }
        else
        {
            pluginType = "native";
            binaryPath = PublishNative(csproj ?? throw new FileNotFoundException($"No .csproj found for '{cleanName}'."), pluginDir, cleanName, rid, dotnet, buildStamp, Emit);
        }

        CommitBuildNumber(pluginDir, buildNumber);

        string manifestPath = Path.Combine(pluginDir, "manifest.exs");
        return new ExoPluginBuild(cleanName, pluginType, binaryPath, manifestPath, output.ToString());
    }

    /// <summary>Runs <see cref="BuildPlugin"/> off the calling thread.</summary>
    public Task<ExoPluginBuild> BuildPluginAsync(
        string pluginName,
        string? rid = null,
        string dotnetPath = "dotnet",
        Action<string>? log = null,
        CancellationToken cancellationToken = default)
    {
        return Task.Run(() => BuildPlugin(pluginName, rid, dotnetPath, log), cancellationToken);
    }

    private string PublishNative(string csproj, string pluginDir, string cleanName, string? rid, string dotnetPath, string buildStamp, Action<string> emit)
    {
        string targetRid = string.IsNullOrWhiteSpace(rid) ? HostRuntimeIdentifier() : rid!;
        emit($"[build] dotnet publish -c Release -r {targetRid}");
        RunProcess(dotnetPath, $"publish \"{csproj}\" -c Release -r {targetRid}", pluginDir, emit);

        // The project may sit at the plugin root or under src/; find its bin/Release output.
        string? binRelease = Directory.GetDirectories(pluginDir, "Release", SearchOption.AllDirectories)
            .FirstOrDefault(dir => string.Equals(Path.GetFileName(Path.GetDirectoryName(dir) ?? ""), "bin", StringComparison.OrdinalIgnoreCase));

        if (binRelease == null)
        {
            throw new DirectoryNotFoundException($"Build output (bin/Release) not found under {pluginDir}.");
        }

        // Stage the published native binary where the runner and deployer expect it.
        string published = Directory.GetFiles(binRelease, cleanName + "*", SearchOption.AllDirectories)
            .FirstOrDefault(path => IsPublishedBinary(path, cleanName))
            ?? throw new FileNotFoundException($"Published native binary not found for '{cleanName}' under {binRelease}.");

        string staged = Path.Combine(pluginDir, cleanName);
        File.Copy(published, staged, overwrite: true);
        MakeExecutable(staged);
        emit($"[build] staged native binary -> {staged}");

        string dll = Directory.GetFiles(binRelease, cleanName + ".dll", SearchOption.AllDirectories).FirstOrDefault()
            ?? throw new FileNotFoundException($"Compiled assembly not found for '{cleanName}' under {binRelease}.");

        string manifestGen = FindManifestGen(pluginDir);
        string manifest = Path.Combine(pluginDir, "manifest.exs");
        emit($"[build] manifest -> {manifest}");
        RunProcess(
            dotnetPath,
            $"run --project \"{manifestGen}\" -- \"{dll}\" \"{manifest}\" --type native --build {buildStamp}",
            pluginDir,
            emit);

        return staged;
    }

    private static bool IsPublishedBinary(string path, string cleanName)
    {
        string normalized = path.Replace('\\', '/');
        if (!normalized.Contains("/publish/")) return false;

        string file = Path.GetFileName(path);
        return file == cleanName || file == cleanName + ".exe";
    }

    /// <summary>
    /// Finds a plugin's project file. Newer plugins keep it under <c>src/</c>; older ones at the plugin root.
    /// </summary>
    private static string? FindPluginCsproj(string pluginDir, string cleanName)
    {
        string inSrc = Path.Combine(pluginDir, "src", cleanName + ".csproj");
        if (File.Exists(inSrc)) return inSrc;

        string atRoot = Path.Combine(pluginDir, cleanName + ".csproj");
        if (File.Exists(atRoot)) return atRoot;

        return Directory.EnumerateFiles(pluginDir, "*.csproj", SearchOption.AllDirectories)
            .FirstOrDefault(path => !IsBuildPath(path));
    }

    private static bool IsBuildPath(string path)
    {
        string normalized = path.Replace('\\', '/');
        return normalized.Contains("/bin/") || normalized.Contains("/obj/");
    }

    /// <summary>
    /// Short content hash of a plugin's sources (<c>.cs</c>/<c>.csproj</c>). Used as SemVer build
    /// metadata (<c>1.0.0+ab12cd34</c>) and to tell whether a local plugin changed since its last build.
    /// </summary>
    public static string ComputeSourceFingerprint(string pluginDir)
    {
        var files = Directory.EnumerateFiles(pluginDir, "*.cs", SearchOption.AllDirectories)
            .Concat(Directory.EnumerateFiles(pluginDir, "*.csproj", SearchOption.AllDirectories))
            .Where(path => !IsBuildPath(path))
            .OrderBy(path => path, StringComparer.Ordinal)
            .ToList();

        var content = new StringBuilder();
        foreach (string file in files)
        {
            content.Append(Path.GetRelativePath(pluginDir, file)).Append('\n');
            content.Append(File.ReadAllText(file)).Append('\n');
        }

        using var sha = System.Security.Cryptography.SHA256.Create();
        byte[] hash = sha.ComputeHash(Encoding.UTF8.GetBytes(content.ToString()));
        return BitConverter.ToString(hash).Replace("-", "").Substring(0, 8).ToLowerInvariant();
    }

    /// <summary>
    /// Local per-plugin build counter, stored in <c>.buildcount</c> and incremented on every build.
    /// With the fingerprint it makes each build identifiable: <c>1.0.0+42.f9ac5087</c>.
    /// </summary>
    private static int PeekBuildNumber(string pluginDir)
    {
        string path = Path.Combine(pluginDir, ".buildcount");

        if (File.Exists(path) && int.TryParse(File.ReadAllText(path).Trim(), out int current))
        {
            return current + 1;
        }

        return 1;
    }

    private static void CommitBuildNumber(string pluginDir, int buildNumber)
    {
        File.WriteAllText(Path.Combine(pluginDir, ".buildcount"), buildNumber.ToString());
    }

    /// <summary>Reads the <c>version</c> field from a plugin's generated <c>manifest.exs</c>.</summary>
    public static string? ReadManifestVersion(string pluginDir)
    {
        string manifestPath = Path.Combine(pluginDir, "manifest.exs");
        if (!File.Exists(manifestPath)) return null;

        var match = System.Text.RegularExpressions.Regex.Match(
            File.ReadAllText(manifestPath), """version:\s*([^\s,]+)""");

        return match.Success ? match.Groups[1].Value.Trim('"') : null;
    }

    private static string? FindFile(string root, string fileName)
    {
        return Directory.GetFiles(root, fileName, SearchOption.AllDirectories).FirstOrDefault();
    }

    private static string FindManifestGen(string startDir)
    {
        string? dir = startDir;
        for (int i = 0; i < 12 && dir != null; i++)
        {
            string candidate = Path.Combine(dir, "sdk", "csharp", "Exoforge.ManifestGen");
            if (Directory.Exists(candidate)) return candidate;

            candidate = Path.Combine(dir, "csharp", "Exoforge.ManifestGen");
            if (Directory.Exists(candidate)) return candidate;

            dir = Directory.GetParent(dir)?.FullName;
        }

        throw new DirectoryNotFoundException(
            "Could not locate the Exoforge repo (sdk/csharp/Exoforge.ManifestGen) above the workspace. " +
            "Native builds need it to generate manifest.exs.");
    }

    /// <summary>How long a single build step may run before it is killed.</summary>
    private static readonly TimeSpan ProcessTimeout = TimeSpan.FromMinutes(10);

    private static void RunProcess(string fileName, string arguments, string workingDirectory, Action<string> emit)
    {
        var psi = new ProcessStartInfo(fileName, arguments)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            WorkingDirectory = workingDirectory
        };

        using var proc = new Process { StartInfo = psi };
        var output = new StringBuilder();

        proc.OutputDataReceived += (_, e) => Append(e.Data);
        proc.ErrorDataReceived += (_, e) => Append(e.Data);

        void Append(string? line)
        {
            if (line == null) return;
            output.AppendLine(line);
            emit(line);
        }

        try
        {
            proc.Start();
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException(
                $"Could not start '{fileName}'. If the .NET SDK is installed, set the dotnet path in " +
                $"Exoforge Settings so it can be found outside your shell.\n{ex.Message}", ex);
        }

        proc.BeginOutputReadLine();
        proc.BeginErrorReadLine();

        // A hung `dotnet publish` would otherwise hang the CLI or the Unity editor with no way out.
        if (!proc.WaitForExit((int)ProcessTimeout.TotalMilliseconds))
        {
            // netstandard2.1 has no Kill(entireProcessTree: true); the direct child is what matters.
            try { proc.Kill(); } catch { /* best effort */ }

            throw new InvalidOperationException(
                $"{fileName} did not finish within {ProcessTimeout.TotalMinutes:0} minutes and was stopped.\n{output}");
        }

        // Parameterless WaitForExit drains the async readers; without it the tail of the output is lost.
        proc.WaitForExit();

        if (proc.ExitCode != 0)
        {
            throw new InvalidOperationException($"{fileName} exited with code {proc.ExitCode}.\n{output}");
        }
    }

    /// <summary>
    /// Resolves the dotnet CLI. Unity (a GUI app) usually launches without the user's shell PATH, so
    /// a bare <c>dotnet</c> fails even when the SDK is installed. An explicit override wins; otherwise
    /// probe PATH, the login shell, and the usual install locations.
    /// </summary>
    private static readonly Dictionary<string, string> DotnetPathCache = new();

    public static string ResolveDotnetPath(string? configured)
    {
        string key = configured ?? "";

        lock (DotnetPathCache)
        {
            if (DotnetPathCache.TryGetValue(key, out var cached)) return cached;
        }

        string candidate = string.IsNullOrWhiteSpace(configured) ? "dotnet" : configured.Trim();

        if (!IsBareCommand(candidate))
        {
            return candidate;
        }

        // The login-shell probe spawns a shell; cache the result so repeated builds are fast.
        string resolved = FindOnPath(candidate)
            ?? FindViaLoginShell()
            ?? FindInCommonLocations()
            ?? candidate;

        lock (DotnetPathCache)
        {
            DotnetPathCache[key] = resolved;
        }

        return resolved;
    }

    private static bool IsBareCommand(string value) =>
        !Path.IsPathRooted(value) && !value.Contains('/') && !value.Contains('\\');

    private static string? FindOnPath(string command)
    {
        string? path = Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrEmpty(path)) return null;

        bool windows = RuntimeInformation.IsOSPlatform(OSPlatform.Windows);

        foreach (string raw in path.Split(Path.PathSeparator))
        {
            // Windows PATH entries are sometimes quoted.
            string dir = raw.Trim().Trim('"');
            if (dir.Length == 0) continue;

            string full = Path.Combine(dir, command);
            if (File.Exists(full)) return full;

            if (windows && File.Exists(full + ".exe")) return full + ".exe";
        }

        return null;
    }

    private static string? FindViaLoginShell()
    {
        // Windows has no POSIX login shell; PATH + Program Files cover it.
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows)) return null;

        try
        {
            string shell = Environment.GetEnvironmentVariable("SHELL") ?? "/bin/sh";
            var psi = new ProcessStartInfo(shell, "-lc \"command -v dotnet\"")
            {
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                RedirectStandardInput = true,
                UseShellExecute = false
            };

            using var proc = Process.Start(psi);
            if (proc == null) return null;

            proc.StandardInput.Close();

            var read = proc.StandardOutput.ReadToEndAsync();
            if (!proc.WaitForExit(5000))
            {
                try { proc.Kill(); } catch { /* best effort */ }
                return null;
            }

            string output = read.GetAwaiter().GetResult();
            if (proc.ExitCode != 0) return null;

            // Login profiles can print banners; the resolved path is the last non-empty line.
            string? resolved = output
                .Split('\n')
                .Select(line => line.Trim())
                .LastOrDefault(line => line.Length > 0);

            return resolved != null && File.Exists(resolved) ? resolved : null;
        }
        catch
        {
            return null;
        }
    }

    private static string? FindInCommonLocations()
    {
        bool windows = RuntimeInformation.IsOSPlatform(OSPlatform.Windows);
        string exe = windows ? "dotnet.exe" : "dotnet";
        string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

        var candidates = new List<string>();

        string? dotnetRoot = Environment.GetEnvironmentVariable("DOTNET_ROOT");
        if (!string.IsNullOrWhiteSpace(dotnetRoot)) candidates.Add(Path.Combine(dotnetRoot, exe));

        if (windows)
        {
            candidates.Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "dotnet", exe));
            candidates.Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "dotnet", exe));
            candidates.Add(Path.Combine(home, "AppData", "Local", "Microsoft", "dotnet", exe));
            candidates.Add(Path.Combine(home, ".dotnet", exe));
        }
        else
        {
            // macOS official installer, then Homebrew (Apple Silicon / Intel), then Linux distros.
            candidates.Add("/usr/local/share/dotnet/dotnet");
            candidates.Add("/usr/share/dotnet/dotnet");
            candidates.Add("/usr/lib/dotnet/dotnet");
            candidates.Add("/opt/dotnet/dotnet");
            candidates.Add("/snap/bin/dotnet");
            candidates.Add("/opt/homebrew/bin/dotnet");
            candidates.Add("/usr/local/bin/dotnet");
            candidates.Add(Path.Combine(home, ".dotnet", "dotnet"));
            candidates.Add(Path.Combine(home, ".local", "share", "mise", "shims", "dotnet"));
            candidates.Add(Path.Combine(home, ".asdf", "shims", "dotnet"));
        }

        foreach (string candidate in candidates)
        {
            if (!string.IsNullOrWhiteSpace(candidate) && File.Exists(candidate)) return candidate;
        }

        return null;
    }

    private static string HostRuntimeIdentifier()
    {
        string os = RuntimeInformation.IsOSPlatform(OSPlatform.Windows) ? "win"
            : RuntimeInformation.IsOSPlatform(OSPlatform.OSX) ? "osx"
            : "linux";

        string arch = RuntimeInformation.ProcessArchitecture switch
        {
            Architecture.X64 => "x64",
            Architecture.X86 => "x86",
            Architecture.Arm64 => "arm64",
            Architecture.Arm => "arm",
            _ => "x64"
        };

        return os + "-" + arch;
    }

    /// <summary>Turns any user-supplied name into the lower_snake_case id Exoforge uses.</summary>
    public static string NormalizePluginName(string pluginName)
    {
        return pluginName.Trim().ToLowerInvariant().Replace("-", "_").Replace(" ", "_");
    }

    [DllImport("libc", SetLastError = true)]
    private static extern int chmod(string pathname, uint mode);

    private static void MakeExecutable(string path)
    {
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows)) return;

        try
        {
            // 0755
            _ = chmod(path, Convert.ToUInt32("755", 8));
        }
        catch
        {
            // best effort
        }
    }
}

/// <summary>One log line a plugin emitted, as served by <c>plugin_manager.logs</c>.</summary>
public sealed class PluginLogLine
{
    public PluginLogLine(long at, string levelName, string message)
    {
        At = at;
        LevelName = levelName;
        Message = message;
    }

    /// <summary>Unix milliseconds, as recorded by the cluster.</summary>
    public long At { get; }

    /// <summary>debug | info | warning | error.</summary>
    public string LevelName { get; }

    public string Message { get; }

    /// <summary>Local time for display.</summary>
    public DateTime LocalTime => DateTimeOffset.FromUnixTimeMilliseconds(At).LocalDateTime;
}

/// <summary>
/// Whether the cluster actually has a plugin after a deploy, and at which version.
///
/// A plain class rather than a record: this library targets netstandard2.1 so Unity can consume it,
/// and a record would need an IsExternalInit polyfill that clashes with the one Unity provides.
/// </summary>
public sealed class PluginDeploymentStatus
{
    public PluginDeploymentStatus(bool isDeployed, string? version, string? type, string detail)
    {
        IsDeployed = isDeployed;
        Version = version;
        Type = type;
        Detail = detail;
    }

    public bool IsDeployed { get; }
    public string? Version { get; }
    public string? Type { get; }

    /// <summary>Human-readable outcome, e.g. <c>loaded</c> or why it is not.</summary>
    public string Detail { get; }

    /// <summary>True when the plugin is loaded and at the expected version.</summary>
    public bool IsHealthy => IsDeployed && Detail == "loaded";
}

/// <summary>Result of <see cref="ExoDeployer.BuildPlugin"/>.</summary>
public class ExoPluginBuild
{
    public ExoPluginBuild(string name, string pluginType, string binaryPath, string manifestPath, string output)
    {
        Name = name;
        PluginType = pluginType;
        BinaryPath = binaryPath;
        ManifestPath = manifestPath;
        Output = output;
    }

    public string Name { get; }
    public string PluginType { get; }
    public string BinaryPath { get; }
    public string ManifestPath { get; }
    public string Output { get; }
}
