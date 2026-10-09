using Exoforge.Plugin.SDK;

namespace Exoforge.Plugins.SamplePlugin;

/// <summary>What a counter did, as the event carries it. A record, not an anonymous object: the
/// generated JSON context can only carry a declared type.</summary>
public record CounterChanged
{
    public int CounterId { get; init; }
    public int NewValue { get; init; }
    public int Delta { get; init; }
}

/// <summary>
/// What a counter can be. Declaring this is the whole declaration of the column's choices - the
/// generator reads the names, and the schema, the form and the database's own constraint all follow
/// from it.
/// </summary>
public enum CounterStatus
{
    Active,
    Retired,
    Archived
}

/// <summary>A stored counter, as the dashboard shows it.</summary>
[ExoResource("counters", PrimaryKey = "counter_id", DrawerTabs = new[] { "overview", "attributes" })]
public record Counter
{
    [ExoColumn(Label = "Counter ID", Sortable = true, Filterable = true)]
    public int CounterId { get; init; }

    [ExoColumn(Label = "Value", Sortable = true)]
    public int Value { get; init; }

    [ExoColumn(Label = "Status", Badge = true)]
    public CounterStatus Status { get; init; } = CounterStatus.Active;
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

    /// <summary>
    /// Increments a counter, stores it, and announces it on a topic.
    ///
    /// It writes through SQL rather than the key-value bridge because the resource declares a table -
    /// which is what the schema says and what the dashboard reads.
    /// </summary>
    [ExoAction("increment", Scope = "global")]
    [ExoEvent("value_changed", typeof(CounterChanged), Topic = "sample:events")]
    public async Task<int> Increment(int counterId, int amount)
    {
        int newValue = amount > 0 ? amount : 1;

        // `status` is left to the column's default, which came from the enum's own value.
        Database!.Execute(
            "INSERT INTO counters (counter_id, value) VALUES ($1, $2) " +
            "ON CONFLICT(counter_id) DO UPDATE SET value = excluded.value",
            counterId,
            newValue);

        await Events!.EmitAsync(
            "value_changed",
            new CounterChanged { CounterId = counterId, NewValue = newValue, Delta = amount },
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
