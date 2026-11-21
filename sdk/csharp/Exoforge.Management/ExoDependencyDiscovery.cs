using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace Exoforge.Management;

/// <summary>What an extension was found to call: the services to make stubs for, and the <c>ExoServices.X</c> names that match nothing.</summary>
public sealed class DiscoveredDependencies
{
    public DiscoveredDependencies(IReadOnlyList<string> services, IReadOnlyList<string> unmatched)
    {
        Services = services;
        Unmatched = unmatched;
    }

    /// <summary>Service names (snake_case): the manifest's dependencies, <c>[ExoDependency]</c> pins and the services the sources call.</summary>
    public IReadOnlyList<string> Services { get; }

    /// <summary><c>ExoServices.&lt;Name&gt;</c> usages that match no known service (the cluster may know them).</summary>
    public IReadOnlyList<string> Unmatched { get; }
}

/// <summary>
/// Finds which services an extension calls without needing a manifest, so stubs can be made before the first build
/// and an exclusion that breaks a caller is reported before anything runs. The sources are the truth:
/// <c>ExoServices.Items</c> is a call to the service <c>items</c>, and <c>[ExoDependency("items")]</c> pins one that
/// the code reaches some other way. A manifest from an earlier build is added to what the sources say.
/// </summary>
public static class ExoDependencyDiscovery
{
    private static readonly Regex ServiceUse = new(@"\bExoServices\s*\.\s*([A-Za-z_]\w*)", RegexOptions.Compiled);
    private static readonly Regex Pin = new("\\bExoDependency(?:Attribute)?\\s*\\(\\s*(?:ServiceName\\s*=\\s*)?\"([^\"]+)\"", RegexOptions.Compiled);

    /// <summary>Members of the generated <c>ExoServices</c> class that are capabilities, not services.</summary>
    private static readonly HashSet<string> Members = new(StringComparer.Ordinal)
    {
        "Database", "Logger", "Events", "Actions", "Context", "Services", "Reset"
    };

    /// <summary>The host's own capabilities: reached without a stub, so never something a stub is made for.</summary>
    public static bool IsHostOwned(string service) => service is "database" or "resource_store";

    /// <summary>
    /// Scans the extension's own sources (not <c>obj</c>, <c>bin</c>, generated files or committed <c>Generated</c> folders).
    /// Returns the used names as written (PascalCase) and the pins.
    /// </summary>
    public static (IReadOnlyList<string> Used, IReadOnlyList<string> Pins) ScanSources(string extensionDir)
    {
        var used = new HashSet<string>(StringComparer.Ordinal);
        var pins = new List<string>();
        if (!Directory.Exists(extensionDir)) return (Array.Empty<string>(), Array.Empty<string>());

        foreach (string file in SourceFiles(extensionDir))
        {
            string text;
            try
            {
                text = File.ReadAllText(file);
            }
            catch (IOException)
            {
                continue;
            }

            foreach (Match m in ServiceUse.Matches(text)) used.Add(m.Groups[1].Value);
            foreach (Match m in Pin.Matches(text))
            {
                if (!pins.Contains(m.Groups[1].Value)) pins.Add(m.Groups[1].Value);
            }
        }

        return (used.OrderBy(u => u, StringComparer.Ordinal).ToList(), pins);
    }

    private static IEnumerable<string> SourceFiles(string dir)
    {
        foreach (string file in Directory.EnumerateFiles(dir, "*.cs"))
        {
            if (!file.EndsWith(".g.cs", StringComparison.OrdinalIgnoreCase)) yield return file;
        }

        foreach (string sub in Directory.EnumerateDirectories(dir))
        {
            string name = Path.GetFileName(sub);
            if (name.StartsWith('.') || name is "obj" or "bin" or "Generated" or "node_modules") continue;
            foreach (string file in SourceFiles(sub)) yield return file;
        }
    }

    /// <summary>
    /// The services <paramref name="extensionDir"/> calls: manifest dependencies (when a manifest exists), pins, and
    /// <c>ExoServices.X</c> usages matched to <paramref name="known"/> by name (<c>LojaItens</c> is <c>loja_itens</c>).
    /// The extension itself is never its own dependency.
    /// </summary>
    public static DiscoveredDependencies Discover(string extensionDir, string selfName, IEnumerable<string> known)
    {
        var byPascal = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (string service in known)
        {
            if (!string.IsNullOrWhiteSpace(service)) byPascal.TryAdd(ExoCodeGenerator.ToPascalCase(service), service);
        }

        var services = new List<string>();
        void Add(string service)
        {
            if (service.Length > 0 && !string.Equals(service, selfName, StringComparison.Ordinal) && !services.Contains(service)) services.Add(service);
        }

        if (ExoDeployer.ReadManifestDependencies(extensionDir) is { } declared)
        {
            foreach (string dependency in declared) Add(dependency);
        }

        var (used, pins) = ScanSources(extensionDir);
        foreach (string pin in pins) Add(pin);

        var unmatched = new List<string>();
        foreach (string name in used)
        {
            if (Members.Contains(name)) continue;
            if (byPascal.TryGetValue(name, out string? service)) Add(service);
            else unmatched.Add(name);
        }

        return new DiscoveredDependencies(services, unmatched);
    }

    /// <summary>
    /// The services the sibling extensions of an extensions directory offer: each folder's name, and what its manifest
    /// provides, when it has one. Folders that are not extensions (hidden, dotted such as <c>x.Tests</c>) are left out.
    /// </summary>
    public static HashSet<string> SiblingServices(string extensionsPath)
    {
        var services = new HashSet<string>(StringComparer.Ordinal);
        if (!Directory.Exists(extensionsPath)) return services;

        foreach (string dir in Directory.GetDirectories(extensionsPath))
        {
            string name = Path.GetFileName(dir);
            if (name.Length == 0 || name.StartsWith('.') || name.Contains('.')) continue;
            services.Add(name);

            string manifest = Path.Combine(dir, "manifest.json");
            if (!File.Exists(manifest)) continue;

            try
            {
                if (JsonNode.Parse(File.ReadAllText(manifest))?["provides"] is JsonArray provides)
                {
                    foreach (JsonNode? p in provides)
                    {
                        if (p?.GetValue<string>() is { Length: > 0 } provided) services.Add(provided);
                    }
                }
            }
            catch (Exception ex) when (ex is System.Text.Json.JsonException or InvalidOperationException or IOException)
            {
                // a half-written manifest: the folder name still counts
            }
        }

        return services;
    }
}
