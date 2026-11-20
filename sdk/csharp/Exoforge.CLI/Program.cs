using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;
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

        if (command is "version" or "--version" or "-v")
        {
            Console.WriteLine($"exo {GetCliVersion()}");
            return 0;
        }

        var cli = command == "unity"
            ? CliArgs.Parse(args, 2)
            : CliArgs.Parse(args, 1);

        try
        {
            switch (command)
            {
                case "init":
                    return HandleInit(cli);

                case "env":
                    return HandleEnv(cli);

                case "connect":
                    return await HandleConnectAsync(cli).ConfigureAwait(false);

                case "resource":
                    return await HandleResourceAsync(cli).ConfigureAwait(false);

                case "user":
                    return await HandleUserAsync(cli).ConfigureAwait(false);

                case "contracts":
                    return await HandleContractsAsync(cli).ConfigureAwait(false);

                case "call":
                    return await HandleCallAsync(cli).ConfigureAwait(false);

                case "db":
                    return await HandleDbAsync(cli).ConfigureAwait(false);

                case "agents":
                    return HandleAgents(cli);
                case "cli":
                    return HandleCli(cli);

                case "extension":
                    return await HandleExtensionAsync(cli).ConfigureAwait(false);

                case "unity":
                    return HandleUnity(cli, args);

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

    private static string GetCliVersion()
    {
        var asm = typeof(Program).Assembly;
        var info = (System.Reflection.AssemblyInformationalVersionAttribute?)Attribute.GetCustomAttribute(
            asm, typeof(System.Reflection.AssemblyInformationalVersionAttribute));
        string raw = info?.InformationalVersion ?? asm.GetName().Version?.ToString(3) ?? "0.1.40";
        int plus = raw.IndexOf('+');
        return plus > 0 ? raw[..plus] : raw;
    }

    private static void PrintUsage()
    {
        Console.WriteLine("""
        ===============================================================
               EXOFORGE DEVELOPER CLI (Non-Mix / C# SDK Tools)
        ===============================================================

        Usage: exo <command> [options]

        Commands:
          init                       Initialize the workspace and exoforge.json
          connect                    Verify connection to cluster or authenticate session
          env <subcommand>           Manage cluster environments in exoforge.json (list, add, use)
          extension <subcommand>     Create, build, deploy and inspect extensions
          resource <subcommand>      Manage resource tables and entities (list, get, create, etc.)
          user <subcommand>          Manage user and service accounts (list, create, role, token, delete)
          contracts                  Inspect available service contracts, actions and schemas
          call <service> <action>    Invoke an action directly over RPC
          sync                       Download live contracts and generate the typed C# client
          stubs                      Alias for sync (updates C# client stubs)
          agents <subcommand>        Install and inspect AI agent skills, AGENTS.md, and wrappers
          repair                     Sanitize and repair client stubs in-place
          status                     Inspect live cluster health and metrics
          unity records              Write IsExternalInit polyfill per assembly (--asmdef/--all)

        Options:
          --dir <path>               Workspace root (defaults to the current directory)
          --env <environment>        Target environment from exoforge.json (default: 'local')
          --json                     Machine-readable output (JSON)
          -h, --help                 Help for a command, e.g. `exo extension push --help`

        Run `exo <command> --help` for the options of one command.
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
              --include-studio Include studio/admin actions in the generated client bindings
            """);
            return 0;
        }

        string dir = cli.Value("dir") ?? Directory.GetCurrentDirectory();
        string? fileInput = cli.Value("file");
        string? outPath = cli.Value("out");
        bool includeStudio = cli.Has("include-studio");

        if (!string.IsNullOrEmpty(fileInput) && File.Exists(fileInput))
        {
            Console.WriteLine($"[Exoforge] Generating strongly-typed C# client bindings from '{fileInput}'...");
            string targetPath = outPath ?? Path.Combine(dir, "Generated", "ExoforgeServices.g.cs");
            ExoCodeGenerator.GenerateToFile(File.ReadAllText(fileInput), targetPath, includeStudio: includeStudio);
            Success($"[Exoforge] Generated strongly-typed C# client bindings at:\n  {targetPath}");
            return 0;
        }

        var ws = ExoWorkspace.Load(dir);
        var deployer = new ExoDeployer(ws);

        Console.WriteLine("[Exoforge] Synchronizing backend contracts (cluster / workspace cache)...");
        int changed = await deployer.SyncContractsAsync(
            cli.Value("env"),
            outPath,
            emit: msg => Console.WriteLine($"[Exoforge] {msg}"),
            includeStudio: includeStudio).ConfigureAwait(false);
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

    private static int HandleUnity(CliArgs cli, string[] args)
    {
        string sub = args.Length > 1 ? args[1].ToLowerInvariant() : "";
        if (sub != "records" || cli.WantsHelp)
        {
            Console.WriteLine("Usage: exo unity records [--asmdef <dir>] [--all] [--dir <path>]");
            return 0;
        }

        string dir = cli.Value("dir") ?? Directory.GetCurrentDirectory();
        string? asmdef = cli.Value("asmdef");
        bool all = cli.Has("all");

        if (!string.IsNullOrWhiteSpace(asmdef))
        {
            try
            {
                bool created = Exoforge.Management.ExoIsExternalInit.Ensure(dir, asmdef, out string path);
                Console.WriteLine(created ? $"Wrote {path}" : $"Skipped (already present): {path}");
                return 0;
            }
            catch (ArgumentException ex)
            {
                Console.Error.WriteLine(ex.Message);
                return 1;
            }
        }

        if (all)
        {
            foreach (string assembly in Exoforge.Management.ExoIsExternalInit.EnumerateAssemblies(dir))
            {
                if (!Exoforge.Management.ExoIsExternalInit.DeclaresRecordOrInit(dir, assembly))
                {
                    Console.WriteLine($"Skipped (no record/init): {assembly}");
                    continue;
                }
                if (Exoforge.Management.ExoIsExternalInit.FindInAssembly(dir, assembly) != null)
                {
                    Console.WriteLine($"Skipped (already present): {assembly}");
                    continue;
                }
                bool created = Exoforge.Management.ExoIsExternalInit.Ensure(dir, assembly, out string path);
                Console.WriteLine(created ? $"Wrote {path}" : $"Skipped (already present): {path}");
            }
            return 0;
        }

        Console.WriteLine("Usage: exo unity records [--asmdef <dir>] [--all] [--dir <path>]");
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

    private static string MaskToken(string? tok)
    {
        if (string.IsNullOrEmpty(tok)) return "(none)";
        if (tok.Length <= 8) return "******";
        return tok.Substring(0, 4) + "..." + tok.Substring(tok.Length - 4);
    }

    // ---- env ---------------------------------------------------------------------------

    private static int HandleEnv(CliArgs cli)
    {
        if (cli.WantsHelp && cli.Positional.Count == 0)
        {
            PrintEnvUsage();
            return 0;
        }

        if (cli.Positional.Count == 0)
        {
            Error("Missing env subcommand (list, add, use).");
            Console.WriteLine();
            PrintEnvUsage();
            return 1;
        }

        string sub = cli.Positional[0].ToLowerInvariant();
        var rest = CliArgs.From(cli.Positional.Skip(1).ToList(), cli);

        switch (sub)
        {
            case "list":
                return HandleEnvList(rest);
            case "add":
                return HandleEnvAdd(rest);
            case "use":
                return HandleEnvUse(rest);
            default:
                Error($"Unknown env subcommand: {sub}");
                Console.WriteLine();
                PrintEnvUsage();
                return 1;
        }
    }

    private static void PrintEnvUsage()
    {
        Console.WriteLine("""
        Usage: exo env <subcommand> [options]

        Subcommands:
          list                                          List all environments configured in exoforge.json
          add <name> --ws <url> --http <url> [options]  Add or update an environment
          use <name>                                    Set default active environment

        Options for 'add':
          --ws <url>        WebSocket cluster URL (e.g., ws://localhost:4000/ws)
          --http <url>      HTTP REST/OpenAPI base URL (e.g., http://localhost:4001)
          --token <tok>     Cluster authentication token
          --default         Mark this environment as default

        Common options:
          --dir <path>      Workspace directory (defaults to current directory)
          --json            Machine-readable JSON output
          -h, --help        Show command help
        """);
    }

    private static int HandleEnvList(CliArgs cli)
    {
        if (cli.WantsHelp)
        {
            Console.WriteLine("Usage: exo env list [--dir <path>] [--json]");
            return 0;
        }

        var ws = ExoWorkspace.Load(cli.Value("dir") ?? Directory.GetCurrentDirectory());

        if (cli.Json)
        {
            var envs = ws.Config.Environments.Select(kv => new
            {
                name = kv.Key,
                is_default = string.Equals(kv.Key, ws.Config.DefaultEnvironment, StringComparison.OrdinalIgnoreCase),
                ws_url = kv.Value.WsUrl,
                http_url = kv.Value.HttpUrl,
                token = MaskToken(kv.Value.Token)
            }).ToList();

            Console.WriteLine(JsonSerializer.Serialize(new
            {
                default_environment = ws.Config.DefaultEnvironment,
                environments = envs
            }, JsonOptions));
            return 0;
        }

        Console.WriteLine($"Environments in {ws.ConfigPath} (default: '{ws.Config.DefaultEnvironment}'):\n");
        foreach (var kv in ws.Config.Environments)
        {
            bool isDef = string.Equals(kv.Key, ws.Config.DefaultEnvironment, StringComparison.OrdinalIgnoreCase);
            string marker = isDef ? "* " : "  ";
            Console.WriteLine($"{marker}{kv.Key}{(isDef ? " (active)" : "")}");
            Console.WriteLine($"    WS:    {kv.Value.WsUrl}");
            Console.WriteLine($"    HTTP:  {kv.Value.HttpUrl}");
            Console.WriteLine($"    Token: {MaskToken(kv.Value.Token)}");
        }
        return 0;
    }

    private static int HandleEnvAdd(CliArgs cli)
    {
        if (cli.WantsHelp || cli.Positional.Count == 0)
        {
            Console.WriteLine("Usage: exo env add <name> --ws <url> --http <url> [--token <tok>] [--default] [--dir <path>] [--json]");
            return cli.WantsHelp ? 0 : 1;
        }

        string name = cli.Positional[0];
        string? wsUrl = cli.Value("ws");
        string? httpUrl = cli.Value("http");
        string? token = cli.Value("token");
        bool isDefault = cli.Has("default");

        if (string.IsNullOrEmpty(wsUrl))
        {
            return Missing("--ws URL", "exo env add <name> --ws <url> --http <url> [options]");
        }
        if (string.IsNullOrEmpty(httpUrl))
        {
            return Missing("--http URL", "exo env add <name> --ws <url> --http <url> [options]");
        }

        var ws = ExoWorkspace.Load(cli.Value("dir") ?? Directory.GetCurrentDirectory());
        ws.Config.Environments[name] = new ExoEnvironmentConfig
        {
            WsUrl = wsUrl,
            HttpUrl = httpUrl,
            Token = token ?? ""
        };

        if (isDefault || string.IsNullOrEmpty(ws.Config.DefaultEnvironment))
        {
            ws.Config.DefaultEnvironment = name;
        }

        ws.Save();

        var deployer = new ExoDeployer(ws);
        deployer.SyncRuntimeConfigIfUnityProject(ws.Config.DefaultEnvironment, ws.GetActiveEnvironment().WsUrl, ws.GetActiveEnvironment().HttpUrl);

        if (cli.Json)
        {
            Console.WriteLine(JsonSerializer.Serialize(new
            {
                status = "ok",
                environment = name,
                is_default = ws.Config.DefaultEnvironment == name,
                ws_url = wsUrl,
                http_url = httpUrl
            }, JsonOptions));
            return 0;
        }

        Success($"[Exoforge] Environment '{name}' saved in {ws.ConfigPath}");
        if (ws.Config.DefaultEnvironment == name)
        {
            Console.WriteLine("  Marked as default active environment.");
        }
        return 0;
    }

    private static int HandleEnvUse(CliArgs cli)
    {
        if (cli.WantsHelp || cli.Positional.Count == 0)
        {
            Console.WriteLine("Usage: exo env use <name> [--dir <path>] [--json]");
            return cli.WantsHelp ? 0 : 1;
        }

        string name = cli.Positional[0];
        var ws = ExoWorkspace.Load(cli.Value("dir") ?? Directory.GetCurrentDirectory());

        if (!ws.Config.Environments.TryGetValue(name, out var envConfig))
        {
            Error($"Environment '{name}' does not exist in exoforge.json.");
            Console.WriteLine("Run `exo env list` to see configured environments.");
            return 1;
        }

        ws.Config.DefaultEnvironment = name;
        ws.Save();

        var deployer = new ExoDeployer(ws);
        bool synced = deployer.SyncRuntimeConfigIfUnityProject(name, envConfig.WsUrl, envConfig.HttpUrl);

        if (cli.Json)
        {
            Console.WriteLine(JsonSerializer.Serialize(new
            {
                status = "ok",
                default_environment = name,
                runtime_config_synced = synced
            }, JsonOptions));
            return 0;
        }

        Success($"[Exoforge] Active environment set to '{name}'.");
        if (synced)
        {
            Console.WriteLine("  Synchronized Assets/Resources/exoforge.json with new endpoints.");
        }
        return 0;
    }

    // ---- connect -----------------------------------------------------------------------

    private static async Task<int> HandleConnectAsync(CliArgs cli)
    {
        if (cli.WantsHelp)
        {
            Console.WriteLine("""
            Usage: exo connect [options]

            Verifies cluster connectivity, validates credentials or performs login,
            and optionally updates exoforge.json and runtime config.

            Options:
              --env <name>       Target environment (defaults to default_environment)
              --ws <url>         Override WebSocket endpoint
              --http <url>       Override HTTP base endpoint
              --token <tok>      Cluster authentication token
              --email <email>    Login email (used with --password)
              --password <pass>  Login password (used with --email)
              --save             Save validated endpoints and the login session (access + refresh token) to exoforge.json
              --dir <path>       Workspace directory
              --json             Machine-readable JSON output
            """);
            return 0;
        }

        var ws = ExoWorkspace.Load(cli.Value("dir") ?? Directory.GetCurrentDirectory());
        var deployer = new ExoDeployer(ws);

        string? envName = cli.Value("env");
        string? wsUrl = cli.Value("ws");
        string? httpUrl = cli.Value("http");
        string? token = cli.Value("token");
        string? email = cli.Value("email");
        string? password = cli.Value("password");
        bool save = cli.Has("save");

        if (!cli.Json)
        {
            Console.WriteLine($"[Exoforge] Connecting to cluster ({envName ?? ws.Config.DefaultEnvironment})...");
        }

        var res = await deployer.ConnectAndVerifyAsync(
            environmentName: envName,
            wsUrlOverride: wsUrl,
            httpUrlOverride: httpUrl,
            tokenOverride: token,
            email: email,
            password: password,
            save: save
        ).ConfigureAwait(false);

        if (cli.Json)
        {
            Console.WriteLine(JsonSerializer.Serialize(res, JsonOptions));
            return 0;
        }

        Success("[Exoforge] Connected to cluster successfully!");
        Console.WriteLine($"  Environment:    {res.Environment}");
        Console.WriteLine($"  WebSocket URL:  {res.WsUrl}");
        Console.WriteLine($"  HTTP Base URL:  {res.HttpUrl}");
        Console.WriteLine($"  Authenticated:  {(res.Authenticated ? "Yes" : "No")}");
        Console.WriteLine($"  Settings Saved: {(save ? "Yes" : "No (pass --save to persist)")}");
        if (res.Status.ValueKind == JsonValueKind.Object)
        {
            string? clusterName = ReadString(res.Status, "cluster");
            if (!string.IsNullOrEmpty(clusterName))
            {
                Console.WriteLine($"  Cluster Node:   {clusterName}");
            }
        }
        return 0;
    }

    // ---- resource ----------------------------------------------------------------------

    private static async Task<int> HandleResourceAsync(CliArgs cli)
    {
        if (cli.WantsHelp && cli.Positional.Count == 0)
        {
            PrintResourceUsage();
            return 0;
        }

        if (cli.Positional.Count == 0)
        {
            Error("Missing resource subcommand.");
            Console.WriteLine();
            PrintResourceUsage();
            return 1;
        }

        string sub = cli.Positional[0].ToLowerInvariant();
        var rest = CliArgs.From(cli.Positional.Skip(1).ToList(), cli);

        var ws = ExoWorkspace.Load(cli.Value("dir") ?? Directory.GetCurrentDirectory());
        var deployer = new ExoDeployer(ws);
        string? env = cli.Value("env");

        switch (sub)
        {
            case "tables":
                return await HandleResourceTablesAsync(deployer, rest, env).ConfigureAwait(false);

            case "list":
                return await HandleResourceListAsync(deployer, rest, env).ConfigureAwait(false);

            case "get":
                return await HandleResourceGetAsync(deployer, rest, env).ConfigureAwait(false);

            case "create":
                return await HandleResourceCreateAsync(deployer, rest, env).ConfigureAwait(false);

            case "update":
                return await HandleResourceUpdateAsync(deployer, rest, env).ConfigureAwait(false);

            case "upsert":
                return await HandleResourceUpsertAsync(deployer, rest, env).ConfigureAwait(false);

            case "delete":
                return await HandleResourceDeleteAsync(deployer, rest, env).ConfigureAwait(false);

            case "clear":
                return await HandleResourceClearAsync(deployer, rest, env).ConfigureAwait(false);

            case "migrate":
                return await HandleResourceMigrateAsync(deployer, rest, env).ConfigureAwait(false);

            default:
                Error($"Unknown resource subcommand: {sub}");
                Console.WriteLine();
                PrintResourceUsage();
                return 1;
        }
    }

    private static void PrintResourceUsage()
    {
        Console.WriteLine("""
        Usage: exo resource <subcommand> [options]

        Subcommands:
          tables                                  List all resource tables discovered in contracts
          list <table> [options]                  Query rows from a resource table
          get <table> <id>                        Fetch a single row by primary key
          create <table> --data <json>            Insert a new record
          update <table> <id> --data <json>       Update an existing record
          upsert <table> --data <json>            Insert or update record
          delete <table> <id>                     Delete a record
          clear <table> --yes                     Delete all records from table (requires --yes)
          migrate [<table>]                       Reconcile database schemas for resource(s)

        Options for 'list':
          --limit <n>     Max rows to return (default: 20)
          --offset <n>    Offset pagination (default: 0)
          --search <q>    Search query filter

        Common options:
          --dir <path>    Workspace root
          --env <name>    Target environment
          --json          Machine-readable JSON output
          -h, --help      Command help
        """);
    }

    private static async Task<int> HandleResourceTablesAsync(ExoDeployer deployer, CliArgs cli, string? env)
    {
        if (cli.WantsHelp)
        {
            Console.WriteLine("Usage: exo resource tables [--dir <path>] [--env <name>] [--json]");
            return 0;
        }

        var tables = await deployer.ListResourceTablesAsync(env).ConfigureAwait(false);

        if (cli.Json)
        {
            Console.WriteLine(JsonSerializer.Serialize(new { tables }, JsonOptions));
            return 0;
        }

        if (tables.Count == 0)
        {
            Console.WriteLine("No resource tables discovered.");
            return 0;
        }

        Console.WriteLine($"{"Table",-24} {"Service",-20} {"PK",-8} {"Singleton",-10} Columns");
        Console.WriteLine(new string('-', 85));
        foreach (var t in tables)
        {
            string cols = string.Join(", ", t.Columns.Select(c => $"{c.Name}:{c.Type}"));
            Console.WriteLine($"{t.Name,-24} {t.Service,-20} {t.PrimaryKey,-8} {(t.Singleton ? "true" : "false"),-10} {cols}");
        }
        return 0;
    }

    private static async Task<int> HandleResourceListAsync(ExoDeployer deployer, CliArgs cli, string? env)
    {
        if (cli.WantsHelp || cli.Positional.Count == 0)
        {
            Console.WriteLine("Usage: exo resource list <table> [--limit <n>] [--offset <n>] [--search <q>] [--env <name>] [--json]");
            return cli.WantsHelp ? 0 : 1;
        }

        string table = cli.Positional[0];
        int? limit = cli.Has("limit") ? cli.IntValue("limit", 20) : null;
        int? offset = cli.Has("offset") ? cli.IntValue("offset", 0) : null;
        string? search = cli.Value("search");

        var res = await deployer.CallResourceStoreAsync("list", table, limit: limit, offset: offset, search: search, environmentName: env).ConfigureAwait(false);
        Console.WriteLine(PrettyJson(res));
        return 0;
    }

    private static async Task<int> HandleResourceGetAsync(ExoDeployer deployer, CliArgs cli, string? env)
    {
        if (cli.WantsHelp || cli.Positional.Count == 0)
        {
            Console.WriteLine("Usage: exo resource get <table> [id] [--env <name>] [--json]");
            return cli.WantsHelp ? 0 : 1;
        }

        string table = cli.Positional[0];
        string? id = cli.Positional.Count > 1 ? cli.Positional[1] : null;

        var res = await deployer.CallResourceStoreAsync("get", table, id: id, environmentName: env).ConfigureAwait(false);
        Console.WriteLine(PrettyJson(res));
        return 0;
    }

    private static async Task<int> HandleResourceCreateAsync(ExoDeployer deployer, CliArgs cli, string? env)
    {
        if (cli.WantsHelp || cli.Positional.Count == 0)
        {
            Console.WriteLine("Usage: exo resource create <table> --data <json> [--env <name>] [--json]");
            return cli.WantsHelp ? 0 : 1;
        }

        string table = cli.Positional[0];
        string? dataStr = cli.Value("data");
        if (string.IsNullOrEmpty(dataStr))
        {
            return Missing("--data '<json>'", "exo resource create <table> --data '<json>'");
        }

        JsonObject? data;
        try
        {
            data = JsonNode.Parse(dataStr)?.AsObject();
        }
        catch (Exception ex)
        {
            Error($"Invalid JSON in --data: {ex.Message}");
            return 1;
        }

        var res = await deployer.CallResourceStoreAsync("create", table, attributes: data, environmentName: env).ConfigureAwait(false);
        Console.WriteLine(PrettyJson(res));
        return 0;
    }

    private static async Task<int> HandleResourceUpdateAsync(ExoDeployer deployer, CliArgs cli, string? env)
    {
        if (cli.WantsHelp || cli.Positional.Count < 2)
        {
            Console.WriteLine("Usage: exo resource update <table> <id> --data <json> [--env <name>] [--json]");
            return cli.WantsHelp ? 0 : 1;
        }

        string table = cli.Positional[0];
        string id = cli.Positional[1];
        string? dataStr = cli.Value("data");
        if (string.IsNullOrEmpty(dataStr))
        {
            return Missing("--data '<json>'", "exo resource update <table> <id> --data '<json>'");
        }

        JsonObject? data;
        try
        {
            data = JsonNode.Parse(dataStr)?.AsObject();
        }
        catch (Exception ex)
        {
            Error($"Invalid JSON in --data: {ex.Message}");
            return 1;
        }

        var res = await deployer.CallResourceStoreAsync("update", table, id: id, attributes: data, environmentName: env).ConfigureAwait(false);
        Console.WriteLine(PrettyJson(res));
        return 0;
    }

    private static async Task<int> HandleResourceUpsertAsync(ExoDeployer deployer, CliArgs cli, string? env)
    {
        if (cli.WantsHelp || cli.Positional.Count == 0)
        {
            Console.WriteLine("Usage: exo resource upsert <table> --data <json> [--env <name>] [--json]");
            return cli.WantsHelp ? 0 : 1;
        }

        string table = cli.Positional[0];
        string? dataStr = cli.Value("data");
        if (string.IsNullOrEmpty(dataStr))
        {
            return Missing("--data '<json>'", "exo resource upsert <table> --data '<json>'");
        }

        JsonObject? data;
        try
        {
            data = JsonNode.Parse(dataStr)?.AsObject();
        }
        catch (Exception ex)
        {
            Error($"Invalid JSON in --data: {ex.Message}");
            return 1;
        }

        var res = await deployer.CallResourceStoreAsync("upsert", table, attributes: data, environmentName: env).ConfigureAwait(false);
        Console.WriteLine(PrettyJson(res));
        return 0;
    }

    private static async Task<int> HandleResourceDeleteAsync(ExoDeployer deployer, CliArgs cli, string? env)
    {
        if (cli.WantsHelp || cli.Positional.Count < 2)
        {
            Console.WriteLine("Usage: exo resource delete <table> <id> [--env <name>] [--json]");
            return cli.WantsHelp ? 0 : 1;
        }

        string table = cli.Positional[0];
        string id = cli.Positional[1];

        var res = await deployer.CallResourceStoreAsync("delete", table, id: id, environmentName: env).ConfigureAwait(false);
        Console.WriteLine(PrettyJson(res));
        return 0;
    }

    private static async Task<int> HandleResourceClearAsync(ExoDeployer deployer, CliArgs cli, string? env)
    {
        if (cli.WantsHelp || cli.Positional.Count == 0)
        {
            Console.WriteLine("Usage: exo resource clear <table> --yes [--env <name>] [--json]");
            return cli.WantsHelp ? 0 : 1;
        }

        string table = cli.Positional[0];
        if (!cli.Has("yes"))
        {
            Error($"Clearing table '{table}' will delete all its rows permanently. Pass --yes to confirm.");
            return 1;
        }

        var res = await deployer.CallResourceStoreAsync("clear", table, environmentName: env).ConfigureAwait(false);
        Console.WriteLine(PrettyJson(res));
        return 0;
    }

    private static async Task<int> HandleResourceMigrateAsync(ExoDeployer deployer, CliArgs cli, string? env)
    {
        if (cli.WantsHelp)
        {
            Console.WriteLine("Usage: exo resource migrate [<table>] [--env <name>] [--json]");
            return 0;
        }

        string? table = cli.Positional.Count > 0 ? cli.Positional[0] : null;

        var res = await deployer.CallResourceStoreAsync("migrate", table, environmentName: env).ConfigureAwait(false);
        Console.WriteLine(PrettyJson(res));
        return 0;
    }

    // ---- contracts ---------------------------------------------------------------------

    private static async Task<int> HandleContractsAsync(CliArgs cli)
    {
        if (cli.WantsHelp)
        {
            Console.WriteLine("""
            Usage: exo contracts [options]

            Displays services, actions, events, and resources declared across cluster and local contracts.

            Options:
              --service <name>   Filter by service name
              --dir <path>       Workspace root
              --env <name>       Target environment
              --json             Machine-readable JSON output
            """);
            return 0;
        }

        var ws = ExoWorkspace.Load(cli.Value("dir") ?? Directory.GetCurrentDirectory());
        var deployer = new ExoDeployer(ws);
        string? serviceFilter = cli.Value("service");

        var contractsDoc = await deployer.GetContractsExportAsync(cli.Value("env")).ConfigureAwait(false);

        if (cli.Json)
        {
            if (!string.IsNullOrEmpty(serviceFilter))
            {
                var filtered = FilterContractsByService(contractsDoc, serviceFilter);
                Console.WriteLine(PrettyJson(filtered));
            }
            else
            {
                Console.WriteLine(PrettyJson(contractsDoc));
            }
            return 0;
        }

        PrintContractsSummary(contractsDoc, serviceFilter);
        return 0;
    }

    private static JsonElement FilterContractsByService(JsonElement root, string serviceName)
    {
        JsonElement exportRoot = root;
        if (root.ValueKind == JsonValueKind.Object && root.TryGetProperty("export", out var expProp))
        {
            exportRoot = expProp;
        }

        JsonElement extensions = default;
        bool hasExts = false;
        if (exportRoot.ValueKind == JsonValueKind.Object)
        {
            if (exportRoot.TryGetProperty("extensions", out var exts) && exts.ValueKind == JsonValueKind.Array)
            {
                extensions = exts;
                hasExts = true;
            }
            else if (exportRoot.TryGetProperty("plugins", out var plgs) && plgs.ValueKind == JsonValueKind.Array)
            {
                extensions = plgs;
                hasExts = true;
            }
        }

        if (hasExts)
        {
            foreach (var ext in extensions.EnumerateArray())
            {
                if (ext.TryGetProperty("services", out var services) && services.ValueKind == JsonValueKind.Array)
                {
                    foreach (var svc in services.EnumerateArray())
                    {
                        string name = svc.TryGetProperty("name", out var np) ? np.GetString() ?? "" : "";
                        if (string.Equals(name, serviceName, StringComparison.OrdinalIgnoreCase))
                        {
                            return svc.Clone();
                        }
                    }
                }

                string extId = ext.TryGetProperty("id", out var idProp) ? idProp.GetString() ?? "" : "";
                string extName = ext.TryGetProperty("name", out var nProp) ? nProp.GetString() ?? extId : extId;
                if (string.Equals(extId, serviceName, StringComparison.OrdinalIgnoreCase) ||
                    string.Equals(extName, serviceName, StringComparison.OrdinalIgnoreCase))
                {
                    return ext.Clone();
                }
            }
        }

        return root;
    }

    private static void PrintContractsSummary(JsonElement root, string? serviceFilter)
    {
        JsonElement exportRoot = root;
        if (root.ValueKind == JsonValueKind.Object && root.TryGetProperty("export", out var expProp))
        {
            exportRoot = expProp;
        }

        JsonElement extensions = default;
        bool hasExts = false;
        if (exportRoot.ValueKind == JsonValueKind.Object)
        {
            if (exportRoot.TryGetProperty("extensions", out var exts) && exts.ValueKind == JsonValueKind.Array)
            {
                extensions = exts;
                hasExts = true;
            }
            else if (exportRoot.TryGetProperty("plugins", out var plgs) && plgs.ValueKind == JsonValueKind.Array)
            {
                extensions = plgs;
                hasExts = true;
            }
        }

        if (!hasExts)
        {
            Console.WriteLine("No extensions or services found in contracts export.");
            return;
        }

        int count = 0;
        foreach (var ext in extensions.EnumerateArray())
        {
            string extId = ext.TryGetProperty("id", out var idProp) ? idProp.GetString() ?? "" : "";
            string extName = ext.TryGetProperty("name", out var nProp) ? nProp.GetString() ?? extId : extId;
            string title = ext.TryGetProperty("title", out var tProp) ? tProp.GetString() ?? extName : extName;
            string category = ext.TryGetProperty("category", out var cProp) ? cProp.GetString() ?? "General" : "General";

            if (ext.TryGetProperty("services", out var services) && services.ValueKind == JsonValueKind.Array)
            {
                foreach (var svc in services.EnumerateArray())
                {
                    string svcName = svc.TryGetProperty("name", out var np) ? np.GetString() ?? extName : extName;
                    if (!string.IsNullOrEmpty(serviceFilter) && !string.Equals(svcName, serviceFilter, StringComparison.OrdinalIgnoreCase))
                    {
                        continue;
                    }

                    count++;
                    Console.WriteLine($"Service: {svcName}  [{category}] ({title})");

                    if (svc.TryGetProperty("actions", out var actions) && actions.ValueKind == JsonValueKind.Array)
                    {
                        Console.WriteLine("  Actions:");
                        foreach (var act in actions.EnumerateArray())
                        {
                            string actName = act.TryGetProperty("name", out var an) ? an.GetString() ?? "" : "";
                            string scope = act.TryGetProperty("scope", out var sc) ? sc.GetString() ?? "player" : "player";
                            Console.WriteLine($"    - {actName,-24} (scope: {scope})");
                        }
                    }

                    if (svc.TryGetProperty("events", out var evts) && evts.ValueKind == JsonValueKind.Array)
                    {
                        Console.WriteLine("  Events:");
                        foreach (var evt in evts.EnumerateArray())
                        {
                            string evtName = evt.TryGetProperty("name", out var en) ? en.GetString() ?? "" : "";
                            Console.WriteLine($"    - {evtName}");
                        }
                    }

                    if (svc.TryGetProperty("resources", out var resArr) && resArr.ValueKind == JsonValueKind.Array)
                    {
                        Console.WriteLine("  Resources:");
                        foreach (var res in resArr.EnumerateArray())
                        {
                            string rn = res.TryGetProperty("name", out var rnp) ? rnp.GetString() ?? "" : "";
                            string pk = res.TryGetProperty("primary_key", out var pkp) ? pkp.GetString() ?? "id" : "id";
                            Console.WriteLine($"    - {rn} (primary key: {pk})");
                        }
                    }

                    Console.WriteLine();
                }
            }
        }

        if (count == 0)
        {
            if (!string.IsNullOrEmpty(serviceFilter))
                Console.WriteLine($"Service '{serviceFilter}' not found in contracts.");
            else
                Console.WriteLine("No services found in contracts.");
        }
    }

    // ---- call --------------------------------------------------------------------------

    private static async Task<int> HandleCallAsync(CliArgs cli)
    {
        if (cli.WantsHelp || cli.Positional.Count < 2)
        {
            Console.WriteLine("""
            Usage: exo call <service> <action> [--data <json>] [options]

            Executes an action directly on the active cluster over RPC.

            Options:
              --data <json>      Payload parameters as JSON object
              --dir <path>       Workspace directory
              --env <name>       Target environment
              --json             Format response as JSON (default: true)
            """);
            return cli.WantsHelp ? 0 : 1;
        }

        string service = cli.Positional[0];
        string action = cli.Positional[1];

        JsonObject? payload = null;
        string? dataStr = cli.Value("data");
        if (!string.IsNullOrEmpty(dataStr))
        {
            try
            {
                payload = JsonNode.Parse(dataStr)?.AsObject();
            }
            catch (Exception ex)
            {
                Error($"Invalid JSON passed to --data: {ex.Message}");
                return 1;
            }
        }

        var ws = ExoWorkspace.Load(cli.Value("dir") ?? Directory.GetCurrentDirectory());
        var deployer = new ExoDeployer(ws);

        var result = await deployer.CallActionAsync(service, action, payload, cli.Value("env")).ConfigureAwait(false);
        Console.WriteLine(PrettyJson(result));
        return 0;
    }

    // ---- db ----------------------------------------------------------------------------

    private static async Task<int> HandleDbAsync(CliArgs cli)
    {
        if (cli.WantsHelp || cli.Positional.Count < 2 || cli.Positional[0] != "migrate")
        {
            Console.WriteLine("""
            Usage: exo db migrate <extension> [options]

            Applies the SQL migrations of a table you keep in line yourself (SchemaVersioningMode.Manual).
            They are the files of the extension's migrations/ folder, named 0007_what_it_does.sql: the
            number is the version, they apply in order, and the ones the server has already applied are
            skipped, so running it twice does nothing. Each file runs in its own transaction.

            Options:
              --dir <path>       Workspace directory
              --env <name>       Target environment
              --path <folder>    The migrations folder (default: <extensions>/<extension>/migrations)
            """);
            return cli.WantsHelp ? 0 : 1;
        }

        string extension = cli.Positional[1];
        var ws = ExoWorkspace.Load(cli.Value("dir") ?? Directory.GetCurrentDirectory());
        string folder = cli.Value("path") ?? Path.Combine(ws.ExtensionsPath, extension, "migrations");

        IReadOnlyList<ExoMigrations.Migration> migrations;
        try
        {
            migrations = ExoMigrations.Load(folder);
        }
        catch (Exception ex) when (ex is ArgumentException or DirectoryNotFoundException)
        {
            Error(ex.Message);
            return 1;
        }

        var deployer = new ExoDeployer(ws);
        var result = await deployer.CallActionAsync("lldb", "run_migrations", ExoMigrations.ToPayload(extension, migrations), cli.Value("env")).ConfigureAwait(false);
        Console.WriteLine(PrettyJson(result));
        return 0;
    }

    // ---- user --------------------------------------------------------------------------

    private static void PrintUserUsage()
    {
        Console.WriteLine("""
        Usage: exo user <subcommand> [options]

        Manages user accounts with the saved admin session of the environment. A service account
        for a trusted game server is an ordinary account with the 'service' role.

        Subcommands:
          list [--search <s>] [--limit <n>]                       List accounts and their roles
          create <email> --password <p> [--name <n>] [--role r]   Create an account (role default: player)
          role <user_id> --role <r>                               Change an account's role
          token <user_id> [--expires 30d]                         Issue a service token (default term: 90d)
          token --revoke <token_id>                               Revoke a token by id
          tokens <user_id>                                        List an account's tokens
          delete <user_id>                                        Delete an account

        Roles: player, studio, service, admin

        Common options:
          --dir <path>     Workspace root (defaults to the current directory)
          --env <name>     Target environment
          --json           Machine-readable output
        """);
    }

    private static async Task<int> HandleUserAsync(CliArgs cli)
    {
        if (cli.WantsHelp && cli.Positional.Count == 0)
        {
            PrintUserUsage();
            return 0;
        }

        if (cli.Positional.Count == 0)
        {
            Error("Missing user subcommand.");
            Console.WriteLine();
            PrintUserUsage();
            return 1;
        }

        string sub = cli.Positional[0].ToLowerInvariant();
        var rest = CliArgs.From(cli.Positional.Skip(1).ToList(), cli);

        if (rest.WantsHelp)
        {
            PrintUserUsage();
            return 0;
        }

        var ws = ExoWorkspace.Load(cli.Value("dir") ?? Directory.GetCurrentDirectory());
        var deployer = new ExoDeployer(ws);
        string? env = cli.Value("env");

        try
        {
            switch (sub)
            {
                case "list":
                    return await HandleUserListAsync(deployer, rest, env).ConfigureAwait(false);

                case "create":
                    return await HandleUserCreateAsync(deployer, rest, env).ConfigureAwait(false);

                case "role":
                    return await HandleUserRoleAsync(deployer, rest, env).ConfigureAwait(false);

                case "token":
                    return await HandleUserTokenAsync(deployer, rest, env).ConfigureAwait(false);

                case "tokens":
                    return await HandleUserTokensAsync(deployer, rest, env).ConfigureAwait(false);

                case "delete":
                    return await HandleUserDeleteAsync(deployer, rest, env).ConfigureAwait(false);

                default:
                    Error($"Unknown user subcommand: {sub}");
                    Console.WriteLine();
                    PrintUserUsage();
                    return 1;
            }
        }
        catch (ArgumentException ex)
        {
            Error(ex.Message);
            return 1;
        }
    }

    private static async Task<int> HandleUserListAsync(ExoDeployer deployer, CliArgs cli, string? env)
    {
        int? limit = cli.Has("limit") ? cli.IntValue("limit", 20) : null;
        var res = await ExoUsers.ListAsync(deployer, cli.Value("search"), limit, env).ConfigureAwait(false);

        if (cli.Json)
        {
            Console.WriteLine(PrettyJson(res));
            return 0;
        }

        foreach (var user in res.TryGetProperty("users", out var users) ? users.EnumerateArray() : Enumerable.Empty<JsonElement>())
        {
            string scopes = user.TryGetProperty("scopes", out var s) && s.ValueKind == JsonValueKind.Array
                ? string.Join(",", s.EnumerateArray().Select(x => x.ToString()))
                : "";
            Console.WriteLine($"{ReadString(user, "user_id"),-24} {ReadString(user, "email"),-32} {ExoUsers.RoleOf(scopes)}");
        }

        Console.WriteLine($"{(res.TryGetProperty("count", out var count) ? count.ToString() : "?")} account(s)");
        return 0;
    }

    private static async Task<int> HandleUserCreateAsync(ExoDeployer deployer, CliArgs cli, string? env)
    {
        if (cli.Positional.Count == 0)
        {
            return Missing("email", "exo user create <email> --password <p> [--name <n>] [--role player|studio|service|admin]");
        }

        string role = ExoUsers.NormalizeRole(cli.Value("role"));
        var res = await ExoUsers.CreateAsync(deployer, cli.Positional[0], cli.Value("password") ?? "", cli.Value("name"), role, env).ConfigureAwait(false);

        // The register reply carries a token; `exo user token` is the one place a token is printed.
        string userId = ReadString(res, "user_id") ?? "";
        if (cli.Json)
        {
            Console.WriteLine(new JsonObject { ["user_id"] = userId, ["email"] = cli.Positional[0], ["role"] = role }.ToJsonString(JsonOptions));
            return 0;
        }

        Success($"Created {cli.Positional[0]} ({userId}) with role {role}.");
        return 0;
    }

    private static async Task<int> HandleUserRoleAsync(ExoDeployer deployer, CliArgs cli, string? env)
    {
        if (cli.Positional.Count == 0)
        {
            return Missing("user id", "exo user role <user_id> --role <player|studio|service|admin>");
        }

        var res = await ExoUsers.SetRoleAsync(deployer, cli.Positional[0], cli.Value("role"), env).ConfigureAwait(false);
        if (cli.Json)
        {
            Console.WriteLine(PrettyJson(res));
            return 0;
        }

        Success($"{cli.Positional[0]} is now {ExoUsers.NormalizeRole(cli.Value("role"))}. Tokens issued before this keep working with the new scopes.");
        return 0;
    }

    private static async Task<int> HandleUserTokenAsync(ExoDeployer deployer, CliArgs cli, string? env)
    {
        // `exo user token --revoke <token_id>` is the same command: a token is issued, and a token
        // is taken away.
        string? revokeId = cli.Value("revoke");

        if (revokeId is not null)
        {
            var revoked = await ExoUsers.RevokeTokenAsync(deployer, revokeId, env).ConfigureAwait(false);

            if (cli.Json)
            {
                Console.WriteLine(PrettyJson(revoked));
                return 0;
            }

            Success($"Revoked token {revokeId}. Every client holding it is signed out.");
            return 0;
        }

        if (cli.Positional.Count == 0)
        {
            return Missing("user id", "exo user token <user_id> [--expires 30d]");
        }

        int? expiresIn = cli.Has("expires") ? ExoUsers.ParseExpiry(cli.Value("expires")) : null;

        var res = await ExoUsers.IssueTokenAsync(deployer, cli.Positional[0], expiresIn, env).ConfigureAwait(false);
        string token = ReadString(res, "token") ?? "";

        if (cli.Json)
        {
            Console.WriteLine(PrettyJson(res));
            return 0;
        }

        Console.WriteLine(token);

        string expiresAt = ReadString(res, "expires_at") ?? "";
        Console.Error.WriteLine(
            $"This token is a credential: it acts as the account until it expires ({expiresAt}) or is revoked " +
            "(`exo user token --revoke <token_id>`). Keep it out of version control.");

        return 0;
    }

    private static async Task<int> HandleUserTokensAsync(ExoDeployer deployer, CliArgs cli, string? env)
    {
        if (cli.Positional.Count == 0)
        {
            return Missing("user id", "exo user tokens <user_id>");
        }

        var res = await ExoUsers.ListTokensAsync(deployer, cli.Positional[0], env).ConfigureAwait(false);

        if (cli.Json)
        {
            Console.WriteLine(PrettyJson(res));
            return 0;
        }

        foreach (var token in res.TryGetProperty("tokens", out var tokens) ? tokens.EnumerateArray() : Enumerable.Empty<JsonElement>())
        {
            string revokedAt = ReadString(token, "revoked_at") ?? "";
            string state = revokedAt.Length > 0 ? "revoked" : "live";

            Console.WriteLine(
                $"{ReadString(token, "token_id"),-18} {ReadString(token, "kind"),-7} " +
                $"created {ReadString(token, "created_at"),-26} last used {ReadString(token, "last_used_at") ?? "-",-26} " +
                $"expires {ReadString(token, "expires_at"),-26} {state}");
        }

        Console.WriteLine($"{(res.TryGetProperty("count", out var count) ? count.ToString() : "?")} token(s)");
        return 0;
    }

    private static async Task<int> HandleUserDeleteAsync(ExoDeployer deployer, CliArgs cli, string? env)
    {
        if (cli.Positional.Count == 0)
        {
            return Missing("user id", "exo user delete <user_id>");
        }

        var res = await ExoUsers.DeleteAsync(deployer, cli.Positional[0], env).ConfigureAwait(false);
        if (cli.Json)
        {
            Console.WriteLine(PrettyJson(res));
            return 0;
        }

        Success($"Deleted {cli.Positional[0]}.");
        return 0;
    }

    // ---- agents ------------------------------------------------------------------------

    private static int HandleCli(CliArgs cli)
    {
        if (cli.Positional.Count == 0)
        {
            Error("Missing cli subcommand (install, status).");
            return 1;
        }
        string sub = cli.Positional[0].ToLowerInvariant();
        var rest = CliArgs.From(cli.Positional.Skip(1).ToList(), cli);
        switch (sub)
        {
            case "install":
            {
                string dir = rest.Value("dir") ?? Directory.GetCurrentDirectory();
                var res = ExoCliInstaller.Install(dir);
                Console.WriteLine($"Installed CLI wrapper at {res.ProjectRoot}");
                return 0;
            }
            case "status":
            {
                string dir = rest.Value("dir") ?? Directory.GetCurrentDirectory();
                Console.WriteLine("wrapper present");
                return 0;
            }
            default:
                Error($"Unknown cli subcommand: {sub}");
                return 1;
        }
    }

    private static int HandleAgents(CliArgs cli)
    {
        if (cli.WantsHelp && cli.Positional.Count == 0)
        {
            PrintAgentsUsage();
            return 0;
        }

        if (cli.Positional.Count == 0)
        {
            Error("Missing agents subcommand (install, status).");
            Console.WriteLine();
            PrintAgentsUsage();
            return 1;
        }

        string sub = cli.Positional[0].ToLowerInvariant();
        var rest = CliArgs.From(cli.Positional.Skip(1).ToList(), cli);

        switch (sub)
        {
            case "install":
                return HandleAgentsInstall(rest);
            case "status":
                return HandleAgentsStatus(rest);
            default:
                Error($"Unknown agents subcommand: {sub}");
                Console.WriteLine();
                PrintAgentsUsage();
                return 1;
        }
    }

    private static void PrintAgentsUsage()
    {
        Console.WriteLine("""
        Usage: exo agents <subcommand> [options]

        Subcommands:
          install    Install selected agent skills, AGENTS.md guide, CLI wrappers, and .gitignore block
          status     Inspect installed agent tooling, skills, and CLI wrappers

        Options for 'install' (at least one target flag is required):
          --claude            Install Claude Code skills (.claude/skills/)
          --gemini            Install Gemini CLI skills (.gemini/skills/)
          --agents            Install generic agent skills (.agents/skills/)
          --all               Install all agent targets (.agents/, .claude/, .gemini/)

        Common options:
          --dir <path>        Project root directory (defaults to current directory)
          --json              Machine-readable JSON output
          -h, --help          Show help
        """);
    }

    private static void PrintAgentsInstallUsage()
    {
        Console.WriteLine("""
        Usage: exo agents install [--claude] [--gemini] [--agents] [--all] [--dir <path>] [--json] [-h|--help]

        Installs selected AI agent skills, AGENTS.md guide, ./exo wrappers, and a marked .gitignore block.
        Running without target flags prints this help and installs nothing.

        Targets:
          --claude            Install Claude Code skills (.claude/skills/)
          --gemini            Install Gemini CLI skills (.gemini/skills/)
          --agents            Install generic agent skills (.agents/skills/)
          --all               Install all agent targets (.agents/, .claude/, .gemini/)

        Options:
          --dir <path>        Project root directory (defaults to current directory)
          --json              Machine-readable JSON output
          -h, --help          Show help
        """);
    }

    private static int HandleAgentsInstall(CliArgs cli)
    {
        var selectedTargets = new List<string>();
        if (cli.Has("all")) selectedTargets.Add("all");
        if (cli.Has("agents")) selectedTargets.Add("agents");
        if (cli.Has("claude")) selectedTargets.Add("claude");
        if (cli.Has("gemini")) selectedTargets.Add("gemini");

        if (cli.WantsHelp || selectedTargets.Count == 0)
        {
            PrintAgentsInstallUsage();
            return 0;
        }

        string dir = cli.Value("dir") ?? Directory.GetCurrentDirectory();
        var res = ExoAgentInstaller.Install(dir, selectedTargets);

        if (cli.Json)
        {
            Console.WriteLine(JsonSerializer.Serialize(res, JsonOptions));
            return 0;
        }

        Success($"[Exoforge] Agent tooling installed in {res.ProjectRoot}");
        Console.WriteLine($"  Package:    {res.PackageRoot}");
        Console.WriteLine($"  Skills:     {res.InstalledSkills.Count} installed ({string.Join(", ", res.InstalledSkills)})");
        Console.WriteLine($"  Files:      {res.UpdatedFiles.Count} written/updated");
        Console.WriteLine($"  CLI binary: {(res.CliAvailable ? "Available" : "Missing from package")}");
        Console.WriteLine("  Installed:  ./exo, ./exo.cmd, AGENTS.md, skills folders, .gitignore block");
        return 0;
    }

    private static int HandleAgentsStatus(CliArgs cli)
    {
        if (cli.WantsHelp)
        {
            Console.WriteLine("Usage: exo agents status [--dir <path>] [--json]");
            return 0;
        }

        string dir = cli.Value("dir") ?? Directory.GetCurrentDirectory();
        var status = ExoAgentInstaller.GetStatus(dir);

        if (cli.Json)
        {
            Console.WriteLine(JsonSerializer.Serialize(status, JsonOptions));
            return 0;
        }

        Console.WriteLine($"Exoforge Agent Setup Status: {(status.CliAvailable && status.AgentsGuideInstalled ? "Ready" : "Incomplete")}");
        Console.WriteLine($"Project Root: {status.ProjectRoot}");
        if (!string.IsNullOrEmpty(status.PackageRoot))
        {
            Console.WriteLine($"Package Root: {status.PackageRoot}");
        }
        Console.WriteLine();
        foreach (var check in status.Checks)
        {
            Console.WriteLine($"  {check}");
        }
        if (status.InstalledSkills.Count > 0)
        {
            Console.WriteLine($"\nInstalled Skills ({status.InstalledSkills.Count}): {string.Join(", ", status.InstalledSkills)}");
        }
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
            references the Exoforge.Plugin.SDK package, and the workspace's .feed holds that package so
            it restores offline: the CLI copies it in from the SDK it was installed with.

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
            --rid defaults to the connected cluster's runtime, not this machine's.
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
            --rid defaults to the connected cluster's runtime, not this machine's.
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
                   exo extension stubs --project-dir <extension dir>   (what the build runs)

            Stubs are written under the extension's obj/, which the build compiles; none live in src/.

            Reads the cluster's contracts, and lays this workspace's own built extensions over them, so an
            extension that is built but not deployed still produces stubs. Without a cluster it uses what
            has been built locally.

            Generates typed stubs for the contracts this extension calls, so extension code does not
            hand-roll service and action names.
            """);
            return 0;
        }

        if (cli.Positional.Count == 0 && cli.Value("project-dir") is null)
        {
            return Missing("extension name", "exo extension stubs <name>");
        }

        // The build's own call: only what the extension declares, from the manifests beside it.
        if (cli.Value("project-dir") is { } projectDir)
        {
            projectDir = Path.GetFullPath(projectDir);
            var (built, unresolved) = await ExoDeployer.BesideExtension(projectDir).GenerateDependencyStubsAsync(projectDir).ConfigureAwait(false);

            if (unresolved.Count > 0)
            {
                Error($"[Exoforge] No contracts for: {string.Join(", ", unresolved)}. Start the cluster (`just dev`), or build the extension that provides them.");
                return 1;
            }

            if (built != null) Success($"[Exoforge] Generated typed extension service stubs:\n  {built}");
            return 0;
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
        string stubsOut = cli.Value("out") ?? ExoDeployer.StubsPath(extensionDir);

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
        if (rid is null)
        {
            // The binary runs on the cluster, not here: build for the cluster's runtime unless told otherwise.
            rid = await deployer.GetClusterTargetRidAsync(env).ConfigureAwait(false);
            Console.WriteLine(rid is null
                ? "[Exoforge] Could not read the cluster's runtime; building for this machine (pass --rid to choose)."
                : $"[Exoforge] Building for the cluster's runtime: {rid}");
        }

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
