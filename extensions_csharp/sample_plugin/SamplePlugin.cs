using System.Threading.Tasks;
using Exoforge.Plugin.SDK;

namespace Exoforge.Plugins.SamplePlugin;

[ExoService("sample_plugin", Version = "1.0.0", Resources = new[] { typeof(Counter) }, Category = "Utility", Title = "Sample Plugin", Icon = "🔧")]
public class SamplePlugin
{
    private const string Table = "counters";

    [Inject]
    public IDatabase? Database { get; set; }

    [Inject]
    public IEventDispatcher? Events { get; set; }

    [ExoAction("ping")]
    public int Ping() => 42;

    [ExoAction("increment", Scope = "global")]
    public async Task<int> Increment(int counterId, int amount)
    {
        int newValue = amount > 0 ? amount : 1;

        Database!.Put(Table, counterId.ToString(), new Counter(counterId, newValue));
        await Events!.EmitAsync(new CounterChanged(counterId, newValue, amount));

        return newValue;
    }

    [ExoAction("injected")]
    public string Injected() => $"database={Database is not null} events={Events is not null}";

    [ExoAction("echo")]
    public int Echo(int value) => value;
}

[ExoResource("counters", PrimaryKey = "counter_id", DrawerTabs = new[] { "overview", "attributes" })]
public record Counter(
    [property: ExoColumn(Label = "Counter ID", Sortable = true, Filterable = true)] int CounterId = 0,
    [property: ExoColumn(Label = "Value", Sortable = true)] int Value = 0,
    [property: ExoColumn(Label = "Status", Badge = true)] CounterStatus Status = CounterStatus.Active
);

public enum CounterStatus
{
    Active,
    Retired,
    Archived
}

// DTO
[ExoEvent("value_changed", Topic = "sample:events")]
public record CounterChanged(int CounterId = 0, int NewValue = 0, int Delta = 0);
