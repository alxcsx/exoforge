using System;
using System.Runtime.InteropServices;
using Exoforge.Plugin.SDK;

namespace Exoforge.Plugins.SampleWasm;

/// <summary>
/// Domain resource representing a stored counter entry.
/// </summary>
[ExoResource("counters", PrimaryKey = "counter_id", DrawerTabs = new[] { "overview", "attributes" })]
public record Counter
{
    [ExoColumn(Label = "Counter ID", Sortable = true, Filterable = true)]
    public int CounterId { get; init; }

    [ExoColumn(Label = "Value", Sortable = true)]
    public int Value { get; init; }

    [ExoColumn(Label = "Status", Badge = true)]
    public string Status { get; init; } = "active";
}

/// <summary>
/// Generic sample WASM plugin demonstrating Exoforge Plugin SDK features:
/// - Actions (sync operations)
/// - Events (emitting to topics)
/// - Resources (with columns for dashboard display)
/// - Database injection
/// - HostBridge usage for event emission
/// </summary>
[ExoService("sample_wasm", Version = "1.0.0", Resources = new[] { typeof(Counter) }, Category = "Utility", Title = "Sample WASM Plugin", Icon = "🔧")]
public static class SampleWasmPlugin
{
    [Inject("database")]
    public static IDatabase? Database { get; set; }

    /// <summary>
    /// Ping action returning status 42 (pong).
    /// Demonstrates a simple sync action.
    /// </summary>
    [ExoAction("ping", Mode = ActionMode.Sync)]
    [UnmanagedCallersOnly(EntryPoint = "ping")]
    public static int Ping()
    {
        return 42;
    }

    /// <summary>
    /// Increments a counter and emits a 'value_changed' event.
    /// Demonstrates event emission via HostBridge.
    /// </summary>
    [ExoAction("increment", Mode = ActionMode.Sync, Scope = "global")]
    [ExoEvent("value_changed", Topic = "sample:events")]
    [UnmanagedCallersOnly(EntryPoint = "increment")]
    public static int Increment(int counterId, int amount)
    {
        int newValue = amount > 0 ? amount : 1;

        HostBridge.EmitEvent("sample:events", "value_changed", new
        {
            counter_id = counterId,
            new_value = newValue,
            delta = amount
        });

        return newValue;
    }

    /// <summary>
    /// Echo action that returns the input value.
    /// Demonstrates simple data pass-through.
    /// </summary>
    [ExoAction("echo", Mode = ActionMode.Sync)]
    [UnmanagedCallersOnly(EntryPoint = "echo")]
    public static int Echo(int value)
    {
        return value;
    }

    public static void Main()
    {
    }
}
