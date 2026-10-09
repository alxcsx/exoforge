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
            root.TryGetProperty("plugins", out var array) &&
            array.ValueKind == JsonValueKind.Array)
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
                               element.TryGetProperty("plugin", out var nested) &&
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

        return new PluginUsage
        {
            PluginId = String(element, "plugin_id"),
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
