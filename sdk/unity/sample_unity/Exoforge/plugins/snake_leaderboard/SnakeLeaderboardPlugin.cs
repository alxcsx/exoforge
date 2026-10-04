using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;
using Exoforge.Plugin.SDK;

namespace Exoforge.Plugins.SnakeLeaderboard;

/// <summary>
/// Persisted Snake leaderboard row.
/// </summary>
[ExoResource("snake_scores", PrimaryKey = "player_id", DrawerTabs = new[] { "overview", "attributes" })]
public record SnakeScoreRecord
{
    [ExoColumn(Label = "Player ID", Sortable = true, Filterable = true)]
    public string PlayerId { get; init; } = "";

    [ExoColumn(Label = "Player", Sortable = true, Filterable = true)]
    public string Name { get; init; } = "";

    [ExoColumn(Label = "High Score", Sortable = true)]
    public int Score { get; init; }

    [ExoColumn(Label = "Max Length", Sortable = true)]
    public int SnakeLength { get; init; }

    [ExoColumn(Label = "Updated", Sortable = true)]
    public long UpdatedAt { get; init; }
}

/// <summary>
/// Snake leaderboard. Stores one row per player in the plugin's isolated database (through the
/// host KV bridge) and serves the top-N ranking.
///
/// The row is keyed by <c>player_id</c> and only ever improves: submitting a lower score keeps
/// the stored best.
/// </summary>
[ExoService("snake_leaderboard", Version = "1.0.0", Resources = new[] { typeof(SnakeScoreRecord) },
    Category = "Game", Title = "Snake Leaderboard", Icon = "🏆")]
public class SnakeLeaderboardPlugin
{
    private const string Table = "snake_scores";

    [Inject("database")]
    public static IDatabase? Database { get; set; }

    /// <summary>
    /// Records a finished run for a player, keeping their best score, and returns that best.
    /// </summary>
    [ExoAction("submit_score", Mode = ActionMode.Sync, Transport = ActionTransport.Auto)]
    public int SubmitScore(string playerId, string name, int score, int snakeLength)
    {
        int bestScore = score;
        int bestLength = snakeLength;

        string? existing = HostBridge.DbGet(Table, playerId);

        if (!string.IsNullOrEmpty(existing))
        {
            try
            {
                using var doc = JsonDocument.Parse(existing);
                var row = doc.RootElement;

                if (row.ValueKind == JsonValueKind.Object &&
                    row.TryGetProperty("score", out var storedScore) &&
                    storedScore.GetInt32() >= score)
                {
                    bestScore = storedScore.GetInt32();
                    bestLength = row.TryGetProperty("snake_length", out var storedLength)
                        ? storedLength.GetInt32()
                        : snakeLength;
                }
            }
            catch (JsonException)
            {
                // Corrupt row: overwrite it with the fresh run.
            }
        }

        HostBridge.DbPut(Table, playerId, new JsonObject
        {
            ["player_id"] = playerId,
            ["name"] = name,
            ["score"] = bestScore,
            ["snake_length"] = bestLength,
            ["updated_at"] = DateTimeOffset.UtcNow.ToUnixTimeSeconds()
        });

        HostBridge.LogInfo($"[snake_leaderboard] {name} ({playerId}) best {bestScore}");
        return bestScore;
    }

    /// <summary>
    /// Returns the top <paramref name="limit"/> rows as a JSON array, highest score first.
    /// </summary>
    [ExoAction("get_leaderboard", Mode = ActionMode.Sync, Transport = ActionTransport.Auto)]
    public JsonElement GetLeaderboard(int limit)
    {
        int take = limit > 0 ? limit : 10;
        string raw = HostBridge.DbAll(Table) ?? "[]";

        using var doc = JsonDocument.Parse(raw);
        var rows = new List<JsonNode>();

        if (doc.RootElement.ValueKind == JsonValueKind.Array)
        {
            foreach (var row in doc.RootElement
                         .EnumerateArray()
                         .OrderByDescending(r => r.TryGetProperty("score", out var s) ? s.GetInt32() : 0)
                         .Take(take))
            {
                rows.Add(JsonNode.Parse(row.GetRawText())!);
            }
        }

        return JsonDocument.Parse(new JsonArray(rows.ToArray()).ToJsonString()).RootElement.Clone();
    }

    public static void Main() => PluginHost.Run<SnakeLeaderboardPlugin>();
}
