using System;
using System.IO;
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
            var matches = Directory.GetFiles(pluginDir, "*.wasm", SearchOption.AllDirectories);
            if (matches.Length > 0)
            {
                wasmPath = matches[0];
            }
        }

        string pluginType = wasmPath != null ? "wasm" : "native";
        string binaryPath = wasmPath ?? Path.Combine(pluginDir, cleanName);

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
                wasm_binary = binaryBase64,
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

    public async Task<string> RemovePluginAsync(
        string pluginId,
        string? environmentName = null,
        ExoClient? existingClient = null,
        CancellationToken cancellationToken = default)
    {
        var client = existingClient ?? await CreateConnectedClientAsync(environmentName, cancellationToken).ConfigureAwait(false);
        try
        {
            var result = await client.SendActionAsync<JsonElement>("plugin_manager", "remove_plugin", new { id = pluginId }, cancellationToken: cancellationToken).ConfigureAwait(false);
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
}
