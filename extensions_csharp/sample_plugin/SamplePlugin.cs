using System.Threading.Tasks;
using Exoforge.Plugin.SDK;

namespace Exoforge.Plugins.SamplePlugin;

[ExoService("sample_plugin", Version = "1.0.0", Resources = new[] { typeof(Counter) }, Category = "Utility", Title = "Sample Plugin", Icon = "🔧")]
public class SamplePlugin
{
    [ExoAction("ping")]
    public int Ping() => 42;

    [ExoAction("increment", Scope = "global")]
    public async Task<int> Increment(int counterId, int amount)
    {
        int newValue = amount > 0 ? amount : 1;

        ExoServices.Database.Put(new Counter(counterId, newValue));
        await ExoServices.Events.EmitAsync(new CounterChanged(counterId, newValue, amount));

        return newValue;
    }

    [ExoAction("injected")]
    public string Injected() => $"database={ExoServices.Database is not null} events={ExoServices.Events is not null}";

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
