using System.Text.Json.Serialization;
using Exoforge.Plugin.SDK;

namespace Exoforge.Plugins.SnakeLeaderboard;

// [ExoResource]/[ExoColumn] describe the row: the Studio renders it and other plugins can
// consume it. Records are the only data type you write — the SDK owns the JSON.
[ExoResource("snake_scores", PrimaryKey = "player_id", DrawerTabs = new[] { "overview", "attributes" })]
public record SnakeScoreRecord
{
    [ExoColumn(Label = "Player ID", Sortable = true, Filterable = true, Role = "user_id")]
    [JsonPropertyName("player_id")]
    public string PlayerId { get; init; } = "";

    [ExoColumn(Label = "High Score", Sortable = true)]
    [JsonPropertyName("score")]
    public int Score { get; init; }

    [ExoColumn(Label = "Max Length", Sortable = true)]
    [JsonPropertyName("snake_length")]
    public int SnakeLength { get; init; }

    [ExoColumn(Label = "Updated", Sortable = true)]
    [JsonPropertyName("updated_at")]
    public long UpdatedAt { get; init; }
}

// Wire shape returned by get_leaderboard; the display name is resolved live.
public record SnakeLeaderboardEntry
{
    [JsonPropertyName("player_id")]
    public string PlayerId { get; init; } = "";

    [JsonPropertyName("name")]
    public string Name { get; init; } = "";

    [JsonPropertyName("score")]
    public int Score { get; init; }

    [JsonPropertyName("snake_length")]
    public int SnakeLength { get; init; }

    [JsonPropertyName("updated_at")]
    public long UpdatedAt { get; init; }
}

// Emitted when a submission actually changes the board. Carries the name so a subscriber can show
// it immediately; the board's own read still resolves names live, so a rename is not left stale.
public record SnakeScoreSubmitted
{
    [JsonPropertyName("player_id")]
    public string PlayerId { get; init; } = "";

    [JsonPropertyName("name")]
    public string Name { get; init; } = "";

    [JsonPropertyName("score")]
    public int Score { get; init; }

    [JsonPropertyName("snake_length")]
    public int SnakeLength { get; init; }

    [JsonPropertyName("improved")]
    public bool Improved { get; init; }
}
