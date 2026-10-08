using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
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

        // The HTTP base is configuration. ExoClient no longer derives it from the WebSocket port,
        // which was wrong for any non-default gateway.
        if (!string.IsNullOrEmpty(env.HttpUrl))
        {
            client.HttpBaseUri = new Uri(env.HttpUrl);
        }

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

        // One compiled kind: the native binary the runner spawns. A runtime that is not a process -
        // a WASM reactor, say - adds a branch here and a runner in the kernel.
        string pluginType = "native";
        string binaryPath = StagedBinary(pluginDir, cleanName);

        if (!File.Exists(binaryPath))
        {
            throw new FileNotFoundException(
                $"No plugin binary found for '{cleanName}' (expected {cleanName}). Build it first.");
        }

        byte[] binaryBytes = await File.ReadAllBytesAsync(binaryPath, cancellationToken).ConfigureAwait(false);
        string binaryBase64 = Convert.ToBase64String(binaryBytes);

        string? manifestContent = null;
        string manifestPath = Path.Combine(pluginDir, "manifest.json");
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
        Action<string>? emit = null,
        CancellationToken cancellationToken = default)
    {
        string cleanName = NormalizePluginName(pluginName);
        string pluginDir = Path.Combine(_workspace.PluginsPath, cleanName);
        string output = Path.Combine(pluginDir, "src", "Generated", "PluginServices.g.cs");
        string exportJson;

        try
        {
            exportJson = await GetContractsExportJsonAsync(existingClient: existingClient, cancellationToken: cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex) when (existingClient == null)
        {
            // No cluster to ask. Every plugin that has been built still has its contracts on disk,
            // which is the point: stubs for a plugin that is built but not deployed. Anything that was
            // neither built nor deployed simply will not appear.
            emit?.Invoke($"[stubs] no cluster ({ex.Message}) - generating from local contracts only");
            exportJson = "{\"export\":{\"plugins\":[]}}";
        }

        string merged = MergeLocalContracts(exportJson);
        var services = ReadManifestDependencies(pluginDir);
        var missing = MissingServices(merged, services);

        if (missing.Count > 0)
        {
            throw new InvalidOperationException(
                $"No contracts for: {string.Join(", ", missing)}. Nothing was written — {output} still " +
                "holds the last stubs that were generated. Start the cluster, or build the plugin that " +
                "provides them.");
        }

        ExoCodeGenerator.GeneratePluginStubsToFile(merged, output, services: services, pluginId: cleanName);
        return output;
    }

    /// <summary>
    /// The declared dependencies the export has no contract for.
    ///
    /// A caller checks this before writing stubs, because generating from an export that is missing
    /// them produces a file with fewer stubs than the one it replaces — which is worse than doing
    /// nothing, since the existing file still compiles and still calls what it called.
    /// </summary>
    public static IReadOnlyList<string> MissingServices(string exportJson, IEnumerable<string>? services)
    {
        var wanted = services?.ToList();
        if (wanted is null || wanted.Count == 0) return Array.Empty<string>();

        var available = new HashSet<string>(StringComparer.Ordinal);

        try
        {
            if (JsonNode.Parse(exportJson)?["export"]?["plugins"] is JsonArray plugins)
            {
                foreach (JsonNode? plugin in plugins)
                {
                    if (plugin?["services"] is not JsonArray declared) continue;

                    foreach (JsonNode? service in declared)
                    {
                        if (service?["name"]?.GetValue<string>() is { Length: > 0 } name) available.Add(name);
                    }
                }
            }
        }
        catch (Exception ex) when (ex is JsonException or InvalidOperationException)
        {
            // An export that cannot be read is not this check's problem to report.
            return Array.Empty<string>();
        }

        return wanted.Where(name => !available.Contains(name)).ToList();
    }

    /// <summary>
    /// The cluster's contract export with every locally built plugin's contracts laid over it.
    ///
    /// A plugin that is built but not deployed has no entry on the cluster, so stubs generated from the
    /// export alone leave the caller with nothing to call. Each plugin's generator writes its contracts
    /// as JSON beside the manifest for exactly this. Local wins where both have an entry, because what
    /// the developer is editing is the local one.
    /// </summary>
    public string MergeLocalContracts(string clusterJson)
    {
        JsonNode? parsed;

        try
        {
            parsed = JsonNode.Parse(clusterJson);
        }
        catch (JsonException)
        {
            return clusterJson;
        }

        if (parsed is not JsonObject root || root["export"] is not JsonObject export) return clusterJson;
        if (export["plugins"] is not JsonArray plugins) return clusterJson;

        bool changed = false;

        foreach (var (id, local) in LocalContracts())
        {
            JsonNode? existing = plugins.FirstOrDefault(p => string.Equals(PluginId(p), id, StringComparison.Ordinal));
            int index = existing is null ? -1 : plugins.IndexOf(existing);

            // Cloned: a parsed node belongs to the document it came from, and assigning it into a
            // second one throws "the node already has a parent".
            JsonNode detached = local.DeepClone();

            if (index >= 0) plugins[index] = detached;
            else plugins.Add(detached);

            changed = true;
        }

        return changed ? root.ToJsonString() : clusterJson;
    }

    /// <summary>
    /// Every workspace plugin's generated contracts, by plugin id. A plugin that has not been built has
    /// no file and is simply absent — the same as it being absent from the cluster.
    /// </summary>
    private IEnumerable<(string Id, JsonNode Node)> LocalContracts()
    {
        if (!Directory.Exists(_workspace.PluginsPath)) yield break;

        var found = new List<(string Id, JsonNode Node)>();

        foreach (string dir in Directory.GetDirectories(_workspace.PluginsPath).OrderBy(d => d, StringComparer.Ordinal))
        {
            string path = Path.Combine(dir, "manifest.json");
            if (!File.Exists(path)) continue;

            try
            {
                if (JsonNode.Parse(ToExport(File.ReadAllText(path)))?["export"]?["plugins"] is not JsonArray localPlugins) continue;

                foreach (JsonNode? plugin in localPlugins)
                {
                    if (plugin is not null && PluginId(plugin) is { Length: > 0 } id) found.Add((id, plugin));
                }
            }
            catch (Exception ex) when (ex is JsonException or InvalidOperationException)
            {
                // A half-written file is not worth failing a build over: the plugin is treated as one
                // with no local contract, which is what it was before the file existed.
            }
        }

        foreach (var entry in found) yield return entry;
    }

    /// <summary>
    /// A plugin's manifest as the contract export the client generator reads.
    ///
    /// The manifest is the file a plugin has; the export is the shape the generator wants, and the
    /// shape the cluster answers with. Converting on read rather than writing a second file is the
    /// point of the manifest being JSON: one artifact per plugin, not two that mean the same thing.
    /// </summary>
    private static string ToExport(string manifestJson)
    {
        JsonNode? parsed;

        try
        {
            parsed = JsonNode.Parse(manifestJson);
        }
        catch (JsonException)
        {
            return EmptyExport;
        }

        if (parsed is not JsonObject manifest) return EmptyExport;

        var plugin = new JsonObject
        {
            ["id"] = manifest["id"]?.DeepClone(),
            // The export carries a name beside the id; the manifest has only the id, deliberately.
            ["name"] = manifest["id"]?.DeepClone(),
            ["version"] = manifest["version"]?.DeepClone(),
            ["type"] = manifest["type"]?.DeepClone(),
            ["entry_point"] = manifest["entry_point"]?.DeepClone(),
            ["provides"] = manifest["provides"]?.DeepClone(),
            ["dependencies"] = manifest["dependencies"]?.DeepClone(),
            ["services"] = manifest["services"]?.DeepClone()
        };

        // A resource's C# record is `record` in the manifest, because `type` is an atom everywhere
        // else in it and one field meaning something else would have cost a path-aware reader. The
        // export has no such constraint and calls it `type`.
        if (plugin["services"] is JsonArray services)
        {
            foreach (JsonNode? service in services)
            {
                if (service?["resources"] is not JsonArray resources) continue;

                foreach (JsonNode? resource in resources)
                {
                    if (resource is not JsonObject entry || entry["record"] is not { } record) continue;

                    entry.Remove("record");
                    entry["type"] = record.DeepClone();
                }
            }
        }

        var export = new JsonObject
        {
            ["export"] = new JsonObject { ["plugins"] = new JsonArray(plugin) }
        };

        return export.ToJsonString();
    }

    private const string EmptyExport = "{\"export\":{\"plugins\":[]}}";

    private static string? PluginId(JsonNode plugin)
    {
        try
        {
            return plugin["id"]?.GetValue<string>();
        }
        catch (InvalidOperationException)
        {
            return null;
        }
    }

    /// <summary>
    /// Reads service dependencies from a plugin's generated <c>manifest.json</c>, so stubs are only
    /// generated for the contracts it actually calls. Returns null when there is no manifest yet, or
    /// when it was built before the JSON twin existed — in which case every service is offered rather
    /// than none.
    /// </summary>
    public static IReadOnlyList<string>? ReadManifestDependencies(string pluginDir)
    {
        string path = Path.Combine(pluginDir, "manifest.json");
        if (!File.Exists(path)) return null;

        try
        {
            if (JsonNode.Parse(File.ReadAllText(path))?["dependencies"] is not JsonArray declared) return null;

            var dependencies = new List<string>();

            foreach (JsonNode? dependency in declared)
            {
                if (dependency?.GetValue<string>() is { Length: > 0 } name && !dependencies.Contains(name))
                {
                    dependencies.Add(name);
                }
            }

            return dependencies.Count == 0 ? null : dependencies;
        }
        catch (Exception ex) when (ex is JsonException or InvalidOperationException)
        {
            return null;
        }
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

            string rawJson = MergeLocalContracts(exportResult.GetRawText());
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
    /// <item>otherwise → <c>dotnet publish</c> a NativeAOT binary and regenerate <c>manifest.json</c>.</item>
    /// </list>
    /// The result is staged next to <c>manifest.json</c>, ready for <see cref="UploadPluginAsync"/>.
    /// </summary>
    public ExoPluginBuild BuildPlugin(
        string pluginName,
        string? rid = null,
        string dotnetPath = "dotnet",
        Action<string>? log = null)
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

        // One compiled kind. The `build.sh` hook was how a WASM guest was built; a runtime that needs
        // its own toolchain adds that branch back alongside its runner.
        string pluginType = "native";
        string binaryPath = PublishNative(csproj ?? throw new FileNotFoundException($"No .csproj found for '{cleanName}'."), pluginDir, cleanName, rid, dotnet, buildStamp, Emit);

        CommitBuildNumber(pluginDir, buildNumber);

        string manifestPath = Path.Combine(pluginDir, "manifest.json");
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
        string manifest = Path.Combine(pluginDir, "manifest.json");

        // The manifest is written by Exoforge.Plugin.Generator during this same compile, so the
        // version stamped into it always describes the binary just produced. There is no second pass
        // over the compiled assembly, which is what used to let a stale Release tree win.
        // Two passes, and only because of the JSON context.
        //
        // A plugin's records need a JsonSerializerContext, and nothing can generate one *into* the
        // compile that needs it: a source generator's output is invisible to the System.Text.Json
        // generator, which is what fills the context's members in. So the generator writes the context
        // as a real file - the manifest's trick - and the compile after that one has it. A cheap build
        // first, then the publish that actually ships.
        //
        // One pass would leave the plugin building and failing at runtime on the first record it tried
        // to send, which is the sort of thing that gets blamed on the SDK.
        emit("[build] dotnet build (writes the JSON context)");
        RunProcess(
            dotnetPath,
            $"build \"{RelativeTo(pluginDir, csproj)}\" -c Release " +
            $"-p:ExoforgePluginType=native -p:ExoforgeBuildStamp={buildStamp} " +
            $"-p:ExoforgeManifestPath=\"{manifest}\"",
            pluginDir,
            emit);

        emit($"[build] dotnet publish -c Release -r {targetRid}");
        RunProcess(
            dotnetPath,
            $"publish \"{RelativeTo(pluginDir, csproj)}\" -c Release -r {targetRid} " +
            $"-p:ExoforgePluginType=native -p:ExoforgeBuildStamp={buildStamp} " +
            // Absolute: a relative path is resolved by whoever consumes it, and the compiler runs
            // from its own directory rather than this one.
            $"-p:ExoforgeManifestPath=\"{manifest}\"",
            pluginDir,
            emit);

        // The project may sit at the plugin root or under src/, and a plugin that has moved between
        // the two leaves both trees behind. Search every Release tree and take the newest match:
        // picking a tree first and searching inside it means one stale directory wins for all of its
        // contents, and the binary staged is then not the one that was just built - silently,
        // because a binary is still produced.
        string[] releaseTrees = Directory.GetDirectories(pluginDir, "Release", SearchOption.AllDirectories)
            .Where(dir => string.Equals(Path.GetFileName(Path.GetDirectoryName(dir) ?? ""), "bin", StringComparison.OrdinalIgnoreCase))
            .ToArray();

        if (releaseTrees.Length == 0)
        {
            throw new DirectoryNotFoundException($"Build output (bin/Release) not found under {pluginDir}.");
        }

        // Stage the published native binary where the runner and deployer expect it.
        string published = releaseTrees
            .SelectMany(tree => Directory.GetFiles(tree, cleanName + "*", SearchOption.AllDirectories))
            .Where(path => IsPublishedBinary(path, cleanName))
            .OrderByDescending(File.GetLastWriteTimeUtc)
            .FirstOrDefault()
            ?? throw new FileNotFoundException($"Published native binary not found for '{cleanName}' under {pluginDir}.");

        // Staged under a dot folder: the plugin directory holds source, and a multi-megabyte binary
        // named after the plugin sitting next to it is noise.
        string stagedDir = Path.Combine(pluginDir, ".exoforge");
        Directory.CreateDirectory(stagedDir);

        string staged = Path.Combine(stagedDir, cleanName);
        File.Copy(published, staged, overwrite: true);
        MakeExecutable(staged);
        emit($"[build] staged native binary -> {staged}");

        if (!File.Exists(manifest))
        {
            throw new FileNotFoundException(
                $"No manifest was generated for '{cleanName}' at {manifest}. " +
                "Does the plugin project reference Exoforge.Plugin.Generator?");
        }

        emit($"[build] manifest -> {manifest}");

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
    /// <summary>
    /// Where a native binary was staged: <c>.exoforge/</c> under the plugin, with the plugin root as
    /// the older layout. Returns the staged path when neither exists, so a "not built" message names
    /// where a build would put it.
    /// </summary>
    public static string StagedBinary(string pluginDir, string cleanName)
    {
        string staged = Path.Combine(pluginDir, ".exoforge", cleanName);
        string legacy = Path.Combine(pluginDir, cleanName);

        // Windows builds append .exe; native deploys are usually cross-built for a Linux RID.
        foreach (string candidate in new[] { staged, legacy })
        {
            if (File.Exists(candidate)) return candidate;
            if (File.Exists(candidate + ".exe")) return candidate + ".exe";
        }

        return staged;
    }

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

    /// <summary>Reads the <c>version</c> field from a plugin's generated <c>manifest.json</c>.</summary>
    public static string? ReadManifestVersion(string pluginDir)
    {
        string manifestPath = Path.Combine(pluginDir, "manifest.json");
        if (!File.Exists(manifestPath)) return null;

        try
        {
            return JsonNode.Parse(File.ReadAllText(manifestPath))?["version"]?.GetValue<string>();
        }
        catch (Exception ex) when (ex is JsonException or InvalidOperationException)
        {
            return null;
        }
    }

    private static string? FindFile(string root, string fileName)
    {
        return Directory.GetFiles(root, fileName, SearchOption.AllDirectories).FirstOrDefault();
    }

    /// <summary>
    /// Re-expresses <paramref name="path"/> relative to <paramref name="baseDir"/>, when that is
    /// meaningful.
    ///
    /// Both must be written the same way: mixing an absolute path with a relative base produces a
    /// climb out of the tree that resolves against the wrong directory in the child process. In that
    /// case the absolute path is kept, which is always correct.
    ///
    /// The test is deliberately "does the string start with a separator" rather than
    /// <see cref="Path.IsPathRooted"/> — Unity's Mono reports a bare relative path as rooted, so
    /// that check says nothing.
    /// </summary>
    private static string RelativeTo(string baseDir, string path)
    {
        if (LooksAbsolute(baseDir) != LooksAbsolute(path))
        {
            return path;
        }

        try
        {
            string relative = Path.GetRelativePath(baseDir, path);

            // Across trees the relative form has to climb to the root first, so it is longer than
            // the absolute path — which is exactly the signal to keep the absolute one. This is not
            // hypothetical: macOS reports /tmp and /private/tmp for the same directory, so the two
            // paths share no common prefix even though they are the same place.
            return relative.Length <= path.Length ? relative : path;
        }
        catch (ArgumentException)
        {
            return path;
        }
    }

    private static bool LooksAbsolute(string path) =>
        path.Length > 0 &&
        (path[0] == Path.DirectorySeparatorChar ||
         path[0] == Path.AltDirectorySeparatorChar ||
         (path.Length > 1 && path[1] == Path.VolumeSeparatorChar));

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
