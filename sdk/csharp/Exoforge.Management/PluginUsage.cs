using System.Collections.Generic;
using System.Text.Json;

namespace Exoforge.Management;

/// <summary>
/// Usage the instance persisted for one plugin: call shape only - names, counts, durations, bytes,
/// CPU and RSS. No payloads and no player identifiers, which is what makes metering on by default.
/// </summary>
public sealed class PluginUsage
{
    public string PluginId { get; set; } = "";
    public long Starts { get; set; }
    public long Restarts { get; set; }
    public long Events { get; set; }
    public long HostCalls { get; set; }
    public long CpuMs { get; set; }
    public long PeakRssKb { get; set; }
    public long UptimeMs { get; set; }
    public IReadOnlyList<PluginActionUsage> Actions { get; set; } = new List<PluginActionUsage>();
}

/// <summary>One action's share of a plugin's usage.</summary>
public sealed class PluginActionUsage
{
    public string Action { get; set; } = "";
    public long Invocations { get; set; }
    public long Errors { get; set; }
    public long WallUs { get; set; }
    public long AvgWallUs { get; set; }
    public long BytesIn { get; set; }
    public long BytesOut { get; set; }
}

/// <summary>
/// One <c>metering.usage</c> response: the title's plugins, rolled up per action. The server owns
/// the arithmetic; this side only reads the shape.
/// </summary>
public sealed class PluginUsageReport
{
    public string TitleId { get; set; } = "";
    public string StudioId { get; set; } = "";
    public IReadOnlyList<PluginUsage> Plugins { get; set; } = new List<PluginUsage>();

    public static PluginUsageReport Parse(JsonElement root)
    {
        var plugins = new List<PluginUsage>();

        if (root.ValueKind == JsonValueKind.Object &&
            ((root.TryGetProperty("extensions", out var array) || root.TryGetProperty("plugins", out array)) &&
             array.ValueKind == JsonValueKind.Array))
        {
            foreach (var element in array.EnumerateArray())
            {
                plugins.Add(ParsePlugin(element));
            }
        }

        return new PluginUsageReport
        {
            TitleId = String(root, "title_id"),
            StudioId = String(root, "studio_id"),
            Plugins = plugins,
        };
    }

    private static PluginUsage ParsePlugin(JsonElement element)
    {
        JsonElement counters = element.ValueKind == JsonValueKind.Object &&
                               (element.TryGetProperty("extension", out var nested) ||
                                element.TryGetProperty("plugin", out nested)) &&
                               nested.ValueKind == JsonValueKind.Object
            ? nested
            : default;

        var actions = new List<PluginActionUsage>();

        if (element.ValueKind == JsonValueKind.Object &&
            element.TryGetProperty("actions", out var list) &&
            list.ValueKind == JsonValueKind.Array)
        {
            foreach (var action in list.EnumerateArray())
            {
                actions.Add(new PluginActionUsage
                {
                    Action = String(action, "action"),
                    Invocations = Long(action, "invocations"),
                    Errors = Long(action, "errors"),
                    WallUs = Long(action, "wall_us"),
                    AvgWallUs = Long(action, "avg_wall_us"),
                    BytesIn = Long(action, "bytes_in"),
                    BytesOut = Long(action, "bytes_out"),
                });
            }
        }

        string id = String(element, "extension_id");
        if (string.IsNullOrEmpty(id)) id = String(element, "plugin_id");

        return new PluginUsage
        {
            PluginId = id,
            Starts = Long(counters, "starts"),
            Restarts = Long(counters, "restarts"),
            Events = Long(counters, "events"),
            HostCalls = Long(counters, "host_calls"),
            CpuMs = Long(counters, "cpu_ms"),
            PeakRssKb = Long(counters, "peak_rss_kb"),
            UptimeMs = Long(counters, "uptime_ms"),
            Actions = actions,
        };
    }

    private static string String(JsonElement element, string property) =>
        element.ValueKind == JsonValueKind.Object &&
        element.TryGetProperty(property, out var value) &&
        value.ValueKind == JsonValueKind.String
            ? value.GetString() ?? ""
            : "";

    private static long Long(JsonElement element, string property) =>
        element.ValueKind == JsonValueKind.Object &&
        element.TryGetProperty(property, out var value) &&
        value.TryGetInt64(out long parsed)
            ? parsed
            : 0;
}

/// <summary>
/// Usage persisted for one extension.
/// </summary>
public sealed class ExtensionUsage
{
    public string ExtensionId { get; set; } = "";
    public string PluginId { get => ExtensionId; set => ExtensionId = value; }
    public long Starts { get; set; }
    public long Restarts { get; set; }
    public long Events { get; set; }
    public long HostCalls { get; set; }
    public long CpuMs { get; set; }
    public long PeakRssKb { get; set; }
    public long UptimeMs { get; set; }
    public IReadOnlyList<ExtensionActionUsage> Actions { get; set; } = new List<ExtensionActionUsage>();

    public static implicit operator ExtensionUsage(PluginUsage p)
    {
        var actions = new List<ExtensionActionUsage>();
        foreach (var a in p.Actions)
        {
            actions.Add(new ExtensionActionUsage
            {
                Action = a.Action,
                Invocations = a.Invocations,
                Errors = a.Errors,
                WallUs = a.WallUs,
                AvgWallUs = a.AvgWallUs,
                BytesIn = a.BytesIn,
                BytesOut = a.BytesOut,
            });
        }
        return new ExtensionUsage
        {
            ExtensionId = p.PluginId,
            Starts = p.Starts,
            Restarts = p.Restarts,
            Events = p.Events,
            HostCalls = p.HostCalls,
            CpuMs = p.CpuMs,
            PeakRssKb = p.PeakRssKb,
            UptimeMs = p.UptimeMs,
            Actions = actions
        };
    }
}

/// <summary>One action's share of an extension's usage.</summary>
public sealed class ExtensionActionUsage
{
    public string Action { get; set; } = "";
    public long Invocations { get; set; }
    public long Errors { get; set; }
    public long WallUs { get; set; }
    public long AvgWallUs { get; set; }
    public long BytesIn { get; set; }
    public long BytesOut { get; set; }
}

/// <summary>
/// Persisted usage report for extensions.
/// </summary>
public sealed class ExtensionUsageReport
{
    public string TitleId { get; set; } = "";
    public string StudioId { get; set; } = "";
    public IReadOnlyList<ExtensionUsage> Extensions { get; set; } = new List<ExtensionUsage>();
    public IReadOnlyList<ExtensionUsage> Plugins => Extensions;

    public static ExtensionUsageReport Parse(JsonElement root)
    {
        var legacy = PluginUsageReport.Parse(root);
        return (ExtensionUsageReport)legacy;
    }

    public static implicit operator ExtensionUsageReport(PluginUsageReport r)
    {
        var list = new List<ExtensionUsage>();
        foreach (var p in r.Plugins)
        {
            list.Add((ExtensionUsage)p);
        }
        return new ExtensionUsageReport
        {
            TitleId = r.TitleId,
            StudioId = r.StudioId,
            Extensions = list
        };
    }
}
