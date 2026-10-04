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

        if (csproj != null)
        {
            Emit($"[build] dotnet build {Path.GetFileName(csproj)}");
            RunProcess(dotnet, $"build \"{csproj}\" -c Release", pluginDir, Emit);
        }

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
            binaryPath = PublishNative(csproj ?? throw new FileNotFoundException($"No .csproj found for '{cleanName}'."), pluginDir, cleanName, rid, dotnet, Emit);
        }

        string manifestPath = Path.Combine(pluginDir, "manifest.exs");
        return new ExoPluginBuild(cleanName, pluginType, binaryPath, manifestPath, output.ToString());
    }

    /// <summary>Runs <see cref="BuildPlugin"/> off the calling thread.</summary>
    public Task<ExoPluginBuild> BuildPluginAsync(
        string pluginName,
        string? rid = null,
        string dotnetPath = "dotnet",
        CancellationToken cancellationToken = default)
    {
        return Task.Run(() => BuildPlugin(pluginName, rid, dotnetPath), cancellationToken);
    }

    private string PublishNative(string csproj, string pluginDir, string cleanName, string? rid, string dotnetPath, Action<string> emit)
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
            $"run --project \"{manifestGen}\" -- \"{dll}\" \"{manifest}\" --type native",
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
    public static string ResolveDotnetPath(string? configured)
    {
        string candidate = string.IsNullOrWhiteSpace(configured) ? "dotnet" : configured.Trim();

        if (!IsBareCommand(candidate))
        {
            return candidate;
        }

        return FindOnPath(candidate)
            ?? FindViaLoginShell()
            ?? FindInCommonLocations()
            ?? candidate;
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

    private static string NormalizePluginName(string pluginName)
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
