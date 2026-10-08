using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Exoforge.Management;

namespace Exoforge.CLI;

public static class Program
{
    public static async Task<int> Main(string[] args)
    {
        if (args.Length == 0)
        {
            PrintUsage();
            return 0;
        }

        string command = args[0].ToLowerInvariant();

        if (command is "help" or "--help" or "-h")
        {
            PrintUsage();
            return 0;
        }

        var cli = CliArgs.Parse(args, 1);

        try
        {
            switch (command)
            {
                case "init":
                    return HandleInit(cli);

                case "plugin":
                    return await HandlePluginAsync(cli).ConfigureAwait(false);

                case "sync":
                case "gen":
                    return await HandleSyncAsync(cli).ConfigureAwait(false);

                case "status":
                    return await HandleStatusAsync(cli).ConfigureAwait(false);

                default:
                    Error($"Unknown command: {command}");
                    Console.WriteLine();
                    PrintUsage();
                    return 1;
            }
        }
        catch (Exception ex)
        {
            Error(Describe(ex));
            return 1;
        }
    }

    // ---- usage -------------------------------------------------------------------------

    private static void PrintUsage()
    {
        Console.WriteLine("""
        ===============================================================
               EXOFORGE DEVELOPER CLI (Non-Mix / C# SDK Tools)
        ===============================================================

        Usage: exo <command> [options]

        Commands:
          init                     Initialize the workspace and exoforge.json
          plugin <subcommand>      Create, build, deploy and inspect plugins
          sync                     Download live contracts and generate the typed C# client
          status                   Inspect live cluster health and metrics

        Options:
          --dir <path>             Workspace root (defaults to the current directory)
          --env <environment>      Target environment from exoforge.json (default: 'local')
          --json                   Machine-readable output (plugin list, logs, status)
          -h, --help               Help for a command, e.g. `exo plugin push --help`

        Run `exo plugin --help` for the plugin subcommands.
        """);
    }

    private static void PrintPluginUsage()
    {
        Console.WriteLine("""
        Usage: exo plugin <subcommand> [name] [options]

        Subcommands:
          new <name>       Scaffold a C# plugin project
          build <name>     Compile the plugin (NativeAOT, or WASM when build.sh exists)
          push <name>      Build, deploy, and verify the plugin on the live cluster
          dev <name>       Watch sources and re-deploy on every change
          reload <name>    Re-boot an installed plugin without re-uploading it
          logs <name>      Show recent log lines the plugin emitted
          stubs <name>     Generate typed service stubs from the live contracts
          list             List installed plugins
          remove <id>      Remove a plugin from the cluster

        Common options:
          --dir <path>     Workspace root (defaults to the current directory)
          --env <name>     Target environment
          --json           Machine-readable output

        Run `exo plugin <subcommand> --help` for the options of one subcommand.
        """);
    }

    // ---- init / sync / status ----------------------------------------------------------

    private static int HandleInit(CliArgs cli)
    {
        if (cli.WantsHelp)
        {
            Console.WriteLine("""
            Usage: exo init [--dir <path>] [--name <project_name>]

            Creates exoforge.json and the plugins/ directory.
            """);
            return 0;
        }

        string dir = cli.Value("dir") ?? Directory.GetCurrentDirectory();
        string name = cli.Value("name") ?? Path.GetFileName(Path.GetFullPath(dir));

        var ws = ExoWorkspace.Initialize(dir, name);
        Success($"[Exoforge] Initialized workspace at {ws.RootPath}");
        Console.WriteLine($"  Config:     {ws.ConfigPath}");
        Console.WriteLine($"  Plugins:    {ws.PluginsPath}");
        Console.WriteLine($"  Client Gen: {ws.GeneratedPath}");
        Console.WriteLine();
        Console.WriteLine("Next: exo plugin new <name>");
        return 0;
    }

    private static async Task<int> HandleSyncAsync(CliArgs cli)
    {
        if (cli.WantsHelp)
        {
            Console.WriteLine("""
            Usage: exo sync [options]

              --dir <path>     Workspace root
              --env <name>     Target environment
              --out <path>     Output file (defaults to the workspace's generated path)
              --file <json>    Generate from a saved export instead of the live cluster
            """);
            return 0;
        }

        string dir = cli.Value("dir") ?? Directory.GetCurrentDirectory();
        string? fileInput = cli.Value("file");
        string? outPath = cli.Value("out");

        if (!string.IsNullOrEmpty(fileInput) && File.Exists(fileInput))
        {
            Console.WriteLine($"[Exoforge] Generating strongly-typed C# client bindings from '{fileInput}'...");
            string targetPath = outPath ?? Path.Combine(dir, "Generated", "ExoforgeServices.g.cs");
            ExoCodeGenerator.GenerateToFile(File.ReadAllText(fileInput), targetPath);
            Success($"[Exoforge] Generated strongly-typed C# client bindings at:\n  {targetPath}");
            return 0;
        }

        var ws = ExoWorkspace.Load(dir);
        var deployer = new ExoDeployer(ws);

        Console.WriteLine("[Exoforge] Synchronizing backend contracts from cluster...");
        await deployer.SyncContractsAsync(cli.Value("env"), outPath).ConfigureAwait(false);
        Success($"[Exoforge] Generated strongly-typed C# client bindings at:\n  {outPath ?? ws.GeneratedPath}");
        return 0;
    }

    private static async Task<int> HandleStatusAsync(CliArgs cli)
    {
        if (cli.WantsHelp)
        {
            Console.WriteLine("Usage: exo status [--dir <path>] [--env <name>] [--json]");
            return 0;
        }

        var ws = ExoWorkspace.Load(cli.Value("dir") ?? Directory.GetCurrentDirectory());
        var deployer = new ExoDeployer(ws);

        if (!cli.Json)
        {
            Console.WriteLine("[Exoforge] Querying cluster status...");
        }

        var status = await deployer.GetSystemStatusAsync(cli.Value("env")).ConfigureAwait(false);
        Console.WriteLine(PrettyJson(status));
        return 0;
    }

    // ---- plugin ------------------------------------------------------------------------

    private static async Task<int> HandlePluginAsync(CliArgs cli)
    {
        if (cli.WantsHelp && cli.Positional.Count == 0)
        {
            PrintPluginUsage();
            return 0;
        }

        if (cli.Positional.Count == 0)
        {
            Error("Missing plugin subcommand.");
            Console.WriteLine();
            PrintPluginUsage();
            return 1;
        }

        string sub = cli.Positional[0].ToLowerInvariant();

        // Everything after the subcommand, so `exo plugin push foo --rid x` parses the same as
        // `exo plugin push --rid x foo`.
        var rest = CliArgs.From(cli.Positional.Skip(1).ToList(), cli);

        switch (sub)
        {
            case "new":
                return HandlePluginNew(rest);

            case "build":
                return HandlePluginBuild(rest);

            case "push":
                return await HandlePluginPushAsync(rest).ConfigureAwait(false);

            case "dev":
                return await HandlePluginDevAsync(rest).ConfigureAwait(false);

            case "reload":
                return await HandlePluginReloadAsync(rest).ConfigureAwait(false);

            case "logs":
                return await HandlePluginLogsAsync(rest).ConfigureAwait(false);

            case "stubs":
                return await HandlePluginStubsAsync(rest).ConfigureAwait(false);

            case "list":
                return await HandlePluginListAsync(rest).ConfigureAwait(false);

            case "remove":
                return await HandlePluginRemoveAsync(rest).ConfigureAwait(false);

            default:
                Error($"Unknown plugin subcommand: {sub}");
                Console.WriteLine();
                PrintPluginUsage();
                return 1;
        }
    }

    private static int HandlePluginNew(CliArgs cli)
    {
        if (cli.WantsHelp)
        {
            Console.WriteLine("""
            Usage: exo plugin new <name> [--template standard|inventory] [--dir <path>] [--sdk <path>]

            Scaffolds plugins/<name>/ with a src/ project, a solution, and a .gitignore.

              --template <t>   standard (default) or inventory
              --sdk <path>     Exoforge.Plugin.SDK.csproj, when the repo is not above the workspace
            """);
            return 0;
        }

        if (cli.Positional.Count == 0)
        {
            return Missing("plugin name", "exo plugin new <name>");
        }

        string raw = cli.Positional[0];
        string template = cli.Value("template") ?? "standard";

        var ws = ExoWorkspace.Load(cli.Value("dir") ?? Directory.GetCurrentDirectory());

        // Say what the plugin id will be: the name is normalised, and silently renaming someone's
        // input is how you end up with a plugin nobody can find.
        string id = ExoScaffolder.NormalizePluginName(raw);

        if (!string.Equals(raw, id, StringComparison.Ordinal))
        {
            Console.WriteLine($"[Exoforge] '{raw}' will be created as '{id}' (plugin ids are lower_snake_case).");
        }

        string created = ExoScaffolder.ScaffoldPlugin(
            ws.PluginsPath, raw, sdkProjectPath: cli.Value("sdk"), template: template);

        Success($"[Exoforge] Scaffolded C# plugin '{id}' ({template}) at:\n  {created}");
        Console.WriteLine();
        Console.WriteLine("Next:");
        Console.WriteLine($"  1. Edit  {Path.Combine(created, "src", ExoScaffolder.ClassNameFor(id) + "Plugin.cs")}");
        Console.WriteLine($"  2. Build  exo plugin build {id}");
        Console.WriteLine($"  3. Deploy exo plugin push {id}");
        return 0;
    }

    private static int HandlePluginBuild(CliArgs cli)
    {
        if (cli.WantsHelp)
        {
            Console.WriteLine("""
            Usage: exo plugin build <name> [--rid <rid>] [--dir <path>]

              --rid <rid>   Target runtime, e.g. linux-x64 (default: this machine)
            """);
            return 0;
        }

        if (cli.Positional.Count == 0)
        {
            return Missing("plugin name", "exo plugin build <name>");
        }

        var ws = ExoWorkspace.Load(cli.Value("dir") ?? Directory.GetCurrentDirectory());
        return Build(ws, cli.Positional[0], cli.Value("rid"));
    }

    private static async Task<int> HandlePluginPushAsync(CliArgs cli)
    {
        if (cli.WantsHelp)
        {
            Console.WriteLine("""
            Usage: exo plugin push <name> [--rid <rid>] [--env <name>] [--dir <path>] [--no-verify]

            Builds, uploads, and then confirms the cluster is actually running the new build.
            """);
            return 0;
        }

        if (cli.Positional.Count == 0)
        {
            return Missing("plugin name", "exo plugin push <name>");
        }

        string name = cli.Positional[0];
        var ws = ExoWorkspace.Load(cli.Value("dir") ?? Directory.GetCurrentDirectory());
        var deployer = new ExoDeployer(ws);
        string? env = cli.Value("env");

        return await BuildThenPushAsync(deployer, ws, name, cli.Value("rid"), env, verify: !cli.Has("no-verify"))
            .ConfigureAwait(false);
    }

    private static async Task<int> HandlePluginDevAsync(CliArgs cli)
    {
        if (cli.WantsHelp)
        {
            Console.WriteLine("""
            Usage: exo plugin dev <name> [--rid <rid>] [--env <name>] [--dir <path>]

            Builds, deploys, then watches the plugin's sources and repeats on every change.
            Stop with Ctrl-C.
            """);
            return 0;
        }

        if (cli.Positional.Count == 0)
        {
            return Missing("plugin name", "exo plugin dev <name>");
        }

        string name = cli.Positional[0];
        var ws = ExoWorkspace.Load(cli.Value("dir") ?? Directory.GetCurrentDirectory());
        var deployer = new ExoDeployer(ws);
        string? env = cli.Value("env");
        string? rid = cli.Value("rid");

        string pluginDir = Path.Combine(ws.PluginsPath, ExoScaffolder.NormalizePluginName(name));
        if (!Directory.Exists(pluginDir))
        {
            Error($"Plugin directory not found: {pluginDir}");
            return 1;
        }

        int first = await BuildThenPushAsync(deployer, ws, name, rid, env, verify: true).ConfigureAwait(false);
        if (first != 0)
        {
            Error("Initial build failed — fix it and the watcher will pick up the change.");
        }

        // Poll the source fingerprint rather than using FileSystemWatcher: it is the same hash the
        // build stamp uses, so "changed" means exactly "the build stamp would change", and it
        // behaves identically on every platform and filesystem.
        string last = ExoDeployer.ComputeSourceFingerprint(pluginDir);
        Console.WriteLine($"[Exoforge] Watching {pluginDir} (fingerprint {last}). Ctrl-C to stop.");

        while (true)
        {
            Thread.Sleep(1000);

            string current = ExoDeployer.ComputeSourceFingerprint(pluginDir);
            if (current == last) continue;

            last = current;
            Console.WriteLine();
            Console.WriteLine($"[Exoforge] Sources changed ({current}) — rebuilding…");

            // A failed rebuild keeps the previous fingerprint, so fixing the error triggers again.
            int code = await BuildThenPushAsync(deployer, ws, name, rid, env, verify: true).ConfigureAwait(false);
            if (code != 0)
            {
                last = "";
            }
        }
    }

    private static async Task<int> HandlePluginReloadAsync(CliArgs cli)
    {
        if (cli.WantsHelp)
        {
            Console.WriteLine("""
            Usage: exo plugin reload <name> [--env <name>] [--dir <path>]

            Re-boots an installed plugin from the files already on the cluster — no rebuild,
            no re-upload. Use it after changing plugin config, or to recover a plugin that died.
            """);
            return 0;
        }

        if (cli.Positional.Count == 0)
        {
            return Missing("plugin name", "exo plugin reload <name>");
        }

        string name = ExoScaffolder.NormalizePluginName(cli.Positional[0]);
        var ws = ExoWorkspace.Load(cli.Value("dir") ?? Directory.GetCurrentDirectory());
        var deployer = new ExoDeployer(ws);

        Console.WriteLine($"[Exoforge] Reloading '{name}'…");

        JsonElement result;
        try
        {
            result = await deployer.ReloadPluginAsync(name, cli.Value("env")).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            Error(Describe(ex));
            return 1;
        }

        if (cli.Json)
        {
            Console.WriteLine(PrettyJson(result));
            return 0;
        }

        Success($"[Exoforge] Reloaded '{name}' ({ReadString(result, "status") ?? "ok"}).");
        return 0;
    }

    private static async Task<int> HandlePluginLogsAsync(CliArgs cli)
    {
        if (cli.WantsHelp)
        {
            Console.WriteLine("""
            Usage: exo plugin logs <name> [--limit <n>] [--follow] [--json] [--env <name>]

              --limit <n>   How many recent lines to show (default 100)
              --follow      Keep printing new lines until Ctrl-C

            Lines are held in memory on the cluster and capped per plugin, so this is
            "what did my plugin just do?" rather than a permanent log store.
            """);
            return 0;
        }

        if (cli.Positional.Count == 0)
        {
            return Missing("plugin name", "exo plugin logs <name>");
        }

        string name = ExoScaffolder.NormalizePluginName(cli.Positional[0]);
        var ws = ExoWorkspace.Load(cli.Value("dir") ?? Directory.GetCurrentDirectory());
        var deployer = new ExoDeployer(ws);
        string? env = cli.Value("env");
        int limit = cli.IntValue("limit", 100);

        List<PluginLogLine> lines;
        try
        {
            lines = await deployer.GetPluginLogsAsync(name, limit, env).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            Error(Describe(ex));
            return 1;
        }

        if (cli.Json)
        {
            Console.WriteLine(JsonSerializer.Serialize(lines, JsonOptions));
        }
        else
        {
            PrintLogLines(lines);
        }

        if (!cli.Has("follow"))
        {
            return 0;
        }

        Console.WriteLine($"[Exoforge] Following '{name}'. Ctrl-C to stop.");
        var seen = lines.Count > 0 ? lines[^1] : null;

        while (true)
        {
            Thread.Sleep(1000);

            var fresh = await deployer.GetPluginLogsAsync(name, limit, env).ConfigureAwait(false);
            if (fresh.Count == 0) continue;

            // Resume after the last line we printed; if it has rotated out of the buffer, the whole
            // window is new to us and we print it.
            int start = 0;
            if (seen != null)
            {
                int index = fresh.FindIndex(l => l.At == seen.At && l.Message == seen.Message);
                start = index >= 0 ? index + 1 : 0;
            }

            for (int i = start; i < fresh.Count; i++)
            {
                PrintLogLine(fresh[i]);
                seen = fresh[i];
            }
        }
    }

    private static async Task<int> HandlePluginStubsAsync(CliArgs cli)
    {
        if (cli.WantsHelp)
        {
            Console.WriteLine("""
            Usage: exo plugin stubs <name> [--services a,b] [--out <path>] [--file <export.json>]

            Generates typed stubs for the contracts this plugin calls, so plugin code does not
            hand-roll service and action names.
            """);
            return 0;
        }

        if (cli.Positional.Count == 0)
        {
            return Missing("plugin name", "exo plugin stubs <name>");
        }

        string name = ExoScaffolder.NormalizePluginName(cli.Positional[0]);
        var ws = ExoWorkspace.Load(cli.Value("dir") ?? Directory.GetCurrentDirectory());
        var deployer = new ExoDeployer(ws);

        string? contractsFile = cli.Value("file");
        string exportJson = !string.IsNullOrEmpty(contractsFile) && File.Exists(contractsFile)
            ? File.ReadAllText(contractsFile)
            : await deployer.GetContractsExportJsonAsync(cli.Value("env")).ConfigureAwait(false);

        string pluginDir = Path.Combine(ws.PluginsPath, name);
        string stubsOut = cli.Value("out") ?? Path.Combine(pluginDir, "src", "Generated", "PluginServices.g.cs");

        string? servicesOption = cli.Value("services");
        IEnumerable<string>? services = servicesOption != null
            ? servicesOption.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            : ExoDeployer.ReadManifestDependencies(pluginDir);

        ExoCodeGenerator.GeneratePluginStubsToFile(exportJson, stubsOut, services: services, pluginId: name);
        Success($"[Exoforge] Generated typed plugin service stubs:\n  {stubsOut}");
        return 0;
    }

    private static async Task<int> HandlePluginListAsync(CliArgs cli)
    {
        if (cli.WantsHelp)
        {
            Console.WriteLine("Usage: exo plugin list [--json] [--env <name>] [--dir <path>]");
            return 0;
        }

        var ws = ExoWorkspace.Load(cli.Value("dir") ?? Directory.GetCurrentDirectory());
        var deployer = new ExoDeployer(ws);

        if (!cli.Json)
        {
            Console.WriteLine("[Exoforge] Fetching installed plugins from live cluster...");
        }

        var result = await deployer.ListPluginsAsync(cli.Value("env")).ConfigureAwait(false);
        Console.WriteLine(PrettyJson(result));
        return 0;
    }

    private static async Task<int> HandlePluginRemoveAsync(CliArgs cli)
    {
        if (cli.WantsHelp)
        {
            Console.WriteLine("""
            Usage: exo plugin remove <id> [--yes] [--delete-files] [--env <name>] [--dir <path>]

              --yes             Skip the confirmation prompt (required when not interactive)
              --delete-files    Also delete the plugin's staged files on the cluster
            """);
            return 0;
        }

        if (cli.Positional.Count == 0)
        {
            return Missing("plugin id", "exo plugin remove <id>");
        }

        string id = cli.Positional[0];

        // Removing a plugin from a running cluster is not undoable by re-running a command.
        if (!cli.Has("yes"))
        {
            if (Console.IsInputRedirected)
            {
                Error($"Refusing to remove '{id}' without confirmation. Pass --yes.");
                return 1;
            }

            Console.Write($"[Exoforge] Remove plugin '{id}' from the cluster? [y/N] ");
            string? answer = Console.ReadLine();

            if (!string.Equals(answer?.Trim(), "y", StringComparison.OrdinalIgnoreCase) &&
                !string.Equals(answer?.Trim(), "yes", StringComparison.OrdinalIgnoreCase))
            {
                Console.WriteLine("Cancelled.");
                return 0;
            }
        }

        var ws = ExoWorkspace.Load(cli.Value("dir") ?? Directory.GetCurrentDirectory());
        var deployer = new ExoDeployer(ws);

        await deployer.RemovePluginAsync(id, cli.Value("env"), deleteFiles: cli.Has("delete-files"))
            .ConfigureAwait(false);

        Success($"[Exoforge] Removed plugin '{id}' from the cluster.");
        return 0;
    }

    // ---- shared steps ------------------------------------------------------------------

    /// <summary>
    /// Builds, and stops if the build failed. <c>push</c> used to ignore this result and upload the
    /// previous binary, so a compile error looked like a successful deploy.
    /// </summary>
    private static async Task<int> BuildThenPushAsync(
        ExoDeployer deployer,
        ExoWorkspace ws,
        string name,
        string? rid,
        string? env,
        bool verify)
    {
        if (Build(ws, name, rid) != 0)
        {
            Error("[Exoforge] Not deploying: the build failed, so the last good binary would be uploaded.");
            return 1;
        }

        string cleanName = ExoScaffolder.NormalizePluginName(name);
        string pluginDir = Path.Combine(ws.PluginsPath, cleanName);
        string? builtVersion = ExoDeployer.ReadManifestVersion(pluginDir);

        Console.WriteLine($"[Exoforge] Uploading plugin '{cleanName}' to live cluster...");
        string result = await deployer.UploadPluginAsync(cleanName, env).ConfigureAwait(false);
        Success($"[Exoforge] Deployed '{cleanName}'.");
        Console.WriteLine($"  Server Response: {result}");

        if (!verify)
        {
            return 0;
        }

        // "installed" only means the files landed. Confirm the cluster is running the new build.
        var status = await deployer.VerifyPluginAsync(cleanName, builtVersion, env).ConfigureAwait(false);

        if (status.IsHealthy)
        {
            Console.WriteLine($"  Verified: {status.Version} loaded ({status.Type}).");
            return 0;
        }

        Error($"[Exoforge] Deployed, but the cluster does not look healthy: {status.Detail}");
        Console.WriteLine($"  Check `exo plugin logs {cleanName}`.");
        return 1;
    }

    private static int Build(ExoWorkspace ws, string rawName, string? ridOverride)
    {
        try
        {
            var build = new ExoDeployer(ws).BuildPlugin(rawName, ridOverride, log: Console.WriteLine);
            Success($"[Exoforge] Build complete for plugin '{build.Name}' ({build.PluginType}).");
            return 0;
        }
        catch (Exception ex)
        {
            Error($"[Exoforge] Build failed: {ex.Message}");
            return 1;
        }
    }

    // ---- output ------------------------------------------------------------------------

    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    private static string PrettyJson(JsonElement element) =>
        JsonSerializer.Serialize(element, JsonOptions);

    private static void PrintLogLines(List<PluginLogLine> lines)
    {
        if (lines.Count == 0)
        {
            Console.WriteLine("(no log lines recorded — the plugin may not have run yet)");
            return;
        }

        foreach (var line in lines)
        {
            PrintLogLine(line);
        }
    }

    private static void PrintLogLine(PluginLogLine line)
    {
        var previous = Console.ForegroundColor;
        Console.ForegroundColor = line.LevelName switch
        {
            "error" => ConsoleColor.Red,
            "warning" => ConsoleColor.Yellow,
            "debug" => ConsoleColor.DarkGray,
            _ => previous
        };

        Console.WriteLine($"{line.LocalTime:HH:mm:ss}  {line.LevelName,-7} {line.Message}");
        Console.ResetColor();
    }

    private static string? ReadString(JsonElement element, string property) =>
        element.ValueKind == JsonValueKind.Object && element.TryGetProperty(property, out var value)
            ? value.ToString()
            : null;

    private static int Missing(string what, string usage)
    {
        Error($"Missing {what}.");
        Console.WriteLine($"Usage: {usage}");
        return 1;
    }

    /// <summary>
    /// Server errors arrive as atoms like <c>:not_found</c>. Say what the developer should do.
    /// </summary>
    private static string Describe(Exception ex)
    {
        string message = ex.Message;

        if (message.Contains(":not_found"))
        {
            return "The cluster does not know that plugin. Check `exo plugin list`, or deploy it with `exo plugin push <name>`.";
        }

        if (message.Contains(":forbidden_scope") || message.Contains(":unauthorized"))
        {
            return $"Not allowed: {message}. Check the environment's token in exoforge.json — admin-scoped actions need an admin token.";
        }

        if (message.Contains("Unable to connect") || message.Contains("No connection"))
        {
            return "Could not reach the cluster. Is it running (`just dev`), and is the environment's ws_url correct?";
        }

        return message;
    }

    private static void Error(string message)
    {
        Console.ForegroundColor = ConsoleColor.Red;
        Console.WriteLine(message);
        Console.ResetColor();
    }

    private static void Success(string message)
    {
        Console.ForegroundColor = ConsoleColor.Green;
        Console.WriteLine(message);
        Console.ResetColor();
    }
}

/// <summary>
/// Position-independent argument parsing: <c>--rid linux-x64 foo</c> and <c>foo --rid linux-x64</c>
/// are the same, so flags can go wherever the developer types them.
/// </summary>
internal sealed class CliArgs
{
    private readonly Dictionary<string, string> _flags;

    private CliArgs(List<string> positional, Dictionary<string, string> flags)
    {
        Positional = positional;
        _flags = flags;
    }

    public IReadOnlyList<string> Positional { get; }

    public bool Json => Has("json");

    public bool WantsHelp => Has("help") || Has("h");

    public static CliArgs Parse(string[] args, int skip) => From(args.Skip(skip).ToList(), null);

    /// <summary>Re-parses the remaining positionals, carrying the parent's flags over.</summary>
    public static CliArgs From(List<string> tokens, CliArgs? parent)
    {
        var positional = new List<string>();
        var flags = parent == null
            ? new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
            : new Dictionary<string, string>(parent._flags, StringComparer.OrdinalIgnoreCase);

        for (int i = 0; i < tokens.Count; i++)
        {
            string token = tokens[i];

            if (token.Length > 1 && token[0] == '-')
            {
                string key = token.TrimStart('-');
                bool nextIsValue = i + 1 < tokens.Count && !(tokens[i + 1].Length > 1 && tokens[i + 1][0] == '-');
                flags[key] = nextIsValue ? tokens[++i] : "true";
            }
            else
            {
                positional.Add(token);
            }
        }

        return new CliArgs(positional, flags);
    }

    public bool Has(string flag) => _flags.ContainsKey(flag);

    public string? Value(string flag) => _flags.TryGetValue(flag, out var value) ? value : null;

    public int IntValue(string flag, int fallback) =>
        _flags.TryGetValue(flag, out var value) && int.TryParse(value, out int parsed) ? parsed : fallback;
}
