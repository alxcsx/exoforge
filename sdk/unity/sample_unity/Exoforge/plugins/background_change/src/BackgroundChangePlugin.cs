using Exoforge.Plugin.SDK;

namespace Exoforge.Plugins;

// A native Exoforge plugin is plain C#. Attributes declare the contract; the host injects
// capabilities; `exo plugin build` produces a self-contained NativeAOT binary.
[ExoService("background_change", Version = "0.1.0", Resources = new[] { typeof(BackgroundChangeItem) },
    Category = "Game", Title = "BackgroundChange", Icon = "🧩")]
public class BackgroundChangePlugin
{
    // The plugin's own isolated database. Instance rather than static: the host runs one plugin
    // instance and wires that, and a test can wire its own without leaking into the next one.
    [Inject("database")]
    public IDatabase? Database { get; set; }

    [Inject]
    public ILogger? Logger { get; set; }

    [ExoAction]
    public string GetColor() => "#FFFFFF";

    [ExoAction]
    public int Echo(int value) => value;
}

// Row stored in the plugin's isolated database.
[ExoResource("background_change_items", PrimaryKey = "id", DrawerTabs = new[] { "overview", "attributes" })]
public record BackgroundChangeItem
{
    [ExoColumn(Label = "Id", Sortable = true, Filterable = true)]
    public string Id { get; init; } = "";

    [ExoColumn(Label = "Owner", Sortable = true, Filterable = true)]
    public string OwnerId { get; init; } = "";

    [ExoColumn(Label = "Quantity", Sortable = true)]
    public int Quantity { get; init; }

    [ExoColumn(Label = "Status", Badge = true)]
    public string Status { get; init; } = "active";
}
