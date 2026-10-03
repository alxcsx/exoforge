using System;
using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Threading.Tasks;
using Exoforge.Management;

namespace Exoforge.CLI;

public static class Program
{
    public static async Task<int> Main(string[] args)
    {
        if (args.Length == 0 || args[0] == "help" || args[0] == "--help" || args[0] == "-h")
        {
            PrintUsage();
            return 0;
        }

        string command = args[0].ToLowerInvariant();

        try
        {
            switch (command)
            {
                case "init":
                    return HandleInit(args);

                case "plugin":
                    return await HandlePluginAsync(args).ConfigureAwait(false);

                case "sync":
                case "gen":
                    return await HandleSyncAsync(args).ConfigureAwait(false);

                case "status":
                    return await HandleStatusAsync(args).ConfigureAwait(false);

                default:
                    Console.ForegroundColor = ConsoleColor.Red;
                    Console.WriteLine($"Unknown command: {command}");
                    Console.ResetColor();
                    PrintUsage();
                    return 1;
            }
        }
        catch (Exception ex)
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine($"[Error] {ex.Message}");
            Console.ResetColor();
            return 1;
        }
    }

    private static void PrintUsage()
    {
        Console.WriteLine("""
===============================================================
       EXOFORGE DEVELOPER CLI (Non-Mix / C# SDK Tools)
===============================================================

Usage: exo <command> [options]

Commands:
  init                     Initializes /exoforge workspace and exoforge.json
  plugin new <name>        Scaffolds a new C# WASM plugin project
  plugin build <name>      Builds plugin .csproj and compiles WASM
  plugin push <name>       Builds and deploys plugin to live Exoforge cluster
  plugin list              Lists all installed plugins from live cluster
  plugin remove <id>       Removes a plugin from the live cluster
  sync (or gen)            Downloads live contracts & generates typed C# client
  status                   Inspects live BEAM cluster health and metrics

Options:
  --dir <path>             Workspace root path (defaults to current dir)
  --env <environment>      Target cluster environment (defaults to 'local')
  --name <project_name>    Project name for initialization
""");
    }

    private static int HandleInit(string[] args)
    {
        string dir = GetOption(args, "--dir") ?? Directory.GetCurrentDirectory();
        string name = GetOption(args, "--name") ?? Path.GetFileName(Path.GetFullPath(dir));

        var ws = ExoWorkspace.Initialize(dir, name);
        Console.ForegroundColor = ConsoleColor.Green;
        Console.WriteLine($"[Exoforge] Initialized workspace at {ws.RootPath}");
        Console.WriteLine($"  Config:     {ws.ConfigPath}");
        Console.WriteLine($"  Plugins:    {ws.PluginsPath}");
        Console.WriteLine($"  Client Gen: {ws.GeneratedPath}");
        Console.ResetColor();
        return 0;
    }

    private static async Task<int> HandlePluginAsync(string[] args)
    {
        if (args.Length < 2)
        {
            Console.WriteLine("Usage: exo plugin <new|build|push|list|remove> [name] [options]");
            return 1;
        }

        string subCmd = args[1].ToLowerInvariant();
        string dir = GetOption(args, "--dir") ?? Directory.GetCurrentDirectory();
        var ws = ExoWorkspace.Load(dir);
        var deployer = new ExoDeployer(ws);
        string? env = GetOption(args, "--env");

        switch (subCmd)
        {
            case "new":
                if (args.Length < 3)
                {
                    Console.WriteLine("Error: Missing plugin name. Usage: exo plugin new <name>");
                    return 1;
                }
                string name = args[2];
                string created = ExoScaffolder.ScaffoldPlugin(ws.PluginsPath, name);
                Console.ForegroundColor = ConsoleColor.Green;
                Console.WriteLine($"[Exoforge] Scaffolded C# WASM plugin '{name}' at:");
                Console.WriteLine($"  {created}");
                Console.ResetColor();
                return 0;

            case "build":
                if (args.Length < 3)
                {
                    Console.WriteLine("Error: Missing plugin name. Usage: exo plugin build <name>");
                    return 1;
                }
                return BuildPlugin(ws, args[2]);

            case "push":
                if (args.Length < 3)
                {
                    Console.WriteLine("Error: Missing plugin name. Usage: exo plugin push <name>");
                    return 1;
                }
                string pushName = args[2];
                // Build if not present or requested
                _ = BuildPlugin(ws, pushName);

                Console.WriteLine($"[Exoforge] Uploading plugin '{pushName}' to live cluster...");
                string pushResult = await deployer.UploadPluginAsync(pushName, env).ConfigureAwait(false);
                Console.ForegroundColor = ConsoleColor.Green;
                Console.WriteLine($"[Exoforge] Successfully deployed '{pushName}'!");
                Console.WriteLine($"  Server Response: {pushResult}");
                Console.ResetColor();
                return 0;

            case "list":
                Console.WriteLine("[Exoforge] Fetching installed plugins from live cluster...");
                var listResult = await deployer.ListPluginsAsync(env).ConfigureAwait(false);
                Console.WriteLine(JsonSerializer.Serialize(listResult, new JsonSerializerOptions { WriteIndented = true }));
                return 0;

            case "remove":
                if (args.Length < 3)
                {
                    Console.WriteLine("Error: Missing plugin id. Usage: exo plugin remove <id>");
                    return 1;
                }
                string rmId = args[2];
                string rmResult = await deployer.RemovePluginAsync(rmId, env).ConfigureAwait(false);
                Console.ForegroundColor = ConsoleColor.Yellow;
                Console.WriteLine($"[Exoforge] Removed plugin '{rmId}' from cluster.");
                Console.ResetColor();
                return 0;

            default:
                Console.WriteLine($"Unknown plugin subcommand: {subCmd}");
                return 1;
        }
    }

    private static int BuildPlugin(ExoWorkspace ws, string rawName)
    {
        string cleanName = rawName.Trim().ToLowerInvariant().Replace("-", "_");
        string pluginDir = Path.Combine(ws.PluginsPath, cleanName);

        if (!Directory.Exists(pluginDir))
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine($"Plugin directory not found: {pluginDir}");
            Console.ResetColor();
            return 1;
        }

        string csproj = Path.Combine(pluginDir, $"{cleanName}.csproj");
        if (File.Exists(csproj))
        {
            Console.WriteLine($"[Exoforge] Compiling {csproj}...");
            var psi = new ProcessStartInfo("dotnet", $"build \"{csproj}\" -c Release")
            {
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false
            };

            using var proc = Process.Start(psi);
            if (proc != null)
            {
                proc.WaitForExit();
                if (proc.ExitCode != 0)
                {
                    Console.WriteLine(proc.StandardError.ReadToEnd());
                    Console.WriteLine(proc.StandardOutput.ReadToEnd());
                    return proc.ExitCode;
                }
            }
        }

        // Check if build.sh exists
        string buildSh = Path.Combine(pluginDir, "build.sh");
        if (File.Exists(buildSh))
        {
            Console.WriteLine($"[Exoforge] Executing build.sh...");
            var psi = new ProcessStartInfo("bash", $"\"{buildSh}\"")
            {
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                WorkingDirectory = pluginDir
            };

            using var proc = Process.Start(psi);
            if (proc != null)
            {
                proc.WaitForExit();
                if (proc.ExitCode != 0)
                {
                    Console.WriteLine(proc.StandardError.ReadToEnd());
                    return proc.ExitCode;
                }
            }
        }

        Console.ForegroundColor = ConsoleColor.Green;
        Console.WriteLine($"[Exoforge] Build complete for plugin '{cleanName}'.");
        Console.ResetColor();
        return 0;
    }

    private static async Task<int> HandleSyncAsync(string[] args)
    {
        string dir = GetOption(args, "--dir") ?? Directory.GetCurrentDirectory();
        var ws = ExoWorkspace.Load(dir);
        var deployer = new ExoDeployer(ws);
        string? env = GetOption(args, "--env");

        Console.WriteLine($"[Exoforge] Synchronizing backend contracts from cluster...");
        await deployer.SyncContractsAsync(env).ConfigureAwait(false);

        Console.ForegroundColor = ConsoleColor.Green;
        Console.WriteLine($"[Exoforge] Generated strongly-typed C# client bindings at:");
        Console.WriteLine($"  {ws.GeneratedPath}");
        Console.ResetColor();
        return 0;
    }

    private static async Task<int> HandleStatusAsync(string[] args)
    {
        string dir = GetOption(args, "--dir") ?? Directory.GetCurrentDirectory();
        var ws = ExoWorkspace.Load(dir);
        var deployer = new ExoDeployer(ws);
        string? env = GetOption(args, "--env");

        Console.WriteLine($"[Exoforge] Querying cluster status...");
        var status = await deployer.GetSystemStatusAsync(env).ConfigureAwait(false);
        Console.WriteLine(JsonSerializer.Serialize(status, new JsonSerializerOptions { WriteIndented = true }));
        return 0;
    }

    private static string? GetOption(string[] args, string flag)
    {
        for (int i = 0; i < args.Length - 1; i++)
        {
            if (string.Equals(args[i], flag, StringComparison.OrdinalIgnoreCase))
            {
                return args[i + 1];
            }
        }
        return null;
    }
}
