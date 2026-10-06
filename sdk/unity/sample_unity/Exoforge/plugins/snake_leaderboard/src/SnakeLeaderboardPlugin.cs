using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Exoforge.Plugin.SDK;
using Exoforge.Plugins.Generated;

namespace Exoforge.Plugins.SnakeLeaderboard;

// A native Exoforge plugin is plain C#. Attributes declare the contract; the host injects
// capabilities; `exo plugin build` produces a self-contained NativeAOT binary.
[ExoService("snake_leaderboard", Version = "1.0.0", Resources = new[] { typeof(SnakeScoreRecord) },
    Category = "Game", Title = "Snake Leaderboard", Icon = "🏆")]
public class SnakeLeaderboardPlugin
{
    private const string Table = "snake_scores";

    // The plugin's own isolated database.
    [Inject("database")]
    public static IDatabase? Database { get; set; }

    // Typed client generated from the player_data contract — no dependency on its implementation.
    [Inject("player_data")]
    public static PlayerDataServiceClient? PlayerData { get; set; }

    [Inject]
    public static ILogger? Logger { get; set; }

    [ExoAction]
    [ExoEvent("score_submitted", typeof(SnakeScoreSubmitted), Topic = "snake:leaderboard")]
    public int SubmitScore(string playerId, string name, int score, int snakeLength)
    {
        var existing = Database!.Get<SnakeScoreRecord>(Table, playerId);
        bool improved = existing is null || existing.Score < score;

        var best = new SnakeScoreRecord
        {
            PlayerId = playerId,
            Score = improved ? score : existing!.Score,
            SnakeLength = improved ? snakeLength : existing!.SnakeLength,
            UpdatedAt = DateTimeOffset.UtcNow.ToUnixTimeSeconds()
        };

        Database.Put(Table, playerId, best);
        Logger?.Info($"[snake_leaderboard] {playerId} best {best.Score}");

        // Only when the board actually changed. A worse run is not a leaderboard update, and
        // broadcasting it would make every subscriber re-read for nothing.
        if (improved)
        {
            HostBridge.EmitEvent("snake:leaderboard", "score_submitted", new SnakeScoreSubmitted
            {
                PlayerId = playerId,
                Name = string.IsNullOrEmpty(name) ? playerId : name,
                Score = best.Score,
                SnakeLength = best.SnakeLength
            });
        }

        return best.Score;
    }

    [ExoAction]
    public async Task<List<SnakeLeaderboardEntry>> GetLeaderboard(int limit)
    {
        var entries = new List<SnakeLeaderboardEntry>();

        foreach (var score in Database!.All<SnakeScoreRecord>(Table)
                     .OrderByDescending(row => row.Score)
                     .Take(limit > 0 ? limit : 10))
        {
            entries.Add(new SnakeLeaderboardEntry
            {
                PlayerId = score.PlayerId,
                Name = await DisplayNameAsync(score.PlayerId),
                Score = score.Score,
                SnakeLength = score.SnakeLength,
                UpdatedAt = score.UpdatedAt
            });
        }

        return entries;
    }

    // Names are resolved at read time, so a rename never leaves a stale name on the board.
    private static async Task<string> DisplayNameAsync(string playerId)
    {
        if (PlayerData is null) return playerId;

        var response = await PlayerData.GetPlayerAsync(new PlayerDataGetPlayerRequest { PlayerId = playerId });
        return string.IsNullOrEmpty(response?.Player?.Name) ? playerId : response!.Player!.Name!;
    }

    public static void Main() => PluginHost.Run<SnakeLeaderboardPlugin, SnakeJsonContext>();
}
