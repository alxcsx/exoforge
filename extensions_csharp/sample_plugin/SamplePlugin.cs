using System.Threading.Tasks;
using Exoforge.Plugin.SDK;

namespace Exoforge.Plugins.SamplePlugin;

[ExoService("sample_plugin", Version = "0.1.0", Resources = new[] { typeof(Counter) }, Category = "Utility", Title = "Sample Plugin", Icon = "🔧")]
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

    /// <summary>Writes log lines in four ways, to see which of them reach the Studio's Logs tab.</summary>
    [ExoAction("log_demo")]
    public string LogDemo(int lines, bool console)
    {
        for (int i = 1; i <= lines; i++) Exo.Logger.Info($"log_demo line {i}");
        Exo.Logger.Warning("log_demo warning");
        Exo.Logger.Error("log_demo error");

        if (console)
        {
            // Not through the SDK: stdout is the wire to the host, stderr is the process's own.
            System.Console.WriteLine("log_demo plain stdout line");
            System.Console.Error.WriteLine("log_demo plain stderr line");
        }

        return $"wrote {lines}";
    }

    [ExoAction("get_many")]
    public List<Counter> GetMany(List<int> ids)
    {
        var result = new List<Counter>();
        if (ids is null || ids.Count == 0) return result;
        foreach (var id in ids)
        {
            var counter = ExoServices.Database.Get<Counter>(id);
            if (counter is not null) result.Add(counter);
        }
        return result;
    }
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
