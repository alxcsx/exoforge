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
        CancellationToken cancellationToken = default)
    {
        string cleanName = pluginName.Trim().ToLowerInvariant().Replace("-", "_");
        string pluginDir = Path.Combine(_workspace.PluginsPath, cleanName);

        // Find .wasm file
        string wasmPath = Path.Combine(pluginDir, $"{cleanName}.wasm");
        if (!File.Exists(wasmPath))
        {
            // Search in bin/ or subdirectories
            var matches = Directory.GetFiles(pluginDir, "*.wasm", SearchOption.AllDirectories);
            if (matches.Length > 0)
            {
                wasmPath = matches[0];
            }
            else
            {
                throw new FileNotFoundException($"No .wasm binary found for plugin '{cleanName}'. Build it first.");
            }
        }

        byte[] wasmBytes = await File.ReadAllBytesAsync(wasmPath, cancellationToken).ConfigureAwait(false);
        string wasmBase64 = Convert.ToBase64String(wasmBytes);

        string? manifestContent = null;
        string manifestPath = Path.Combine(pluginDir, "manifest.exs");
        if (File.Exists(manifestPath))
        {
            manifestContent = await File.ReadAllTextAsync(manifestPath, cancellationToken).ConfigureAwait(false);
        }

        using var client = await CreateConnectedClientAsync(environmentName, cancellationToken).ConfigureAwait(false);

        var payload = new
        {
            name = cleanName,
            wasm_binary = wasmBase64,
            manifest = manifestContent
        };

        var result = await client.PluginManager().UploadPluginAsync(cleanName, wasmBase64, manifestContent ?? "", cancellationToken).ConfigureAwait(false);
        return result.ToString();
    }

    public async Task<string> RemovePluginAsync(
        string pluginId,
        string? environmentName = null,
        CancellationToken cancellationToken = default)
    {
        using var client = await CreateConnectedClientAsync(environmentName, cancellationToken).ConfigureAwait(false);
        var result = await client.PluginManager().RemovePluginAsync(pluginId, cancellationToken).ConfigureAwait(false);
        return result.ToString();
    }

    public async Task<int> SyncContractsAsync(
        string? environmentName = null,
        CancellationToken cancellationToken = default)
    {
        using var client = await CreateConnectedClientAsync(environmentName, cancellationToken).ConfigureAwait(false);
        var exportResult = await client.PluginManager().ExportPluginInfoAsync(cancellationToken).ConfigureAwait(false);

        string rawJson = exportResult.GetRawText();
        ExoCodeGenerator.GenerateToFile(rawJson, _workspace.GeneratedPath, _workspace.Config.Codegen.Namespace);

        return 1;
    }

    public async Task<JsonElement> GetSystemStatusAsync(
        string? environmentName = null,
        CancellationToken cancellationToken = default)
    {
        using var client = await CreateConnectedClientAsync(environmentName, cancellationToken).ConfigureAwait(false);
        return await client.PluginManager().GetSystemInfoAsync(cancellationToken).ConfigureAwait(false);
    }

    public async Task<JsonElement> ListPluginsAsync(
        string? environmentName = null,
        CancellationToken cancellationToken = default)
    {
        using var client = await CreateConnectedClientAsync(environmentName, cancellationToken).ConfigureAwait(false);
        return await client.PluginManager().ListPluginsAsync(cancellationToken).ConfigureAwait(false);
    }
}
