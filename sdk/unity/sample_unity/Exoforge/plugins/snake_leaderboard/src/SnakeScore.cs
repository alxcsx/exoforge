using Exoforge.Plugin.SDK;

namespace Exoforge.Plugins.SnakeLeaderboard;

// [ExoResource]/[ExoColumn] describe the row: the Studio renders it and other plugins can
// consume it. Records are the only data type you write — the SDK owns the JSON.
[ExoResource("snake_scores", PrimaryKey = "player_id", DrawerTabs = new[] { "overview", "attributes" })]
public record SnakeScoreRecord
{
    [ExoColumn(Label = "Player ID", Sortable = true, Filterable = true)]
    public string PlayerId { get; init; } = "";

    [ExoColumn(Label = "High Score", Sortable = true)]
    public int Score { get; init; }

    [ExoColumn(Label = "Max Length", Sortable = true)]
    public int SnakeLength { get; init; }

    [ExoColumn(Label = "Updated", Sortable = true)]
    public long UpdatedAt { get; init; }
}

// Wire shape returned by get_leaderboard; the display name is resolved live.
public record SnakeLeaderboardEntry
{
    public string PlayerId { get; init; } = "";
    public string Name { get; init; } = "";
    public int Score { get; init; }
    public int SnakeLength { get; init; }
    public long UpdatedAt { get; init; }
}

// Emitted when a submission actually changes the board. Carries the name so a subscriber can show
// it immediately; the board's own read still resolves names live, so a rename is not left stale.
public record SnakeScoreSubmitted
{
    public string PlayerId { get; init; } = "";
    public string Name { get; init; } = "";
    public int Score { get; init; }
    public int SnakeLength { get; init; }
}
