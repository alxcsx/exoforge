using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
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

        string targetEnv = environmentName ?? _workspace.Config.DefaultEnvironment;

        if (!string.IsNullOrEmpty(env.Token))
        {
            bool authenticated = await TryAuthenticateAsync(client, env.Token, cancellationToken).ConfigureAwait(false);

            // A saved session is a pair: an access token that lasts an hour and the refresh token
            // beside it. The hour having passed is ordinary, not a failed login.
            if (!authenticated &&
                !string.IsNullOrEmpty(env.RefreshToken) &&
                await RefreshCliSessionAsync(client, env, targetEnv, cancellationToken).ConfigureAwait(false))
            {
                authenticated = await TryAuthenticateAsync(client, env.Token, cancellationToken).ConfigureAwait(false);
            }

            if (!authenticated)
            {
                throw new InvalidOperationException(
                    "Failed to authenticate with cluster: the saved session was refused. " +
                    "Run `exo connect --email <email> --password <password> --save` to renew it.");
            }
        }

        // Every command's calls renew the pair the same way, through the client's one gate.
        client.RefreshTokensAsync = ct => RefreshCliSessionAsync(client, env, targetEnv, ct);

        return client;
    }

    /// <summary>
    /// Whether the socket accepted <paramref name="token"/>. The client raises a refusal as an
    /// exception rather than returning an unsuccessful result, and a refusal is what a caller wants
    /// to branch on here.
    /// </summary>
    private static async Task<bool> TryAuthenticateAsync(ExoClient client, string token, CancellationToken cancellationToken)
    {
        try
        {
            await client.AuthenticateAsync(token, cancellationToken: cancellationToken).ConfigureAwait(false);
            return true;
        }
        catch (ExoActionException)
        {
            return false;
        }
    }

    /// <summary>
    /// The device a CLI session belongs to: one per machine and environment, so connecting again
    /// replaces that session (the server rotates a device's tokens) instead of adding another pair.
    /// Stable across runs, because it is derived rather than stored.
    /// </summary>
    public static string CliDeviceId(string environmentName)
    {
        using var sha = SHA256.Create();
        byte[] hash = sha.ComputeHash(Encoding.UTF8.GetBytes($"{Environment.MachineName}:{environmentName}"));
        // A device id is an opaque key, not a secret: eight bytes identify the machine without
        // carrying the machine name to the server.
        return "cli:" + BitConverter.ToString(hash, 0, 8).Replace("-", "").ToLowerInvariant();
    }

    /// <summary>
    /// Exchanges the saved refresh token for a new pair and writes the rotated pair back, so the
    /// next command finds the one that works. Single-use rotation means the old token is spent as
    /// soon as this returns.
    /// </summary>
    private async Task<bool> RefreshCliSessionAsync(
        ExoClient client,
        ExoEnvironmentConfig env,
        string environmentName,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrEmpty(env.RefreshToken))
        {
            return false;
        }

        JsonElement result;

        try
        {
            result = await client.SendActionAsync<JsonElement>(
                "auth",
                "refresh",
                new { token = env.RefreshToken },
                ExoTransportPreference.Http,
                cancellationToken: cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception)
        {
            return false;
        }

        string token = result.ValueKind == JsonValueKind.Object && result.TryGetProperty("token", out var tokenProp)
            ? tokenProp.GetString() ?? ""
            : "";

        string rotated = result.ValueKind == JsonValueKind.Object && result.TryGetProperty("refresh_token", out var rotatedProp)
            ? rotatedProp.GetString() ?? ""
            : "";

        if (string.IsNullOrEmpty(token) || string.IsNullOrEmpty(rotated))
        {
            return false;
        }

        env.Token = token;
        env.RefreshToken = rotated;
        client.UseToken(token);

        if (client.IsConnected)
        {
            try
            {
                await client.AuthenticateAsync(token, cancellationToken: cancellationToken).ConfigureAwait(false);
            }
            catch (Exception)
            {
                // The socket was opened with the previous token; the calls that follow go over HTTP
                // with the new one, and the next command dials a fresh socket.
            }
        }

        // Only a session the workspace already keeps is written back: a connect without --save
        // leaves the workspace alone.
        if (_workspace.Config.Environments.ContainsKey(environmentName))
        {
            _workspace.Save();
        }

        return true;
    }

    public async Task<string> UploadExtensionAsync(
        string extensionName,
        string? environmentName = null,
        ExoClient? existingClient = null,
        CancellationToken cancellationToken = default)
    {
        string cleanName = extensionName.Trim().ToLowerInvariant().Replace("-", "_");
        string extensionDir = Path.Combine(_workspace.ExtensionsPath, cleanName);

        // One compiled kind: the native binary the runner spawns. A runtime that is not a process -
        // one hosted in-process, say - adds a branch here and a runner in the kernel.
        string extensionType = "native";
        string binaryPath = StagedBinary(extensionDir, cleanName);

        if (!File.Exists(binaryPath))
        {
            throw new FileNotFoundException(
                $"No extension binary found for '{cleanName}' (expected {cleanName}). Build it first.");
        }

        byte[] binaryBytes = await File.ReadAllBytesAsync(binaryPath, cancellationToken).ConfigureAwait(false);
        string binaryBase64 = Convert.ToBase64String(binaryBytes);

        string? manifestContent = null;
        string manifestPath = Path.Combine(extensionDir, "manifest.json");
        if (File.Exists(manifestPath))
        {
            manifestContent = await File.ReadAllTextAsync(manifestPath, cancellationToken).ConfigureAwait(false);
        }

        Dictionary<string, object>? filesPayload = null;
        string assetsDir = Path.Combine(extensionDir, "assets");
        if (Directory.Exists(assetsDir))
        {
            filesPayload = new Dictionary<string, object>();
            foreach (string filePath in Directory.GetFiles(assetsDir, "*", SearchOption.AllDirectories))
            {
                string relPath = Path.GetRelativePath(extensionDir, filePath).Replace('\\', '/');
                byte[] fileBytes = await File.ReadAllBytesAsync(filePath, cancellationToken).ConfigureAwait(false);
                filesPayload[relPath] = new
                {
                    encoding = "base64",
                    content = Convert.ToBase64String(fileBytes)
                };
            }
        }

        var client = existingClient ?? await CreateConnectedClientAsync(environmentName, cancellationToken).ConfigureAwait(false);
        try
        {
            var payload = new
            {
                name = cleanName,
                type = extensionType,
                // Named 'binary', not 'wasm_binary': the field carries whatever the runtime produces,
                // and the old name read as a format.
                binary = binaryBase64,
                manifest = manifestContent,
                files = filesPayload
            };

            var result = await client.SendActionAsync<JsonElement>("extension_manager", "upload_extension", payload, ExoTransportPreference.Http, cancellationToken: cancellationToken).ConfigureAwait(false);
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
    /// Whether the cluster actually has an extension after a deploy, and at which version.
    ///
    /// <c>upload_extension</c> returning <c>installed</c> only means the files landed. An extension that
    /// fails to boot afterwards is otherwise invisible until you try to call one of its actions —
    /// which is exactly the wrong moment to find out.
    /// </summary>
    public async Task<ExtensionDeploymentStatus> VerifyExtensionAsync(
        string extensionName,
        string? expectedVersion = null,
        string? environmentName = null,
        ExoClient? existingClient = null,
        CancellationToken cancellationToken = default)
    {
        string cleanName = NormalizeExtensionName(extensionName);
        var client = existingClient ?? await CreateConnectedClientAsync(environmentName, cancellationToken).ConfigureAwait(false);

        try
        {
            JsonElement result;
            try
            {
                result = await client.SendActionAsync<JsonElement>(
                    "extension_manager", "get_extension", new { id = cleanName }, cancellationToken: cancellationToken).ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                return new ExtensionDeploymentStatus(false, null, null, $"cluster does not have '{cleanName}': {ex.Message}");
            }

            string? version = ReadString(result, "extension", "version") ?? ReadString(result, "plugin", "version");
            string? type = ReadString(result, "extension", "type") ?? ReadString(result, "plugin", "type");
            string? status = ReadString(result, "extension", "status") ?? ReadString(result, "plugin", "status");

            if (version == null)
            {
                return new ExtensionDeploymentStatus(false, null, null, $"cluster does not have '{cleanName}'");
            }

            if (status != null && status.StartsWith("crashed", StringComparison.OrdinalIgnoreCase))
            {
                return new ExtensionDeploymentStatus(false, version, type, $"extension crashed on boot: {status}");
            }

            if (expectedVersion != null && !string.Equals(version, expectedVersion, StringComparison.Ordinal))
            {
                return new ExtensionDeploymentStatus(
                    true, version, type,
                    $"cluster is running {version}, but {expectedVersion} was just deployed");
            }

            return new ExtensionDeploymentStatus(true, version, type, "loaded");
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
    /// Re-boots an installed extension from the files already on the cluster. No rebuild, no re-upload.
    /// </summary>
    public async Task<JsonElement> ReloadExtensionAsync(
        string extensionName,
        string? environmentName = null,
        ExoClient? existingClient = null,
        CancellationToken cancellationToken = default)
    {
        string cleanName = NormalizeExtensionName(extensionName);
        var client = existingClient ?? await CreateConnectedClientAsync(environmentName, cancellationToken).ConfigureAwait(false);

        try
        {
            return await client.SendActionAsync<JsonElement>(
                "extension_manager", "reload_extension", new { id = cleanName }, cancellationToken: cancellationToken).ConfigureAwait(false);
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
    /// Recent log lines the extension emitted.
    /// </summary>
    public async Task<List<ExtensionLogLine>> GetExtensionLogsAsync(
        string extensionName,
        int limit = 100,
        string? environmentName = null,
        ExoClient? existingClient = null,
        CancellationToken cancellationToken = default)
    {
        string cleanName = NormalizeExtensionName(extensionName);
        var client = existingClient ?? await CreateConnectedClientAsync(environmentName, cancellationToken).ConfigureAwait(false);

        try
        {
            var result = await client.SendActionAsync<JsonElement>(
                "extension_manager",
                "logs",
                new { id = cleanName, limit },
                cancellationToken: cancellationToken).ConfigureAwait(false);

            var lines = new List<ExtensionLogLine>();

            if (result.ValueKind == JsonValueKind.Object &&
                result.TryGetProperty("lines", out var array) &&
                array.ValueKind == JsonValueKind.Array)
            {
                foreach (var entry in array.EnumerateArray())
                {
                    lines.Add(new ExtensionLogLine(
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

    /// <summary>
    /// Persisted usage for one extension or the whole title: calls by action, wall time, bytes, CPU
    /// and peak RSS. <paramref name="since"/> is Unix seconds; null means everything recorded.
    /// </summary>
    public async Task<ExtensionUsageReport> GetExtensionUsageAsync(
        string? extensionName = null,
        long? since = null,
        string? environmentName = null,
        ExoClient? existingClient = null,
        CancellationToken cancellationToken = default)
    {
        var client = existingClient ?? await CreateConnectedClientAsync(environmentName, cancellationToken).ConfigureAwait(false);

        try
        {
            var payload = new
            {
                plugin_id = extensionName == null ? null : NormalizeExtensionName(extensionName),
                since,
            };

            var result = await client.SendActionAsync<JsonElement>(
                "metering",
                "usage",
                payload,
                cancellationToken: cancellationToken).ConfigureAwait(false);

            return ExtensionUsageReport.Parse(result);
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

    public async Task<string> RemoveExtensionAsync(
        string extensionId,
        string? environmentName = null,
        bool deleteFiles = false,
        ExoClient? existingClient = null,
        CancellationToken cancellationToken = default)
    {
        var client = existingClient ?? await CreateConnectedClientAsync(environmentName, cancellationToken).ConfigureAwait(false);
        try
        {
            var result = await client.SendActionAsync<JsonElement>(
                "extension_manager",
                "remove_extension",
                new { id = extensionId, delete_files = deleteFiles },
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

    /// <summary>Fetches the raw contract export (what <c>extension_manager.export_extension_info</c> returns).</summary>
    public async Task<string> GetContractsExportJsonAsync(
        string? environmentName = null,
        ExoClient? existingClient = null,
        CancellationToken cancellationToken = default)
    {
        var client = existingClient ?? await CreateConnectedClientAsync(environmentName, cancellationToken).ConfigureAwait(false);
        try
        {
            var export = await client.SendActionAsync<JsonElement>(
                "extension_manager", "export_extension_info", null, cancellationToken: cancellationToken).ConfigureAwait(false);
            string raw = export.GetRawText();
            TryCacheContracts(raw);
            return raw;
        }
        finally
        {
            if (existingClient == null)
            {
                client.Dispose();
            }
        }
    }

    public Task<string> GenerateExtensionStubsAsync(
        string extensionName,
        ExoClient? existingClient = null,
        Action<string>? emit = null,
        CancellationToken cancellationToken = default) =>
        GenerateExtensionStubsAsync(extensionName, services: null, existingClient: existingClient, emit: emit, cancellationToken: cancellationToken);

    /// <summary>Fetches the contracts and writes typed stubs into the extension's <c>obj/exoforge</c> folder.</summary>
    public async Task<string> GenerateExtensionStubsAsync(
        string extensionName,
        IEnumerable<string>? services,
        ExoClient? existingClient = null,
        Action<string>? emit = null,
        CancellationToken cancellationToken = default)
    {
        string cleanName = NormalizeExtensionName(extensionName);
        string extensionDir = Path.Combine(_workspace.ExtensionsPath, cleanName);
        string output = StubsPath(extensionDir);
        string exportJson;

        try
        {
            exportJson = await GetContractsExportJsonAsync(existingClient: existingClient, cancellationToken: cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex) when (existingClient == null)
        {
            // No cluster to ask. Try cached cluster export first, then fallback to local contracts only.
            exportJson = LoadCachedOrEmptyContracts();
            emit?.Invoke($"[stubs] no cluster ({ex.Message}) - generating from {(File.Exists(ContractsCachePath) ? "cached" : "local")} contracts");
        }

        string merged = MergeLocalContracts(exportJson);
        var targetServices = services?.ToList();
        if (targetServices == null)
        {
            targetServices = AvailableServices(merged)
                .Where(s => !string.Equals(s, cleanName, StringComparison.OrdinalIgnoreCase))
                .ToList();
        }

        var missing = MissingServices(merged, targetServices);

        if (missing.Count > 0)
        {
            throw new InvalidOperationException(
                $"No contracts for: {string.Join(", ", missing)}. Nothing was written — {output} still " +
                "holds the last stubs that were generated. Start the cluster, or build the extension that " +
                "provides them.");
        }

        ExoCodeGenerator.GeneratePluginStubsToFile(merged, output, services: targetServices, pluginId: cleanName);
        string attrDir = Path.Combine(extensionDir, "obj", "exoforge", "Attributes");
        SyncCompanionAttributes(merged, attrDir, emit);
        return output;
    }

    public static List<string> AvailableServices(string exportJson)
    {
        var available = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        try
        {
            var parsed = JsonNode.Parse(exportJson);
            var exportNode = parsed?["export"] ?? parsed;
            var plugins = exportNode?["plugins"] as JsonArray ?? exportNode?["extensions"] as JsonArray;

            if (plugins != null)
            {
                foreach (JsonNode? plugin in plugins)
                {
                    if (plugin is null) continue;

                    if (PluginId(plugin) is { Length: > 0 } pid) available.Add(pid);
                    if (plugin["provides"] is JsonArray provides)
                    {
                        foreach (var p in provides) if (p?.GetValue<string>() is { Length: > 0 } pv) available.Add(pv);
                    }

                    if (plugin["services"] is JsonArray declared)
                    {
                        foreach (JsonNode? service in declared)
                        {
                            if (service?["name"]?.GetValue<string>() is { Length: > 0 } name) available.Add(name);
                        }
                    }
                }
            }
        }
        catch (Exception ex) when (ex is JsonException or InvalidOperationException)
        {
        }

        return available.ToList();
    }

    /// <summary>
    /// Synchronizes modular companion C# attributes/types from remote cluster export and local extension folders
    /// into the generated attributes folder so the SDK / Unity compiles them.
    /// </summary>
    public int SyncCompanionAttributes(string exportJson, string? targetDir = null, Action<string>? emit = null)
    {
        string destDir = targetDir ?? Path.Combine(Path.GetDirectoryName(_workspace.GeneratedPath)!, "Attributes");
        Directory.CreateDirectory(destDir);
        int written = 0;

        // 1. From remote cluster export JSON
        try
        {
            var parsed = JsonNode.Parse(exportJson);
            var exportNode = parsed?["export"] ?? parsed;
            if (exportNode?["csharp_attributes"] is JsonArray remoteAttrs)
            {
                foreach (var attr in remoteAttrs)
                {
                    if (attr is null) continue;
                    string? filename = attr["filename"]?.GetValue<string>();
                    string? content = attr["content"]?.GetValue<string>();
                    if (string.IsNullOrWhiteSpace(filename) || content is null) continue;

                    string filePath = Path.Combine(destDir, filename);
                    if (!File.Exists(filePath) || File.ReadAllText(filePath) != content)
                    {
                        File.WriteAllText(filePath, content);
                        emit?.Invoke($"[sync] synced remote attribute: {filename}");
                        written++;
                    }
                }
            }
        }
        catch
        {
            // Ignore parse errors from empty/partial export json
        }

        // 2. From local workspace extension folders
        try
        {
            if (Directory.Exists(_workspace.ExtensionsPath))
            {
                var localCsFiles = Directory.GetFiles(_workspace.ExtensionsPath, "*.cs", SearchOption.AllDirectories)
                    .Where(p =>
                    {
                        string dir = Path.GetDirectoryName(p) ?? "";
                        return dir.EndsWith("csharp", StringComparison.OrdinalIgnoreCase) ||
                               dir.EndsWith("unity", StringComparison.OrdinalIgnoreCase);
                    });

                foreach (var file in localCsFiles)
                {
                    string filename = Path.GetFileName(file);
                    string destFile = Path.Combine(destDir, filename);
                    string content = File.ReadAllText(file);

                    if (!File.Exists(destFile) || File.ReadAllText(destFile) != content)
                    {
                        File.WriteAllText(destFile, content);
                        emit?.Invoke($"[sync] synced local attribute: {filename}");
                        written++;
                    }
                }
            }
        }
        catch
        {
            // Ignore local scan errors
        }

        return written;
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
            var root = JsonNode.Parse(exportJson);
            var export = root?["export"] ?? root;
            var plugins = (export?["extensions"] as JsonArray) ?? (export?["plugins"] as JsonArray);
            if (plugins is not null)
            {
                foreach (JsonNode? plugin in plugins)
                {
                    if (plugin is null) continue;

                    if (PluginId(plugin) is { Length: > 0 } pid) available.Add(pid);
                    if (plugin["provides"] is JsonArray provides)
                    {
                        foreach (var p in provides) if (p?.GetValue<string>() is { Length: > 0 } pv) available.Add(pv);
                    }

                    if (plugin["services"] is not JsonArray declared) continue;

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
        JsonArray? plugins = export["plugins"] as JsonArray;
        JsonArray? extensions = export["extensions"] as JsonArray;
        if (plugins is null && extensions is null) return clusterJson;

        bool changed = false;

        foreach (var (id, local) in LocalContracts())
        {
            if (plugins is not null)
            {
                JsonNode? existing = plugins.FirstOrDefault(p => p != null && string.Equals(PluginId(p), id, StringComparison.Ordinal));
                int index = existing is null ? -1 : plugins.IndexOf(existing);

                JsonNode detached = local.DeepClone();
                if (index >= 0) plugins[index] = detached;
                else plugins.Add(detached);
                changed = true;
            }

            if (extensions is not null)
            {
                JsonNode? existing = extensions.FirstOrDefault(p => p != null && string.Equals(PluginId(p), id, StringComparison.Ordinal));
                int index = existing is null ? -1 : extensions.IndexOf(existing);

                JsonNode detached = local.DeepClone();
                if (index >= 0) extensions[index] = detached;
                else extensions.Add(detached);
                changed = true;
            }
        }

        return changed ? root.ToJsonString() : clusterJson;
    }

    /// <summary>
    /// Every workspace plugin's generated contracts, by plugin id. A plugin that has not been built has
    /// no file and is simply absent — the same as it being absent from the cluster.
    /// </summary>
    private IEnumerable<(string Id, JsonNode Node)> LocalContracts()
    {
        if (!Directory.Exists(_workspace.ExtensionsPath)) yield break;

        var found = new List<(string Id, JsonNode Node)>();

        foreach (string dir in Directory.GetDirectories(_workspace.ExtensionsPath).OrderBy(d => d, StringComparer.Ordinal))
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

        if (manifest["title"] is JsonNode tit) plugin["title"] = tit.DeepClone();
        else if (manifest["dashboard_view"]?["title"] is JsonNode dvt) plugin["title"] = dvt.DeepClone();

        if (manifest["icon"] is JsonNode ic) plugin["icon"] = ic.DeepClone();
        else if (manifest["dashboard_view"]?["icon"] is JsonNode dvi) plugin["icon"] = dvi.DeepClone();

        if (manifest["dashboard_view"] is JsonNode dv) plugin["dashboard_view"] = dv.DeepClone();
        if (manifest["category"] is JsonNode cat) plugin["category"] = cat.DeepClone();

        if (manifest["input_types"] is JsonNode it) plugin["input_types"] = it.DeepClone();

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
            ["export"] = new JsonObject
            {
                ["plugins"] = new JsonArray(plugin),
                ["extensions"] = new JsonArray(plugin.DeepClone())
            }
        };

        return export.ToJsonString();
    }

    private const string EmptyExport = "{\"export\":{\"plugins\":[],\"extensions\":[]}}";
    private string ContractsCachePath => Path.Combine(_workspace.RootPath, ".contracts_cache.json");

    private void TryCacheContracts(string exportJson)
    {
        try
        {
            File.WriteAllText(ContractsCachePath, exportJson);
        }
        catch
        {
            // Non-fatal if cache cannot be written
        }
    }

    private string LoadCachedOrEmptyContracts()
    {
        try
        {
            if (File.Exists(ContractsCachePath))
            {
                return File.ReadAllText(ContractsCachePath);
            }
        }
        catch
        {
            // Non-fatal if cache cannot be read
        }

        return EmptyExport;
    }

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

    /// <summary>
    /// Where an extension's typed stubs live: under <c>obj/</c>, which the build compiles and nobody
    /// commits, so the file is never a thing to keep in step with the contracts it was made from.
    /// </summary>
    public static string StubsPath(string extensionDir) =>
        Path.Combine(extensionDir, "obj", "exoforge", "PluginServices.g.cs");

    /// <summary>A deployer whose workspace is the folder beside an extension: its siblings are the contracts.</summary>
    public static ExoDeployer BesideExtension(string extensionDir) =>
        new(new ExoWorkspace(
            Path.GetDirectoryName(Path.GetFullPath(extensionDir))!,
            new ExoProjectConfig { ExtensionsDir = Path.GetDirectoryName(Path.GetFullPath(extensionDir))! }));

    /// <summary>
    /// Build-time stubs: the services the extension declares as dependencies, from the sibling manifests,
    /// asking the cluster only for what they do not cover. Nothing declared means nothing to generate
    /// (<c>Output</c> is null); a dependency with no contract anywhere comes back in <c>Missing</c>.
    /// </summary>
    public async Task<(string? Output, IReadOnlyList<string> Missing)> GenerateDependencyStubsAsync(
        string extensionDir,
        CancellationToken cancellationToken = default)
    {
        // `database` is the host's own capability (Exo.Database), reached without a stub, and the generator
        // declares it for any extension that stores anything - so it must not demand a contract offline.
        if (ReadManifestDependencies(extensionDir) is not { } all
            || all.Where(d => d != "database").ToList() is not { Count: > 0 } deps)
        {
            return (null, Array.Empty<string>());
        }

        string export = MergeLocalContracts("{\"export\":{\"extensions\":[]}}");

        if (MissingServices(export, deps).Count > 0)
        {
            try
            {
                export = MergeLocalContracts(await GetContractsExportJsonAsync(cancellationToken: cancellationToken).ConfigureAwait(false));
            }
            catch (Exception)
            {
                // No cluster to ask: whatever the siblings did not cover stays missing, and is reported.
            }
        }

        var missing = MissingServices(export, deps);
        if (missing.Count > 0) return (null, missing);

        string output = StubsPath(extensionDir);
        ExoCodeGenerator.GeneratePluginStubsToFile(export, output, services: deps, pluginId: Path.GetFileName(extensionDir), codeSearchRoot: extensionDir);
        return (output, missing);
    }

    /// <summary>Generates typed stubs for every extension in the workspace that has a project.</summary>
    public async Task<List<string>> GenerateAllExtensionStubsAsync(
        string? environmentName = null,
        ExoClient? existingClient = null,
        CancellationToken cancellationToken = default)
    {
        var outputs = new List<string>();
        string extensionsDir = _workspace.ExtensionsPath;

        if (!Directory.Exists(extensionsDir)) return outputs;

        // One export for all extensions.
        string exportJson;
        try
        {
            exportJson = await GetContractsExportJsonAsync(environmentName, existingClient, cancellationToken).ConfigureAwait(false);
        }
        catch (Exception) when (existingClient == null)
        {
            exportJson = LoadCachedOrEmptyContracts();
        }

        string merged = MergeLocalContracts(exportJson);

        foreach (string dir in Directory.GetDirectories(extensionsDir))
        {
            string name = Path.GetFileName(dir);
            if (FindExtensionCsproj(dir, name) == null) continue;

            string output = StubsPath(dir);
            ExoCodeGenerator.GeneratePluginStubsToFile(merged, output, services: ReadManifestDependencies(dir), pluginId: name, codeSearchRoot: dir, log: null);
            outputs.Add(output);
        }

        return outputs;
    }

    public async Task<int> SyncContractsAsync(
        string? environmentName = null,
        string? outputPathOverride = null,
        ExoClient? existingClient = null,
        Action<string>? emit = null,
        bool includeStudio = false,
        CancellationToken cancellationToken = default)
    {
        string exportJson;
        if (existingClient != null)
        {
            var exportResult = await existingClient.SendActionAsync<JsonElement>("extension_manager", "export_extension_info", null, cancellationToken: cancellationToken).ConfigureAwait(false);
            exportJson = exportResult.GetRawText();
            TryCacheContracts(exportJson);
        }
        else
        {
            try
            {
                using var client = await CreateConnectedClientAsync(environmentName, cancellationToken).ConfigureAwait(false);
                var exportResult = await client.SendActionAsync<JsonElement>("extension_manager", "export_extension_info", null, cancellationToken: cancellationToken).ConfigureAwait(false);
                exportJson = exportResult.GetRawText();
                TryCacheContracts(exportJson);
            }
            catch (Exception ex)
            {
                emit?.Invoke($"[sync] no cluster ({ex.Message}) - falling back to cached/local contracts");
                exportJson = LoadCachedOrEmptyContracts();
            }
        }

        string rawJson = MergeLocalContracts(exportJson);
        string targetPath = outputPathOverride ?? _workspace.GeneratedPath;
        string? targetDir = Path.GetDirectoryName(targetPath);
        if (!string.IsNullOrEmpty(targetDir))
        {
            SyncCompanionAttributes(rawJson, Path.Combine(targetDir, "Attributes"), emit);
        }
        bool changed = ExoCodeGenerator.GenerateToFile(
            rawJson,
            targetPath,
            _workspace.Config.Codegen.Namespace,
            codeSearchRoot: _workspace.RootPath,
            log: emit,
            includeStudio: includeStudio);

        return changed ? 1 : 0;
    }

    public async Task<JsonElement> GetSystemStatusAsync(
        string? environmentName = null,
        CancellationToken cancellationToken = default)
    {
        using var client = await CreateConnectedClientAsync(environmentName, cancellationToken).ConfigureAwait(false);
        return await client.SendActionAsync<JsonElement>("extension_manager", "get_system_info", null, cancellationToken: cancellationToken).ConfigureAwait(false);
    }

    /// <summary>
    /// The runtime identifier the connected cluster runs on, so a build for it is not a build for this
    /// machine (a win-x64 binary uploaded to a linux-musl-x64 cluster dies on its first byte).
    /// Null when the cluster cannot be asked; the caller then falls back to the host.
    /// </summary>
    public async Task<string?> GetClusterTargetRidAsync(string? environmentName = null, CancellationToken cancellationToken = default)
    {
        try
        {
            return TargetRidFrom(await GetSystemStatusAsync(environmentName, cancellationToken).ConfigureAwait(false));
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return null;
        }
    }

    public static string? TargetRidFrom(JsonElement systemInfo)
    {
        if (systemInfo.ValueKind != JsonValueKind.Object) return null;

        JsonElement node = systemInfo.TryGetProperty("system", out var system) ? system : systemInfo;

        return node.ValueKind == JsonValueKind.Object && node.TryGetProperty("target_rid", out var rid) && rid.ValueKind == JsonValueKind.String
            && !string.IsNullOrWhiteSpace(rid.GetString())
            ? rid.GetString()
            : null;
    }

    public async Task<JsonElement> ListExtensionsAsync(
        string? environmentName = null,
        CancellationToken cancellationToken = default)
    {
        using var client = await CreateConnectedClientAsync(environmentName, cancellationToken).ConfigureAwait(false);
        return await client.SendActionAsync<JsonElement>("extension_manager", "list_extensions", null, cancellationToken: cancellationToken).ConfigureAwait(false);
    }

    /// <summary>
    /// Invokes any action on a service with optional payload and returns the raw response.
    /// </summary>
    public async Task<JsonElement> CallActionAsync(
        string service,
        string action,
        JsonObject? payload = null,
        string? environmentName = null,
        ExoClient? existingClient = null,
        CancellationToken ct = default)
    {
        var client = existingClient ?? await CreateConnectedClientAsync(environmentName, ct).ConfigureAwait(false);
        try
        {
            return await client.SendActionAsync<JsonElement>(service, action, payload, cancellationToken: ct).ConfigureAwait(false);
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
    /// Connects to the cluster, optionally logs in or authenticates, queries system status,
    /// and optionally saves the connection settings to exoforge.json and Assets/Resources/exoforge.json.
    /// </summary>
    public async Task<ExoConnectionVerificationResult> ConnectAndVerifyAsync(
        string? environmentName = null,
        string? wsUrlOverride = null,
        string? httpUrlOverride = null,
        string? tokenOverride = null,
        string? email = null,
        string? password = null,
        bool save = false,
        CancellationToken ct = default)
    {
        string targetEnvName = environmentName ?? _workspace.Config.DefaultEnvironment;
        var env = _workspace.GetActiveEnvironment(targetEnvName);

        string effectiveWsUrl = wsUrlOverride ?? env.WsUrl;
        string effectiveHttpUrl = httpUrlOverride ?? env.HttpUrl;
        string? effectiveToken = tokenOverride ?? env.Token;
        string? effectiveRefreshToken = env.RefreshToken;

        var client = new ExoClient();
        bool connected = false;
        bool authenticated = false;
        bool tokenSaved = false;
        JsonElement systemStatus = default;

        try
        {
            if (!string.IsNullOrEmpty(effectiveHttpUrl))
            {
                client.HttpBaseUri = new Uri(effectiveHttpUrl);
            }

            await client.ConnectAsync(new Uri(effectiveWsUrl), ct).ConfigureAwait(false);
            connected = true;

            if (!string.IsNullOrEmpty(email) && !string.IsNullOrEmpty(password))
            {
                // The device id makes the saved session replaceable: logging in again on this
                // machine and environment rotates that session rather than adding another pair.
                var loginPayload = new JsonObject
                {
                    ["email"] = email,
                    ["password"] = password,
                    ["device_id"] = CliDeviceId(targetEnvName)
                };

                var loginResult = await client.SendActionAsync<JsonElement>("auth", "login", loginPayload, cancellationToken: ct).ConfigureAwait(false);

                string? acquiredToken = null;
                if (loginResult.ValueKind == JsonValueKind.Object && loginResult.TryGetProperty("token", out var tokProp))
                {
                    acquiredToken = tokProp.GetString();
                }

                if (string.IsNullOrEmpty(acquiredToken))
                {
                    throw new InvalidOperationException("Cluster login succeeded, but no token was returned in the payload.");
                }

                if (!await TryAuthenticateAsync(client, acquiredToken, ct).ConfigureAwait(false))
                {
                    throw new InvalidOperationException("Authentication failed with the token the cluster issued.");
                }

                // A saved CLI session is the same pair a client holds: the access token lasts an
                // hour, and the refresh token beside it is what keeps the session usable.
                if (loginResult.ValueKind == JsonValueKind.Object && loginResult.TryGetProperty("refresh_token", out var refreshProp))
                {
                    effectiveRefreshToken = refreshProp.GetString();
                }

                authenticated = true;
                effectiveToken = acquiredToken;
            }
            else if (!string.IsNullOrEmpty(effectiveToken))
            {
                bool valid = await TryAuthenticateAsync(client, effectiveToken, ct).ConfigureAwait(false);

                // The hour passing is ordinary for a saved session, not a failed login: renew from
                // the refresh token beside it. An explicitly passed token is not the saved session,
                // so it is only validated.
                if (!valid && tokenOverride == null &&
                    !string.IsNullOrEmpty(effectiveRefreshToken) &&
                    await RefreshCliSessionAsync(client, env, targetEnvName, ct).ConfigureAwait(false))
                {
                    effectiveToken = env.Token;
                    effectiveRefreshToken = env.RefreshToken;
                    valid = await TryAuthenticateAsync(client, effectiveToken, ct).ConfigureAwait(false);
                }

                if (!valid)
                {
                    throw new InvalidOperationException("Authentication failed: the cluster refused the token.");
                }

                authenticated = true;
            }

            // The status query below is a call like any other: if the saved pair expires in this
            // command, renew it and retry once. A token passed on the command line is not that
            // session, so it is not renewed from it.
            if (tokenOverride == null && !string.IsNullOrEmpty(env.RefreshToken))
            {
                client.RefreshTokensAsync = ct2 => RefreshCliSessionAsync(client, env, targetEnvName, ct2);
            }

            systemStatus = await client.SendActionAsync<JsonElement>(
                "extension_manager", "get_system_info", null, cancellationToken: ct).ConfigureAwait(false);

            if (save)
            {
                if (!_workspace.Config.Environments.TryGetValue(targetEnvName, out var envConfig))
                {
                    envConfig = new ExoEnvironmentConfig();
                    _workspace.Config.Environments[targetEnvName] = envConfig;
                }

                envConfig.WsUrl = effectiveWsUrl;
                envConfig.HttpUrl = effectiveHttpUrl;
                if (!string.IsNullOrEmpty(effectiveToken))
                {
                    envConfig.Token = effectiveToken;
                    tokenSaved = true;
                }

                if (!string.IsNullOrEmpty(effectiveRefreshToken))
                {
                    envConfig.RefreshToken = effectiveRefreshToken;
                }

                _workspace.Save();
                SyncRuntimeConfigIfUnityProject(targetEnvName, effectiveWsUrl, effectiveHttpUrl);
            }

            return new ExoConnectionVerificationResult
            {
                Connected = connected,
                Environment = targetEnvName,
                WsUrl = effectiveWsUrl,
                HttpUrl = effectiveHttpUrl,
                Authenticated = authenticated,
                TokenSaved = tokenSaved,
                Status = systemStatus
            };
        }
        finally
        {
            client.Dispose();
        }
    }

    /// <summary>
    /// Synchronizes Assets/Resources/exoforge.json if the workspace belongs to a Unity project.
    /// </summary>
    public bool SyncRuntimeConfigIfUnityProject(string envName, string wsUrl, string httpUrl)
    {
        string projectRoot = _workspace.RootPath;
        if (!Directory.Exists(Path.Combine(projectRoot, "Assets")))
        {
            var parent = Directory.GetParent(projectRoot);
            if (parent != null && Directory.Exists(Path.Combine(parent.FullName, "Assets")))
            {
                projectRoot = parent.FullName;
            }
        }

        if (Directory.Exists(Path.Combine(projectRoot, "Assets")))
        {
            string rtDir = Path.Combine(projectRoot, "Assets", "Resources");
            string rtPath = Path.Combine(rtDir, "exoforge.json");
            Directory.CreateDirectory(rtDir);

            var payload = new Dictionary<string, object>
            {
                ["default_environment"] = envName,
                ["environments"] = new Dictionary<string, object>
                {
                    [envName] = new Dictionary<string, string>
                    {
                        ["ws_url"] = wsUrl,
                        ["http_url"] = httpUrl
                    }
                }
            };

            File.WriteAllText(rtPath, JsonSerializer.Serialize(payload, new JsonSerializerOptions { WriteIndented = true }));
            return true;
        }

        return false;
    }

    /// <summary>
    /// Fetches the contracts export (from live cluster or cached/local contracts) merged with local extensions.
    /// </summary>
    public async Task<JsonElement> GetContractsExportAsync(
        string? environmentName = null,
        CancellationToken ct = default)
    {
        string exportJson;
        try
        {
            exportJson = await GetContractsExportJsonAsync(environmentName, cancellationToken: ct).ConfigureAwait(false);
        }
        catch
        {
            exportJson = LoadCachedOrEmptyContracts();
        }

        string merged = MergeLocalContracts(exportJson);
        using var doc = JsonDocument.Parse(merged);
        return doc.RootElement.Clone();
    }

    /// <summary>
    /// Extracts all resource tables declared in cluster and local contracts.
    /// </summary>
    public async Task<List<ExoResourceTableInfo>> ListResourceTablesAsync(
        string? environmentName = null,
        CancellationToken ct = default)
    {
        var export = await GetContractsExportAsync(environmentName, ct).ConfigureAwait(false);
        var tables = new List<ExoResourceTableInfo>();

        JsonElement exportRoot = export;
        if (export.ValueKind == JsonValueKind.Object && export.TryGetProperty("export", out var expProp))
        {
            exportRoot = expProp;
        }

        JsonElement extensions = default;
        bool hasExtensions = false;
        if (exportRoot.ValueKind == JsonValueKind.Object)
        {
            if (exportRoot.TryGetProperty("extensions", out var exts) && exts.ValueKind == JsonValueKind.Array)
            {
                extensions = exts;
                hasExtensions = true;
            }
            else if (exportRoot.TryGetProperty("plugins", out var plgs) && plgs.ValueKind == JsonValueKind.Array)
            {
                extensions = plgs;
                hasExtensions = true;
            }
        }

        if (hasExtensions)
        {
            foreach (var ext in extensions.EnumerateArray())
            {
                string extId = ext.TryGetProperty("id", out var idProp) ? idProp.GetString() ?? "" : "";
                string extName = ext.TryGetProperty("name", out var nProp) ? nProp.GetString() ?? extId : extId;

                // 1. Resources declared under services
                if (ext.TryGetProperty("services", out var services) && services.ValueKind == JsonValueKind.Array)
                {
                    foreach (var svc in services.EnumerateArray())
                    {
                        string svcName = svc.TryGetProperty("name", out var sn) ? sn.GetString() ?? extName : extName;

                        if (svc.TryGetProperty("resources", out var resArr) && resArr.ValueKind == JsonValueKind.Array)
                        {
                            foreach (var res in resArr.EnumerateArray())
                            {
                                tables.Add(ParseResourceElement(svcName, res));
                            }
                        }
                    }
                }

                // 2. Direct resources on extension
                if (ext.TryGetProperty("resources", out var directRes) && directRes.ValueKind == JsonValueKind.Array)
                {
                    foreach (var res in directRes.EnumerateArray())
                    {
                        tables.Add(ParseResourceElement(extName, res));
                    }
                }
            }
        }

        return tables;
    }

    private static ExoResourceTableInfo ParseResourceElement(string serviceName, JsonElement res)
    {
        string name = res.TryGetProperty("name", out var rn) ? rn.GetString() ?? "" : "";
        string? source = null;
        if (res.TryGetProperty("source", out var sProp))
        {
            source = sProp.ValueKind == JsonValueKind.String ? sProp.GetString() : sProp.ToString();
        }

        string pk = "id";
        if (res.TryGetProperty("primary_key", out var pkProp) && pkProp.ValueKind == JsonValueKind.String)
        {
            pk = pkProp.GetString() ?? "id";
        }
        else if (res.TryGetProperty("primaryKey", out var pkProp2) && pkProp2.ValueKind == JsonValueKind.String)
        {
            pk = pkProp2.GetString() ?? "id";
        }

        bool singleton = false;
        if (res.TryGetProperty("singleton", out var singProp) && singProp.ValueKind is JsonValueKind.True or JsonValueKind.False)
        {
            singleton = singProp.GetBoolean();
        }
        else if (res.TryGetProperty("kind", out var kindProp) && kindProp.GetString() == "singleton")
        {
            singleton = true;
        }

        var cols = new List<ExoResourceColumnInfo>();
        if (res.TryGetProperty("columns", out var colsProp) && colsProp.ValueKind == JsonValueKind.Array)
        {
            foreach (var col in colsProp.EnumerateArray())
            {
                string cn = col.TryGetProperty("name", out var cnp) ? cnp.GetString() ?? "" : "";
                string ct = col.TryGetProperty("type", out var ctp) ? ctp.GetString() ?? "string" : "string";
                if (!string.IsNullOrEmpty(cn))
                {
                    cols.Add(new ExoResourceColumnInfo { Name = cn, Type = ct });
                }
            }
        }

        return new ExoResourceTableInfo
        {
            Service = serviceName,
            Name = name,
            Source = source,
            PrimaryKey = pk,
            Singleton = singleton,
            Columns = cols
        };
    }

    /// <summary>
    /// Invokes an action on the standard <c>resource_store</c> extension.
    /// </summary>
    public async Task<JsonElement> CallResourceStoreAsync(
        string action,
        string? resourceName = null,
        string? id = null,
        JsonObject? attributes = null,
        int? limit = null,
        int? offset = null,
        string? search = null,
        string? environmentName = null,
        CancellationToken ct = default)
    {
        var payload = new JsonObject();
        if (!string.IsNullOrEmpty(resourceName))
        {
            payload["resource"] = resourceName;
        }

        if (!string.IsNullOrEmpty(id))
        {
            payload["id"] = id;
        }

        if (attributes != null)
        {
            payload["attributes"] = attributes.DeepClone();
        }

        if (limit.HasValue)
        {
            payload["limit"] = limit.Value;
        }

        if (offset.HasValue)
        {
            payload["offset"] = offset.Value;
        }

        if (!string.IsNullOrEmpty(search))
        {
            payload["search"] = search;
        }

        return await CallActionAsync("resource_store", action, payload, environmentName, ct: ct).ConfigureAwait(false);
    }

    // -- Build --

    /// <summary>
    /// Builds a local extension in the workspace with <c>dotnet publish</c>: a framework-dependent
    /// binary, with <c>manifest.json</c> regenerated.
    /// The result is staged next to <c>manifest.json</c>, ready for <see cref="UploadExtensionAsync"/>.
    /// </summary>
    public ExoExtensionBuild BuildExtension(
        string extensionName,
        string? rid = null,
        string dotnetPath = "dotnet",
        Action<string>? log = null)
    {
        string cleanName = NormalizeExtensionName(extensionName);
        string extensionDir = Path.Combine(_workspace.ExtensionsPath, cleanName);

        if (!Directory.Exists(extensionDir))
        {
            string directDir = Path.Combine(_workspace.RootPath, cleanName);
            if (Directory.Exists(directDir))
            {
                extensionDir = directDir;
            }
            else
            {
                throw new DirectoryNotFoundException($"Extension directory not found: {extensionDir}");
            }
        }

        var output = new StringBuilder();
        void Emit(string line)
        {
            output.AppendLine(line);
            log?.Invoke(line);
        }

        string? csproj = FindExtensionCsproj(extensionDir, cleanName);
        string dotnet = ResolveDotnetPath(dotnetPath);
        if (dotnet != dotnetPath)
        {
            Emit($"[build] dotnet -> {dotnet}");
        }

        string fingerprint = ComputeSourceFingerprint(extensionDir);
        // Peek, don't commit: a failed build must not burn a build number, or the numbers you see
        // in a manifest cannot be correlated with the builds that produced them.
        int buildNumber = PeekBuildNumber(extensionDir);
        string buildStamp = $"{buildNumber}.{fingerprint}";
        // Refresh stubs from contracts before compiling if stubs file exists and cached contracts are available
        string stubsFile = StubsPath(extensionDir);
        if (File.Exists(stubsFile))
        {
            try
            {
                string cachedContracts = LoadCachedOrEmptyContracts();
                if (!string.IsNullOrWhiteSpace(cachedContracts) && cachedContracts.Trim() != "{}")
                {
                    string contractsJson = MergeLocalContracts(cachedContracts);
                    var available = AvailableServices(contractsJson).ToHashSet(StringComparer.OrdinalIgnoreCase);
                    var deps = ReadManifestDependencies(extensionDir);

                    if (deps is { Count: > 0 } && !deps.Any(d => available.Contains(d)))
                    {
                        // Contracts for declared dependencies cannot be resolved offline/unconnected; preserve existing stubs
                        Emit($"[build] Contracts for dependencies ({string.Join(", ", deps)}) not in offline cache; preserving existing stubs.");
                    }
                    else if (deps is { Count: > 0 })
                    {
                        ExoCodeGenerator.GeneratePluginStubsToFile(contractsJson, stubsFile, services: deps, pluginId: cleanName, codeSearchRoot: extensionDir, log: Emit);
                    }
                }
            }
            catch
            {
                // Best-effort: existing file remains if contracts cannot be resolved
            }
        }

        // One compiled kind. A runtime that needs its own toolchain adds that branch back alongside
        // its runner.
        string extensionType = "native";
        string binaryPath = PublishNative(csproj ?? throw new FileNotFoundException($"No .csproj found for '{cleanName}'."), extensionDir, cleanName, rid, dotnet, buildStamp, Emit);

        CommitBuildNumber(extensionDir, buildNumber);

        string manifestPath = Path.Combine(extensionDir, "manifest.json");
        return new ExoExtensionBuild(cleanName, extensionType, binaryPath, manifestPath, output.ToString());
    }

    /// <summary>Runs <see cref="BuildExtension"/> off the calling thread.</summary>
    public Task<ExoExtensionBuild> BuildExtensionAsync(
        string extensionName,
        string? rid = null,
        string dotnetPath = "dotnet",
        Action<string>? log = null,
        CancellationToken cancellationToken = default) =>
        Task.Run(() => BuildExtension(extensionName, rid, dotnetPath, log), cancellationToken);

    private string PublishNative(string csproj, string pluginDir, string cleanName, string? rid, string dotnetPath, string buildStamp, Action<string> emit)
    {
        ExoScaffolder.EnsureBuildFeed(_workspace.RootPath, pluginDir);

        string targetRid = string.IsNullOrWhiteSpace(rid) ? HostRuntimeIdentifier() : rid!;
        string manifest = Path.Combine(pluginDir, "manifest.json");

        string tfmArg = "";
        try
        {
            string csprojText = File.ReadAllText(csproj);
            int tfmStart = csprojText.IndexOf("<TargetFramework>net", StringComparison.OrdinalIgnoreCase);
            if (tfmStart >= 0)
            {
                int numStart = tfmStart + "<TargetFramework>net".Length;
                int dot = csprojText.IndexOf('.', numStart);
                if (dot > numStart && int.TryParse(csprojText.Substring(numStart, dot - numStart), out int projMajor))
                {
                    int highestInstalled = ExoScaffolder.DetectHighestInstalledSdkMajor(dotnetPath);
                    if (projMajor > highestInstalled && highestInstalled >= ExoScaffolder.MinimumMajorDotnetVersion)
                    {
                        tfmArg = $" -p:TargetFramework=net{highestInstalled}.0";
                        emit($"[build] Project targets net{projMajor}.0 but highest installed SDK is net{highestInstalled}.0; targeting net{highestInstalled}.0");
                    }
                }
            }
        }
        catch
        {
            // Best effort
        }

        // The manifest is written by Exoforge.Plugin.Generator during this same compile, so the
        // version stamped into it always describes the binary just produced. There is no second pass
        // over the compiled assembly, which is what used to let a stale Release tree win.
        // One pass. It was two while the generator wrote a JsonSerializerContext for a second compile
        // to pick up; plugins are framework-dependent now, so reflection serialises their records and
        // there is nothing to write.
        emit($"[build] dotnet restore -r {targetRid}");
        RunProcess(
            dotnetPath,
            $"restore \"{RelativeTo(pluginDir, csproj)}\" -r {targetRid}{tfmArg}",
            pluginDir,
            emit);

        emit($"[build] dotnet publish -c Release -r {targetRid}");
        RunProcess(
            dotnetPath,
            $"publish \"{RelativeTo(pluginDir, csproj)}\" -c Release -r {targetRid}{tfmArg} --no-restore " +
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
    /// Finds an extension's project file. Newer extensions keep it under <c>src/</c>; older ones at the root.
    /// </summary>
    private static string? FindExtensionCsproj(string pluginDir, string cleanName)
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
        return normalized.Contains("/bin/") ||
               normalized.Contains("/obj/") ||
               normalized.Contains("/.exoforge/") ||
               normalized.Contains("/.vs/") ||
               normalized.Contains("/.idea/") ||
               normalized.Contains("/.git/") ||
               normalized.Contains("/.vscode/") ||
               normalized.Contains("/Generated/") ||
               normalized.EndsWith(".g.cs", StringComparison.OrdinalIgnoreCase);
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

    /// <summary>
    /// Whether the sources differ from what was built. A manifest without the build stamp was not
    /// written by <c>exo</c> (an IDE or plain <c>dotnet build</c> rewrites it unstamped), so nothing
    /// proves it matches the sources: it counts as modified, never as current.
    /// </summary>
    public static bool IsModifiedSinceBuild(string pluginDir, string? manifestVersion)
    {
        if (manifestVersion is null || !manifestVersion.Contains('+')) return true;

        return !manifestVersion.EndsWith("." + ComputeSourceFingerprint(pluginDir), StringComparison.Ordinal);
    }

    public static string ComputeSourceFingerprint(string pluginDir)
    {
        var files = Directory.EnumerateFiles(pluginDir, "*.cs", SearchOption.AllDirectories)
            .Concat(Directory.EnumerateFiles(pluginDir, "*.csproj", SearchOption.AllDirectories))
            .Where(path => !IsBuildPath(path))
            .OrderBy(path => Path.GetRelativePath(pluginDir, path).Replace('\\', '/'), StringComparer.Ordinal)
            .ToList();

        var content = new StringBuilder();
        foreach (string file in files)
        {
            content.Append(Path.GetRelativePath(pluginDir, file).Replace('\\', '/')).Append('\n');
            string text = File.ReadAllText(file).Replace("\r\n", "\n").TrimEnd();
            content.Append(text).Append('\n');
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
    public static TimeSpan ProcessTimeout { get; set; } = TimeSpan.FromMinutes(5);

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
            string outStr = output.ToString();
            if (outStr.Contains("NETSDK1112"))
            {
                throw new InvalidOperationException(
                    $"{fileName} exited with code {proc.ExitCode}.\n{outStr}\n" +
                    "[Exoforge Diagnosis] NETSDK1112 indicates that the target runtime pack was not downloaded.\n" +
                    "Make sure your workspace nuget.config includes nuget.org and that your machine has an active internet connection to download Microsoft.NETCore.App.Runtime targeting packs from nuget.org.");
            }
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

    public static string HostRuntimeIdentifier()
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

    /// <summary>Turns any user-supplied name into the lower_snake_case id Exoforge uses.</summary>
    public static string NormalizeExtensionName(string extensionName) => NormalizePluginName(extensionName);

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

/// <summary>One log line an extension emitted, as served by <c>extension_manager.logs</c>.</summary>
public sealed class ExtensionLogLine
{
    public ExtensionLogLine(long at, string levelName, string message)
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
/// Whether the cluster actually has an extension after a deploy, and at which version.
/// </summary>
public sealed class ExtensionDeploymentStatus
{
    public ExtensionDeploymentStatus(bool isDeployed, string? version, string? type, string detail)
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

    /// <summary>True when the extension is loaded and at the expected version.</summary>
    public bool IsHealthy => IsDeployed && Detail == "loaded";
}

/// <summary>Result of <see cref="ExoDeployer.BuildExtension"/>.</summary>
public class ExoExtensionBuild
{
    public ExoExtensionBuild(string name, string extensionType, string binaryPath, string manifestPath, string output)
    {
        Name = name;
        ExtensionType = extensionType;
        BinaryPath = binaryPath;
        ManifestPath = manifestPath;
        Output = output;
    }

    public string Name { get; }
    public string ExtensionType { get; }
    public string BinaryPath { get; }
    public string ManifestPath { get; }
    public string Output { get; }
}

public class ExoConnectionVerificationResult
{
    [JsonPropertyName("connected")]
    public bool Connected { get; set; }

    [JsonPropertyName("environment")]
    public string Environment { get; set; } = "";

    [JsonPropertyName("ws_url")]
    public string WsUrl { get; set; } = "";

    [JsonPropertyName("http_url")]
    public string HttpUrl { get; set; } = "";

    [JsonPropertyName("authenticated")]
    public bool Authenticated { get; set; }

    [JsonPropertyName("token_saved")]
    public bool TokenSaved { get; set; }

    [JsonPropertyName("status")]
    public JsonElement Status { get; set; }
}

public class ExoResourceTableInfo
{
    [JsonPropertyName("service")]
    public string Service { get; set; } = "";

    [JsonPropertyName("name")]
    public string Name { get; set; } = "";

    [JsonPropertyName("source")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Source { get; set; }

    [JsonPropertyName("primary_key")]
    public string PrimaryKey { get; set; } = "id";

    [JsonPropertyName("singleton")]
    public bool Singleton { get; set; }

    [JsonPropertyName("columns")]
    public List<ExoResourceColumnInfo> Columns { get; set; } = new();
}

public class ExoResourceColumnInfo
{
    [JsonPropertyName("name")]
    public string Name { get; set; } = "";

    [JsonPropertyName("type")]
    public string Type { get; set; } = "string";
}
