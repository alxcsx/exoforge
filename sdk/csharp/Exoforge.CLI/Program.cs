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

                case "extension":
                    return await HandleExtensionAsync(cli).ConfigureAwait(false);

                case "sync":
                case "gen":
                case "stubs":
                    return await HandleSyncAsync(cli).ConfigureAwait(false);

                case "repair":
                    return HandleRepair(cli);

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
          init                       Initialize the workspace and exoforge.json
          extension <subcommand>     Create, build, deploy and inspect extensions
          sync                       Download live contracts and generate the typed C# client
          stubs                      Alias for sync (updates C# client stubs)
          repair                     Sanitize and repair client stubs in-place
          status                     Inspect live cluster health and metrics

        Options:
          --dir <path>               Workspace root (defaults to the current directory)
          --env <environment>        Target environment from exoforge.json (default: 'local')
          --json                     Machine-readable output (extension list, logs, status)
          -h, --help                 Help for a command, e.g. `exo extension push --help`

        Run `exo extension --help` for the extension subcommands.
        """);
    }

    private static void PrintExtensionUsage()
    {
        Console.WriteLine("""
        Usage: exo extension <subcommand> [name] [options]

        Subcommands:
          new <name>       Scaffold a C# extension project
          build <name>     Compile the extension (framework-dependent .NET)
          push <name>      Build, deploy, and verify the extension on the live cluster
          dev <name>       Watch sources and re-deploy on every change
          reload <name>    Re-boot an installed extension without re-uploading it
          logs <name>      Show recent log lines the extension emitted
          usage [name]     Show metered usage (calls, CPU, memory) for an extension or the title
          stubs <name>     Generate typed service stubs from the contracts this extension calls
          list             List installed extensions
          remove <id>      Remove an extension from the cluster

        Common options:
          --dir <path>     Workspace root (defaults to the current directory)
          --env <name>     Target environment
          --json           Machine-readable output

        Run `exo extension <subcommand> --help` for the options of one subcommand.
        """);
    }

    // ---- init / sync / status ----------------------------------------------------------

    private static int HandleInit(CliArgs cli)
    {
        if (cli.WantsHelp)
        {
            Console.WriteLine("""
            Usage: exo init [--dir <path>] [--name <project_name>]

            Creates exoforge.json and the extensions/ directory.
            """);
            return 0;
        }

        string dir = cli.Value("dir") ?? Directory.GetCurrentDirectory();
        string name = cli.Value("name") ?? Path.GetFileName(Path.GetFullPath(dir));

        var ws = ExoWorkspace.Initialize(dir, name);
        Success($"[Exoforge] Initialized workspace at {ws.RootPath}");
        Console.WriteLine($"  Config:     {ws.ConfigPath}");
        Console.WriteLine($"  Extensions: {ws.ExtensionsPath}");
        Console.WriteLine($"  Client Gen: {ws.GeneratedPath}");
        Console.WriteLine();
        Console.WriteLine("Next: exo extension new <name>");
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

        Console.WriteLine("[Exoforge] Synchronizing backend contracts (cluster / workspace cache)...");
        int changed = await deployer.SyncContractsAsync(cli.Value("env"), outPath, emit: msg => Console.WriteLine($"[Exoforge] {msg}")).ConfigureAwait(false);
        if (changed > 0)
        {
            Success($"[Exoforge] Updated strongly-typed C# client bindings at:\n  {outPath ?? ws.GeneratedPath}");
        }
        else
        {
            Success($"[Exoforge] C# client bindings are already up-to-date at:\n  {outPath ?? ws.GeneratedPath}");
        }
        return 0;
    }

    private static int HandleRepair(CliArgs cli)
    {
        string dir = cli.Value("dir") ?? Directory.GetCurrentDirectory();
        string defaultPath = Path.Combine(dir, "Assets", "Exoforge", "Generated", "ExoforgeServices.g.cs");
        string targetPath = cli.Value("path") ?? (File.Exists(defaultPath) ? defaultPath : Path.Combine(dir, "Generated", "ExoforgeServices.g.cs"));

        if (!File.Exists(targetPath))
        {
            Error($"[Exoforge] Generated stub file not found at: {targetPath}");
            return 1;
        }

        string text = File.ReadAllText(targetPath);
        if (text.Contains("global::Exoforge.Client.Unity.ExoforgeSDK.Client") || text.Contains("#if UNITY_2018_1_OR_NEWER || UNITY_5_3_OR_NEWER"))
        {
            var lines = text.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.None);
            var filtered = new List<string>();
            bool insideBadBlock = false;
            foreach (var line in lines)
            {
                if (line.Contains("#if UNITY_2018_1_OR_NEWER || UNITY_5_3_OR_NEWER"))
                {
                    insideBadBlock = true;
                    continue;
                }
                if (insideBadBlock)
                {
                    if (line.Contains("#endif"))
                    {
                        insideBadBlock = false;
                    }
                    continue;
                }
                filtered.Add(line);
            }
            File.WriteAllText(targetPath, string.Join("\n", filtered), new System.Text.UTF8Encoding(false));
            Success($"[Exoforge] Successfully sanitized and repaired stubs in-place at:\n  {targetPath}");
        }
        else
        {
            Success($"[Exoforge] Stubs at {targetPath} are already clean.");
        }
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

    // ---- extension ---------------------------------------------------------------------

    private static async Task<int> HandleExtensionAsync(CliArgs cli)
    {
        if (cli.WantsHelp && cli.Positional.Count == 0)
        {
            PrintExtensionUsage();
            return 0;
        }

        if (cli.Positional.Count == 0)
        {
            Error("Missing extension subcommand.");
            Console.WriteLine();
            PrintExtensionUsage();
            return 1;
        }

        string sub = cli.Positional[0].ToLowerInvariant();

        // Everything after the subcommand, so `exo extension push foo --rid x` parses the same as
        // `exo extension push --rid x foo`.
        var rest = CliArgs.From(cli.Positional.Skip(1).ToList(), cli);

        switch (sub)
        {
            case "new":
                return HandleExtensionNew(rest);

            case "build":
                return HandleExtensionBuild(rest);

            case "push":
                return await HandleExtensionPushAsync(rest).ConfigureAwait(false);

            case "dev":
                return await HandleExtensionDevAsync(rest).ConfigureAwait(false);

            case "reload":
                return await HandleExtensionReloadAsync(rest).ConfigureAwait(false);

            case "logs":
                return await HandleExtensionLogsAsync(rest).ConfigureAwait(false);

            case "usage":
                return await HandleExtensionUsageAsync(rest).ConfigureAwait(false);

            case "stubs":
                return await HandleExtensionStubsAsync(rest).ConfigureAwait(false);

            case "list":
                return await HandleExtensionListAsync(rest).ConfigureAwait(false);

            case "remove":
                return await HandleExtensionRemoveAsync(rest).ConfigureAwait(false);

            default:
                Error($"Unknown extension subcommand: {sub}");
                Console.WriteLine();
                PrintExtensionUsage();
                return 1;
        }
    }

    private static int HandleExtensionNew(CliArgs cli)
    {
        if (cli.WantsHelp)
        {
            Console.WriteLine("""
            Usage: exo extension new <name> [--template standard] [--dir <path>]

            Scaffolds extensions/<name>/ with a src/ project, a solution, and a .gitignore. The project
            references the Exoforge.Plugin.SDK package, so it builds wherever it is put; run
            `just pack-sdk` to fill the local feed from a checkout.

              --template <t>   standard (default)
            """);
            return 0;
        }

        if (cli.Positional.Count == 0)
        {
            return Missing("extension name", "exo extension new <name>");
        }

        string raw = cli.Positional[0];
        string template = cli.Value("template") ?? "standard";

        var ws = ExoWorkspace.Load(cli.Value("dir") ?? Directory.GetCurrentDirectory());

        string id = ExoScaffolder.NormalizeExtensionName(raw);

        if (!string.Equals(raw, id, StringComparison.Ordinal))
        {
            Console.WriteLine($"[Exoforge] '{raw}' will be created as '{id}' (extension ids are lower_snake_case).");
        }

        string created = ExoScaffolder.ScaffoldExtension(ws.ExtensionsPath, raw, template: template);

        Success($"[Exoforge] Scaffolded C# extension '{id}' ({template}) at:\n  {created}");
        Console.WriteLine();
        Console.WriteLine("Next:");
        Console.WriteLine($"  1. Edit  {Path.Combine(created, "src", ExoScaffolder.ClassNameFor(id) + "Extension.cs")}");
        Console.WriteLine($"  2. Build  exo extension build {id}");
        Console.WriteLine($"  3. Deploy exo extension push {id}");
        return 0;
    }

    private static int HandleExtensionBuild(CliArgs cli)
    {
        if (cli.WantsHelp)
        {
            Console.WriteLine("""
            Usage: exo extension build <name> [--rid <rid>] [--dir <path>]

              --rid <rid>   Target runtime, e.g. linux-x64 (default: this machine)
            """);
            return 0;
        }

        if (cli.Positional.Count == 0)
        {
            return Missing("extension name", "exo extension build <name>");
        }

        var ws = ExoWorkspace.Load(cli.Value("dir") ?? Directory.GetCurrentDirectory());
        return Build(ws, cli.Positional[0], cli.Value("rid"));
    }

    private static async Task<int> HandleExtensionPushAsync(CliArgs cli)
    {
        if (cli.WantsHelp)
        {
            Console.WriteLine("""
            Usage: exo extension push <name> [--rid <rid>] [--env <name>] [--dir <path>] [--no-verify]

            Builds, uploads, and then confirms the cluster is actually running the new build.
            """);
            return 0;
        }

        if (cli.Positional.Count == 0)
        {
            return Missing("extension name", "exo extension push <name>");
        }

        string name = cli.Positional[0];
        var ws = ExoWorkspace.Load(cli.Value("dir") ?? Directory.GetCurrentDirectory());
        var deployer = new ExoDeployer(ws);
        string? env = cli.Value("env");

        return await BuildThenPushAsync(deployer, ws, name, cli.Value("rid"), env, verify: !cli.Has("no-verify"))
            .ConfigureAwait(false);
    }

    private static async Task<int> HandleExtensionDevAsync(CliArgs cli)
    {
        if (cli.WantsHelp)
        {
            Console.WriteLine("""
            Usage: exo extension dev <name> [--rid <rid>] [--env <name>] [--dir <path>]

            Builds, deploys, then watches the extension's sources and repeats on every change.
            Stop with Ctrl-C.
            """);
            return 0;
        }

        if (cli.Positional.Count == 0)
        {
            return Missing("extension name", "exo extension dev <name>");
        }

        string name = cli.Positional[0];
        var ws = ExoWorkspace.Load(cli.Value("dir") ?? Directory.GetCurrentDirectory());
        var deployer = new ExoDeployer(ws);
        string? env = cli.Value("env");
        string? rid = cli.Value("rid");

        string extensionDir = Path.Combine(ws.ExtensionsPath, ExoScaffolder.NormalizeExtensionName(name));
        if (!Directory.Exists(extensionDir))
        {
            string directDir = Path.Combine(ws.RootPath, ExoScaffolder.NormalizeExtensionName(name));
            if (Directory.Exists(directDir)) extensionDir = directDir;
            else
            {
                Error($"Extension directory not found: {extensionDir}");
                return 1;
            }
        }

        int first = await BuildThenPushAsync(deployer, ws, name, rid, env, verify: true).ConfigureAwait(false);
        if (first != 0)
        {
            Error("Initial build failed — fix it and the watcher will pick up the change.");
        }

        // Poll the source fingerprint rather than using FileSystemWatcher: it is the same hash the
        // build stamp uses, so "changed" means exactly "the build stamp would change", and it
        // behaves identically on every platform and filesystem.
        string last = ExoDeployer.ComputeSourceFingerprint(extensionDir);
        Console.WriteLine($"[Exoforge] Watching {extensionDir} (fingerprint {last}). Ctrl-C to stop.");

        while (true)
        {
            Thread.Sleep(1000);

            string current = ExoDeployer.ComputeSourceFingerprint(extensionDir);
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

    private static async Task<int> HandleExtensionReloadAsync(CliArgs cli)
    {
        if (cli.WantsHelp)
        {
            Console.WriteLine("""
            Usage: exo extension reload <name> [--env <name>] [--dir <path>]

            Re-boots an installed extension from the files already on the cluster — no rebuild,
            no re-upload. Use it after changing extension config, or to recover an extension that died.
            """);
            return 0;
        }

        if (cli.Positional.Count == 0)
        {
            return Missing("extension name", "exo extension reload <name>");
        }

        string name = ExoScaffolder.NormalizeExtensionName(cli.Positional[0]);
        var ws = ExoWorkspace.Load(cli.Value("dir") ?? Directory.GetCurrentDirectory());
        var deployer = new ExoDeployer(ws);

        Console.WriteLine($"[Exoforge] Reloading '{name}'…");

        JsonElement result;
        try
        {
            result = await deployer.ReloadExtensionAsync(name, cli.Value("env")).ConfigureAwait(false);
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

    private static async Task<int> HandleExtensionLogsAsync(CliArgs cli)
    {
        if (cli.WantsHelp)
        {
            Console.WriteLine("""
            Usage: exo extension logs <name> [--limit <n>] [--follow] [--json] [--env <name>]

              --limit <n>   How many recent lines to show (default 100)
              --follow      Keep printing new lines until Ctrl-C

            Lines are held in memory on the cluster and capped per extension, so this is
            "what did my extension just do?" rather than a permanent log store.
            """);
            return 0;
        }

        if (cli.Positional.Count == 0)
        {
            return Missing("extension name", "exo extension logs <name>");
        }

        string name = ExoScaffolder.NormalizeExtensionName(cli.Positional[0]);
        var ws = ExoWorkspace.Load(cli.Value("dir") ?? Directory.GetCurrentDirectory());
        var deployer = new ExoDeployer(ws);
        string? env = cli.Value("env");
        int limit = cli.IntValue("limit", 100);

        List<ExtensionLogLine> lines;
        try
        {
            lines = await deployer.GetExtensionLogsAsync(name, limit, env).ConfigureAwait(false);
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

            var fresh = await deployer.GetExtensionLogsAsync(name, limit, env).ConfigureAwait(false);
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

    private static async Task<int> HandleExtensionUsageAsync(CliArgs cli)
    {
        if (cli.WantsHelp)
        {
            Console.WriteLine("""
            Usage: exo extension usage [name] [--since <unix-seconds>] [--json] [--env <name>]

              Without a name, every extension the instance has metered.
              --since <n>   Only usage recorded at or after this Unix time.

            Counts, durations, bytes, CPU and peak RSS. Never payloads, and never player data.
            """);
            return 0;
        }

        string? name = cli.Positional.Count > 0
            ? ExoScaffolder.NormalizeExtensionName(cli.Positional[0])
            : null;

        long? since = null;
        if (cli.Value("since") is { } raw)
        {
            if (!long.TryParse(raw, out long parsed))
            {
                Error($"--since expects Unix seconds, got '{raw}'.");
                return 1;
            }

            since = parsed;
        }

        var ws = ExoWorkspace.Load(cli.Value("dir") ?? Directory.GetCurrentDirectory());
        var deployer = new ExoDeployer(ws);

        ExtensionUsageReport report;
        try
        {
            report = await deployer.GetExtensionUsageAsync(name, since, cli.Value("env")).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            Error(Describe(ex));
            return 1;
        }

        if (cli.Json)
        {
            Console.WriteLine(JsonSerializer.Serialize(report, JsonOptions));
        }
        else
        {
            PrintUsage(report);
        }

        return 0;
    }

    private static async Task<int> HandleExtensionStubsAsync(CliArgs cli)
    {
        if (cli.WantsHelp)
        {
            Console.WriteLine("""
            Usage: exo extension stubs <name> [--services a,b] [--out <path>] [--file <export.json>]

            Reads the cluster's contracts, and lays this workspace's own built extensions over them, so an
            extension that is built but not deployed still produces stubs. Without a cluster it uses what
            has been built locally.

            Generates typed stubs for the contracts this extension calls, so extension code does not
            hand-roll service and action names.
            """);
            return 0;
        }

        if (cli.Positional.Count == 0)
        {
            return Missing("extension name", "exo extension stubs <name>");
        }

        string name = ExoScaffolder.NormalizeExtensionName(cli.Positional[0]);
        var ws = ExoWorkspace.Load(cli.Value("dir") ?? Directory.GetCurrentDirectory());
        var deployer = new ExoDeployer(ws);

        string? contractsFile = cli.Value("file");
        string exportJson;

        if (!string.IsNullOrEmpty(contractsFile) && File.Exists(contractsFile))
        {
            exportJson = File.ReadAllText(contractsFile);
        }
        else
        {
            try
            {
                exportJson = await deployer.GetContractsExportJsonAsync(cli.Value("env")).ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                // No cluster to ask. Every extension that has been built has its contracts on disk beside
                // its manifest, which is the point: stubs for an extension that is built but not deployed.
                // Services that were neither built here nor deployed are simply absent.
                Console.WriteLine($"[Exoforge] No cluster ({ex.Message}) — generating from local contracts only.");
                exportJson = "{\"export\":{\"extensions\":[]}}";
            }
        }

        // Local contracts win over the cluster's, so an extension that is being edited generates stubs for
        // what it is now rather than for what was last deployed.
        exportJson = deployer.MergeLocalContracts(exportJson);

        string extensionDir = Path.Combine(ws.ExtensionsPath, name);
        string stubsOut = cli.Value("out") ?? Path.Combine(extensionDir, "src", "Generated", "PluginServices.g.cs");

        var deps = ExoDeployer.ReadManifestDependencies(extensionDir);
        string? servicesOption = cli.Value("services");
        IEnumerable<string>? services = servicesOption != null
            ? servicesOption.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            : (deps is { Count: > 0 } ? deps : ExoDeployer.AvailableServices(exportJson).Where(s => !string.Equals(s, name, StringComparison.OrdinalIgnoreCase)).ToList());

        var missing = ExoDeployer.MissingServices(exportJson, services);

        if (missing.Count > 0)
        {
            Error($"[Exoforge] No contracts for: {string.Join(", ", missing)}. Nothing was written — {stubsOut} still holds the last stubs that were generated. Start the cluster (`just dev`), or build the extension that provides them.");
            return 1;
        }

        ExoCodeGenerator.GeneratePluginStubsToFile(exportJson, stubsOut, services: services, pluginId: name);
        Success($"[Exoforge] Generated typed extension service stubs:\n  {stubsOut}");
        return 0;
    }

    private static async Task<int> HandleExtensionListAsync(CliArgs cli)
    {
        if (cli.WantsHelp)
        {
            Console.WriteLine("Usage: exo extension list [--json] [--env <name>] [--dir <path>]");
            return 0;
        }

        var ws = ExoWorkspace.Load(cli.Value("dir") ?? Directory.GetCurrentDirectory());
        var deployer = new ExoDeployer(ws);

        if (!cli.Json)
        {
            Console.WriteLine("[Exoforge] Fetching installed extensions from live cluster...");
        }

        var result = await deployer.ListExtensionsAsync(cli.Value("env")).ConfigureAwait(false);
        Console.WriteLine(PrettyJson(result));
        return 0;
    }

    private static async Task<int> HandleExtensionRemoveAsync(CliArgs cli)
    {
        if (cli.WantsHelp)
        {
            Console.WriteLine("""
            Usage: exo extension remove <id> [--yes] [--delete-files] [--env <name>] [--dir <path>]

              --yes             Skip the confirmation prompt (required when not interactive)
              --delete-files    Also delete the extension's staged files on the cluster
            """);
            return 0;
        }

        if (cli.Positional.Count == 0)
        {
            return Missing("extension id", "exo extension remove <id>");
        }

        string id = cli.Positional[0];

        // Removing an extension from a running cluster is not undoable by re-running a command.
        if (!cli.Has("yes"))
        {
            if (Console.IsInputRedirected)
            {
                Error($"Refusing to remove '{id}' without confirmation. Pass --yes.");
                return 1;
            }

            Console.Write($"[Exoforge] Remove extension '{id}' from the cluster? [y/N] ");
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

        await deployer.RemoveExtensionAsync(id, cli.Value("env"), deleteFiles: cli.Has("delete-files"))
            .ConfigureAwait(false);

        Success($"[Exoforge] Removed extension '{id}' from the cluster.");
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

        string cleanName = ExoScaffolder.NormalizeExtensionName(name);
        string extensionDir = Path.Combine(ws.ExtensionsPath, cleanName);
        string? builtVersion = ExoDeployer.ReadManifestVersion(extensionDir);

        Console.WriteLine($"[Exoforge] Uploading extension '{cleanName}' to live cluster...");
        string result = await deployer.UploadExtensionAsync(cleanName, env).ConfigureAwait(false);
        Success($"[Exoforge] Deployed '{cleanName}'.");
        Console.WriteLine($"  Server Response: {result}");

        if (!verify)
        {
            return 0;
        }

        // "installed" only means the files landed. Confirm the cluster is running the new build.
        var status = await deployer.VerifyExtensionAsync(cleanName, builtVersion, env).ConfigureAwait(false);

        if (status.IsHealthy)
        {
            Console.WriteLine($"  Verified: {status.Version} loaded ({status.Type}).");
            return 0;
        }

        Error($"[Exoforge] Deployed, but the cluster does not look healthy: {status.Detail}");
        Console.WriteLine($"  Check `exo extension logs {cleanName}`.");
        return 1;
    }

    private static int Build(ExoWorkspace ws, string rawName, string? ridOverride)
    {
        try
        {
            var build = new ExoDeployer(ws).BuildExtension(rawName, ridOverride, log: Console.WriteLine);
            Success($"[Exoforge] Build complete for extension '{build.Name}' ({build.ExtensionType}).");
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

    private static void PrintUsage(ExtensionUsageReport report)
    {
        Console.WriteLine($"Title {report.TitleId}  (studio {report.StudioId})");

        if (report.Extensions.Count == 0)
        {
            Console.WriteLine("(no usage recorded yet)");
            return;
        }

        foreach (var extension in report.Extensions)
        {
            long calls = extension.Actions.Sum(a => a.Invocations);
            long errors = extension.Actions.Sum(a => a.Errors);

            Console.WriteLine();
            Console.WriteLine(
                $"{extension.ExtensionId}  {calls} calls  {errors} errors  " +
                $"cpu {FormatDuration(extension.CpuMs)}  peak RSS {FormatBytes(extension.PeakRssKb * 1024L)}  " +
                $"up {FormatDuration(extension.UptimeMs)}  {extension.Events} events  " +
                $"{extension.HostCalls} host calls  {extension.Restarts} restarts");

            foreach (var action in extension.Actions)
            {
                Console.WriteLine(
                    $"  {action.Action,-24} {action.Invocations,8} calls  {action.Errors,5} errors  " +
                    $"avg {FormatMicros(action.AvgWallUs),8}  in {FormatBytes(action.BytesIn),8}  out {FormatBytes(action.BytesOut),8}");
            }
        }
    }

    private static string FormatDuration(long milliseconds) =>
        milliseconds < 1000 ? $"{milliseconds}ms" : $"{milliseconds / 1000.0:0.##}s";

    private static string FormatMicros(long microseconds) =>
        microseconds < 1000 ? $"{microseconds}us" : FormatDuration(microseconds / 1000);

    private static string FormatBytes(long bytes) =>
        bytes < 1024 ? $"{bytes}B"
        : bytes < 1024 * 1024 ? $"{bytes / 1024.0:0.#}KB"
        : $"{bytes / (1024.0 * 1024.0):0.#}MB";

    private static void PrintLogLines(List<ExtensionLogLine> lines)
    {
        if (lines.Count == 0)
        {
            Console.WriteLine("(no log lines recorded — the extension may not have run yet)");
            return;
        }

        foreach (var line in lines)
        {
            PrintLogLine(line);
        }
    }

    private static void PrintLogLine(ExtensionLogLine line)
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
            return "The cluster does not know that extension. Check `exo extension list`, or deploy it with `exo extension push <name>`.";
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
