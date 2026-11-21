using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json.Nodes;

namespace Exoforge.Management;

/// <summary>An extension as the deploy order sees it: the services it provides and the services it calls.</summary>
public sealed class DeployNode
{
    public DeployNode(string name, IReadOnlyCollection<string> provides, IReadOnlyCollection<string> dependencies)
    {
        Name = name;
        Provides = provides;
        Dependencies = dependencies;
    }

    public string Name { get; }
    public IReadOnlyCollection<string> Provides { get; }
    public IReadOnlyCollection<string> Dependencies { get; }
}

/// <summary>
/// The order to build and deploy a set of extensions in. An extension that calls a service another one provides
/// goes after it, so the provider is already running (and its manifest already written, for the stubs) when the
/// caller starts. Services nobody in the set provides are the server's, and are only checked when the caller
/// says which ones the server has.
/// </summary>
public sealed class DeployPlan
{
    public DeployPlan(IReadOnlyList<string> order, IReadOnlyList<string> problems)
    {
        Order = order;
        Problems = problems;
    }

    public IReadOnlyList<string> Order { get; }
    public IReadOnlyList<string> Problems { get; }
    public bool IsClean => Problems.Count == 0;
}

/// <summary>An included extension (<see cref="Extension"/>) that needs an excluded one (<see cref="Needs"/>).</summary>
public sealed class ExclusionProblem : IEquatable<ExclusionProblem>
{
    public ExclusionProblem(string extension, string needs)
    {
        Extension = extension;
        Needs = needs;
    }

    public string Extension { get; }
    public string Needs { get; }
    public string Message => $"{Extension} needs {Needs}, which is excluded";

    public bool Equals(ExclusionProblem? other) => other != null && Extension == other.Extension && Needs == other.Needs;
    public override bool Equals(object? obj) => Equals(obj as ExclusionProblem);
    public override int GetHashCode() => (Extension, Needs).GetHashCode();
}

public static class ExoDeployOrder
{
    /// <param name="serverServices">The services the server already runs; null when unknown (nothing is reported missing).</param>
    public static DeployPlan Plan(IEnumerable<DeployNode> nodes, IReadOnlyCollection<string>? serverServices = null)
    {
        var list = nodes.OrderBy(n => n.Name, StringComparer.Ordinal).ToList();
        var providerOf = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var node in list)
        {
            foreach (string service in node.Provides)
            {
                providerOf.TryAdd(service, node.Name);
            }
        }

        var problems = new List<string>();
        var waitsFor = new Dictionary<string, HashSet<string>>(StringComparer.Ordinal);
        foreach (var node in list)
        {
            var needs = new HashSet<string>(StringComparer.Ordinal);
            foreach (string dependency in node.Dependencies)
            {
                if (providerOf.TryGetValue(dependency, out string? provider))
                {
                    if (provider != node.Name) needs.Add(provider);
                }
                else if (serverServices != null && !serverServices.Contains(dependency))
                {
                    problems.Add($"'{node.Name}' needs the service '{dependency}', which no extension here provides and the server does not run.");
                }
            }

            waitsFor[node.Name] = needs;
        }

        var order = new List<string>();
        var remaining = list.Select(n => n.Name).ToList();
        while (remaining.Count > 0)
        {
            string? next = remaining.FirstOrDefault(name => waitsFor[name].All(order.Contains));
            if (next == null)
            {
                problems.Add($"These extensions depend on each other in a circle: {string.Join(", ", remaining)}.");
                order.AddRange(remaining);
                break;
            }

            order.Add(next);
            remaining.Remove(next);
        }

        return new DeployPlan(order, problems);
    }

    /// <summary>The problems with deploying in this exact order: an extension placed before one it calls.</summary>
    public static IReadOnlyList<string> Verify(IReadOnlyList<string> order, IEnumerable<DeployNode> nodes)
    {
        var all = nodes.ToList();
        var problems = new List<string>();
        foreach (var node in all)
        {
            int at = order.ToList().IndexOf(node.Name);
            foreach (string dependency in node.Dependencies)
            {
                var provider = all.FirstOrDefault(o => o.Name != node.Name && o.Provides.Contains(dependency));
                if (provider != null && order.ToList().IndexOf(provider.Name) > at)
                {
                    problems.Add($"'{node.Name}' is deployed before '{provider.Name}', which provides '{dependency}'.");
                }
            }
        }

        return problems;
    }

    /// <summary>
    /// Reads the nodes: what each extension provides from its <c>manifest.json</c>, and what it calls from its sources
    /// and pins as well as the manifest (<see cref="ExoDependencyDiscovery"/>), so an extension that was never built
    /// still has its links. A half-written manifest counts as having none.
    /// </summary>
    public static List<DeployNode> ReadNodes(string extensionsPath, IEnumerable<string> names)
    {
        var siblings = ExoDependencyDiscovery.SiblingServices(extensionsPath);
        var nodes = new List<DeployNode>();
        foreach (string name in names)
        {
            var provides = new List<string>();
            string dir = Path.Combine(extensionsPath, name);
            string path = Path.Combine(dir, "manifest.json");
            try
            {
                if (File.Exists(path) && JsonNode.Parse(File.ReadAllText(path)) is JsonObject manifest)
                {
                    provides.AddRange(Strings(manifest["provides"]));
                }
            }
            catch (System.Text.Json.JsonException)
            {
                // a half-written manifest: treat as unlinked, the build will rewrite it
            }

            nodes.Add(new DeployNode(name, provides, ExoDependencyDiscovery.Discover(dir, name, siblings).Services));
        }

        return nodes;
    }

    /// <summary>
    /// The problems with leaving <paramref name="excluded"/> out of <paramref name="all"/>: an included extension that
    /// calls a service only an excluded extension provides ("daily_rewards needs wallet, which is excluded"). A service
    /// nobody here provides is the server's own and is not an error. Providers are found as in <see cref="Plan"/>:
    /// the manifest's <c>provides</c>, and the extension's own name when it has not been built yet.
    /// </summary>
    public static IReadOnlyList<string> ValidateIncluded(string extensionsPath, IEnumerable<string> all, IEnumerable<string> excluded) =>
        FindExclusionProblems(extensionsPath, all, excluded).Select(p => p.Message).ToList();

    /// <summary>The same check as <see cref="ValidateIncluded"/>, with the two extension names kept apart (for a button that includes the missing one).</summary>
    public static IReadOnlyList<ExclusionProblem> FindExclusionProblems(string extensionsPath, IEnumerable<string> all, IEnumerable<string> excluded)
    {
        var skip = new HashSet<string>(excluded, StringComparer.Ordinal);
        var nodes = ReadNodes(extensionsPath, all)
            .Select(n => new DeployNode(n.Name, n.Provides.Append(n.Name).ToList(), n.Dependencies))
            .ToList();

        var problems = new List<ExclusionProblem>();
        foreach (var node in nodes.Where(n => !skip.Contains(n.Name)))
        {
            foreach (string dependency in node.Dependencies.Distinct(StringComparer.Ordinal))
            {
                if (nodes.Any(n => !skip.Contains(n.Name) && n.Provides.Contains(dependency))) continue;
                var excludedProvider = nodes.FirstOrDefault(n => skip.Contains(n.Name) && n.Provides.Contains(dependency));
                if (excludedProvider != null)
                {
                    problems.Add(new ExclusionProblem(node.Name, excludedProvider.Name));
                }
            }
        }

        return problems.Distinct().ToList();
    }

    private static IEnumerable<string> Strings(JsonNode? node) =>
        node is JsonArray array
            ? array.Select(item => item?.GetValue<string>() ?? "").Where(s => s.Length > 0)
            : Enumerable.Empty<string>();
}
