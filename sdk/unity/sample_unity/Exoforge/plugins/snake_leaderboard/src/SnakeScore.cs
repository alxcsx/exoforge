using Exoforge.Plugin.SDK;

namespace Exoforge.Plugins.SnakeLeaderboard;

/// <summary>
/// Stored leaderboard row, keyed by <c>player_id</c>.
///
/// The player's display name is deliberately **not** stored here. It is joined from the
/// <c>player_data</c> profile when the leaderboard is read, so renaming a player never leaves a
/// stale name on the board.
/// </summary>
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

/// <summary>
/// One leaderboard row as returned to clients: the stored score plus the player's **current**
/// display name, resolved at read time.
/// </summary>
public record SnakeLeaderboardEntry
{
    public string PlayerId { get; init; } = "";
    public string Name { get; init; } = "";
    public int Score { get; init; }
    public int SnakeLength { get; init; }
    public long UpdatedAt { get; init; }
}
