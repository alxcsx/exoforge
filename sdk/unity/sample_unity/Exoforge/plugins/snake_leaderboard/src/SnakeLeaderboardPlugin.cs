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

    // Instance rather than static: the host runs one plugin instance and wires that, and a test can
    // wire its own without leaking into the next one.

    // The plugin's own isolated database.
    [Inject("database")]
    public IDatabase? Database { get; set; }

    // The player_data service's contract, generated from the server's plugin list. Injecting the
    // interface means no dependency on its implementation - and a test can hand in a fake.
    [Inject("player_data")]
    public IPlayerDataService? PlayerData { get; set; }

    [Inject]
    public IEventDispatcher? Events { get; set; }

    [Inject]
    public ILogger? Logger { get; set; }

    [ExoAction]
    [ExoEvent("score_submitted", typeof(SnakeScoreSubmitted), Topic = "snake:leaderboard")]
    public async Task<int> SubmitScore(string playerId, string name, int score, int snakeLength)
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

        // Every submission is announced, with `improved` saying whether the board changed. Announcing
        // only improvements looks right and is not: the board keeps its best across runs, so a run
        // that ties the stored score emits nothing, and a subscriber cannot tell that from a broken
        // subscription.
        await Events!.EmitAsync(
            "score_submitted",
            new SnakeScoreSubmitted
            {
                PlayerId = playerId,
                Name = string.IsNullOrEmpty(name) ? playerId : name,
                Score = score,
                SnakeLength = snakeLength,
                Improved = improved
            },
            "snake:leaderboard");

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
    private async Task<string> DisplayNameAsync(string playerId)
    {
        if (PlayerData is null) return playerId;

        var response = await PlayerData.GetPlayerAsync(new PlayerDataGetPlayerRequest { PlayerId = playerId });
        return string.IsNullOrEmpty(response?.Player?.Name) ? playerId : response!.Player!.Name!;
    }
}
