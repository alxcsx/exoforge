using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Exoforge.Plugin.SDK;
using Exoforge.Plugins.Generated;

namespace Exoforge.Plugins.SnakeLeaderboard;

[ExoService("snake_leaderboard", Version = "1.0.0", Resources = new[] { typeof(SnakeScoreRecord) },
    Category = "Game", Title = "Snake Leaderboard", Icon = "🏆")]
public class SnakeLeaderboardPlugin
{
    [ExoAction]
    public async Task<int> SubmitScore(string playerId, string name, int score, int snakeLength)
    {
        var existing = ExoServices.Database.Get<SnakeScoreRecord>(playerId);
        bool improved = existing is null || existing.Score < score;
        long now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();

        var best = existing != null && !improved
            ? existing
            : new SnakeScoreRecord(playerId, Math.Max(score, existing?.Score ?? 0), improved ? snakeLength : existing?.SnakeLength ?? snakeLength, now);

        ExoServices.Database.Put(best);
        ExoServices.Logger.Info($"[snake_leaderboard] {playerId} best {best.Score}");

        var submittedName = string.IsNullOrEmpty(name) ? playerId : name;
        await ExoServices.Events.EmitAsync(new SnakeScoreSubmitted(playerId, submittedName, score, snakeLength, improved));

        return best.Score;
    }

    [ExoAction]
    public async Task<List<SnakeLeaderboardEntry>> GetLeaderboard(int limit)
    {
        var scores = ExoServices.Database.All<SnakeScoreRecord>().OrderByDescending(s => s.Score).Take(limit > 0 ? limit : 10);
        var entries = new List<SnakeLeaderboardEntry>();

        foreach (var score in scores)
        {
            entries.Add(score.ToEntry(await DisplayNameAsync(score.PlayerId)));
        }

        return entries;
    }

    private async Task<string> DisplayNameAsync(string playerId)
    {
        try
        {
            var response = await ExoServices.PlayerData.GetPlayerAsync(new PlayerDataGetPlayerRequest { PlayerId = playerId });
            return string.IsNullOrEmpty(response?.Player?.Name) ? playerId : response!.Player!.Name!;
        }
        catch
        {
            return playerId;
        }
    }
}

[ExoResource("snake_scores", PrimaryKey = "player_id", DrawerTabs = new[] { "overview", "attributes" })]
public record SnakeScoreRecord(
    [property: ExoColumn(Label = "Player ID", Sortable = true, Filterable = true, Role = "user_id")] string PlayerId = "",
    [property: ExoColumn(Label = "High Score", Sortable = true)] int Score = 0,
    [property: ExoColumn(Label = "Max Length", Sortable = true)] int SnakeLength = 0,
    [property: ExoColumn(Label = "Updated", Sortable = true)] long UpdatedAt = 0
)
{
    public SnakeLeaderboardEntry ToEntry(string name) => new(PlayerId, name, Score, SnakeLength, UpdatedAt);
}

// DTOs
public record SnakeLeaderboardEntry(
    string PlayerId = "",
    string Name = "",
    int Score = 0,
    int SnakeLength = 0,
    long UpdatedAt = 0
);

[ExoEvent("score_submitted", Topic = "snake:leaderboard")]
public record SnakeScoreSubmitted(
    string PlayerId = "",
    string Name = "",
    int Score = 0,
    int SnakeLength = 0,
    bool Improved = false
);
