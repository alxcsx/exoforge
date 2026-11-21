using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Exoforge.Client;

namespace Exoforge.Management;

/// <summary>A stub pass that could not give an extension the stubs it needs. The message says what to do.</summary>
public sealed class ExoStubPassException : InvalidOperationException
{
    public ExoStubPassException(string message) : base(message)
    {
    }
}

public enum StubOutcome
{
    /// <summary>Stubs are in <c>obj/exoforge</c> (written now, or already current).</summary>
    Generated,

    /// <summary>The extension calls no other service: nothing to generate.</summary>
    NoDependencies,

    /// <summary>The extension commits its own <c>Generated/PluginServices.g.cs</c>; a second copy would not compile.</summary>
    CommittedStubs,

    /// <summary>Not an extension with a project.</summary>
    Skipped,

    /// <summary>A service it calls has no contract anywhere.</summary>
    Failed,
}

public sealed class StubPassItem
{
    public StubPassItem(string name, StubOutcome outcome, string detail, string? output = null)
    {
        Name = name;
        Outcome = outcome;
        Detail = detail;
        Output = output;
    }

    public string Name { get; }
    public StubOutcome Outcome { get; }
    public string Detail { get; }
    public string? Output { get; }
}

public sealed class StubPassResult
{
    public StubPassResult(IReadOnlyList<StubPassItem> items) => Items = items;

    public IReadOnlyList<StubPassItem> Items { get; }
    public IEnumerable<StubPassItem> Failures => Items.Where(i => i.Outcome == StubOutcome.Failed);
    public bool Ok => !Failures.Any();
    public IReadOnlyList<string> Outputs => Items.Where(i => i.Output != null).Select(i => i.Output!).ToList();

    /// <summary>One line per failure, ready for a banner or an error.</summary>
    public string FailureMessage => string.Join(" ", Failures.Select(f => f.Detail));
}

public partial class ExoDeployer
{
    /// <summary>How long a stub pass waits for a server before generating with what it has.</summary>
    private static readonly TimeSpan StubServerTimeout = TimeSpan.FromSeconds(8);

    /// <summary>
    /// The explicit stub pass: for each extension, makes typed stubs for the services it calls and writes them under
    /// <c>obj/exoforge</c> (never into <c>src</c>). Callers decide when it runs: <c>exo extension stubs</c>, the start of
    /// every build, a button. Nothing runs it on its own, and nothing in MSBuild or Unity's load path does.
    ///
    /// Which services: <see cref="ExoDependencyDiscovery"/> (sources, pins and a manifest if there is one). Where the
    /// contracts come from: the manifests of the sibling extensions, then the cached cluster export
    /// (<c>.contracts_cache.json</c>), then the server, asked only when something is still unknown. Name the providers
    /// first; a provider that is built before its callers already has its manifest. A service nobody has a contract
    /// for fails that extension with a message; the others still get theirs.
    /// </summary>
    public async Task<StubPassResult> GenerateStubsAsync(
        IEnumerable<string> names,
        ExoClient? existingClient = null,
        Action<string>? emit = null,
        CancellationToken cancellationToken = default)
    {
        var items = new List<StubPassItem>();
        if (ExoClientBindings.ExtensionsInsideUnityCompile(_workspace) is { } inside) emit?.Invoke($"[stubs] warning: {inside}");
        string cached = LoadCachedOrEmptyContracts();
        string? fromServer = null;
        bool serverTried = false;

        async Task<bool> AskServerAsync()
        {
            if (serverTried) return fromServer != null;
            serverTried = true;

            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeout.CancelAfter(StubServerTimeout);
            try
            {
                fromServer = await GetContractsExportJsonAsync(existingClient: existingClient, cancellationToken: timeout.Token).ConfigureAwait(false);
                return true;
            }
            catch (Exception ex) when (ex is not OperationCanceledException || !cancellationToken.IsCancellationRequested)
            {
                emit?.Invoke($"[stubs] no server ({ex.Message}); using the manifests and the cached contracts");
                return false;
            }
        }

        foreach (string raw in names)
        {
            cancellationToken.ThrowIfCancellationRequested();
            string name = NormalizeExtensionName(raw);
            string? dir = ResolveExtensionDir(name);
            string? csproj = dir == null ? null : FindExtensionCsproj(dir, name);
            if (dir == null || csproj == null)
            {
                items.Add(new StubPassItem(name, StubOutcome.Skipped, $"'{name}' has no extension project here."));
                continue;
            }

            string projectDir = Path.GetDirectoryName(csproj)!;
            if (File.Exists(Path.Combine(projectDir, "Generated", "PluginServices.g.cs")))
            {
                string kept = $"'{name}' commits its own Generated/PluginServices.g.cs; delete it to let `exo extension stubs` make the stubs under obj/exoforge.";
                emit?.Invoke($"[stubs] {kept}");
                items.Add(new StubPassItem(name, StubOutcome.CommittedStubs, kept));
                continue;
            }

            string merged = MergeLocalContracts(fromServer ?? cached);
            DiscoveredDependencies found = DiscoverFor(dir, name, merged);
            var needed = found.Services.Where(s => !ExoDependencyDiscovery.IsHostOwned(s)).ToList();

            if (!serverTried && (found.Unmatched.Count > 0 || MissingServices(merged, needed).Count > 0) && await AskServerAsync().ConfigureAwait(false))
            {
                merged = MergeLocalContracts(fromServer!);
                found = DiscoverFor(dir, name, merged);
                needed = found.Services.Where(s => !ExoDependencyDiscovery.IsHostOwned(s)).ToList();
            }

            string output = StubsPath(dir);
            if (needed.Count == 0)
            {
                // A stub left from when it did call something would keep compiling against a contract it no longer uses.
                if (File.Exists(output)) File.Delete(output);
                items.Add(new StubPassItem(name, StubOutcome.NoDependencies, $"'{name}' calls no other service."));
                continue;
            }

            var missing = MissingServices(merged, needed);
            if (missing.Count > 0)
            {
                string detail =
                    $"'{name}' calls {string.Join(", ", missing)}, which has no contract: build the extension that provides it first, " +
                    "or start the server (its own services are fetched from it).";
                emit?.Invoke($"[stubs] {detail}");
                items.Add(new StubPassItem(name, StubOutcome.Failed, detail));
                continue;
            }

            ExoCodeGenerator.GeneratePluginStubsToFile(merged, output, services: needed, pluginId: name, codeSearchRoot: dir);
            emit?.Invoke($"[stubs] {name}: {string.Join(", ", needed)} -> {output}");
            items.Add(new StubPassItem(name, StubOutcome.Generated, $"Stubs for {string.Join(", ", needed)}.", output));
        }

        return new StubPassResult(items);
    }

    /// <summary>The stub pass over every extension the workspace includes (not <c>excluded_extensions</c>), providers first.</summary>
    public Task<StubPassResult> GenerateIncludedStubsAsync(
        ExoClient? existingClient = null,
        Action<string>? emit = null,
        CancellationToken cancellationToken = default)
    {
        var included = _workspace.IncludedExtensions();
        var plan = ExoDeployOrder.Plan(ExoDeployOrder.ReadNodes(_workspace.ExtensionsPath, included)
            .Select(n => new DeployNode(n.Name, n.Provides.Append(n.Name).ToList(), n.Dependencies)));
        return GenerateStubsAsync(plan.Order, existingClient, emit, cancellationToken);
    }

    /// <summary>
    /// The stub pass for one extension, from code that cannot await (a build). It runs on its own thread, so a caller
    /// with a synchronization context cannot deadlock on it. Throws <see cref="ExoStubPassException"/> when it fails.
    /// </summary>
    public void EnsureStubs(string extensionName, Action<string>? emit = null)
    {
        var result = Task.Run(() => GenerateStubsAsync(new[] { extensionName }, emit: emit)).GetAwaiter().GetResult();
        if (!result.Ok) throw new ExoStubPassException(result.FailureMessage);
    }

    private DiscoveredDependencies DiscoverFor(string extensionDir, string name, string mergedExport)
    {
        var known = new HashSet<string>(AvailableServices(mergedExport), StringComparer.Ordinal);
        known.UnionWith(ExoDependencyDiscovery.SiblingServices(_workspace.ExtensionsPath));
        return ExoDependencyDiscovery.Discover(extensionDir, name, known);
    }

    private string? ResolveExtensionDir(string cleanName)
    {
        string dir = Path.Combine(_workspace.ExtensionsPath, cleanName);
        if (Directory.Exists(dir)) return dir;

        string direct = Path.Combine(_workspace.RootPath, cleanName);
        return Directory.Exists(direct) ? direct : null;
    }
}
