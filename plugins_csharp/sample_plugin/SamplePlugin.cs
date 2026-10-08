using Exoforge.Plugin.SDK;

namespace Exoforge.Plugins.SamplePlugin;

/// <summary>A stored counter, as the dashboard shows it.</summary>
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
/// The reference plugin: one instance, injected dependencies, actions that emit events.
///
/// It is a native plugin — compiled to a single binary the server runs as a process. It used to be
/// the WASM sample; that runtime is gone for now, and the shape of a plugin is the same either way,
/// which is the point of it being the reference.
/// </summary>
[ExoService("sample_plugin", Version = "1.0.0", Resources = new[] { typeof(Counter) }, Category = "Utility", Title = "Sample Plugin", Icon = "🔧")]
public class SamplePlugin
{
    [Inject("database")]
    public IDatabase? Database { get; set; }

    [Inject]
    public IEventDispatcher? Events { get; set; }

    /// <summary>Answers 42.</summary>
    [ExoAction("ping")]
    public int Ping() => 42;

    /// <summary>Increments a counter and announces it on a topic.</summary>
    [ExoAction("increment", Scope = "global")]
    [ExoEvent("value_changed", Topic = "sample:events")]
    public async Task<int> Increment(int counterId, int amount)
    {
        int newValue = amount > 0 ? amount : 1;

        await Events!.EmitAsync(
            "value_changed",
            new { counter_id = counterId, new_value = newValue, delta = amount },
            "sample:events");

        return newValue;
    }

    /// <summary>
    /// What the host actually injected. Temporary: this is how the `Object reference not set` in
    /// `Increment` gets located - whether the property is null, or whether it was never found.
    /// </summary>
    [ExoAction("injected")]
    public string Injected() => $"database={Database is not null} events={Events is not null}";

    /// <summary>Returns what it was given.</summary>
    [ExoAction("echo")]
    public int Echo(int value) => value;
}
