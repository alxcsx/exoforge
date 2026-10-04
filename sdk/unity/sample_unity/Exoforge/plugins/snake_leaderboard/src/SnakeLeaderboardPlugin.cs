using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Exoforge.Plugin.SDK;
using Exoforge.Plugins.Generated;

namespace Exoforge.Plugins.SnakeLeaderboard;

/// <summary>
/// Snake leaderboard service. Stores one score row per player in the plugin's isolated database and
/// serves a shared top-N ranking. Player names are resolved from <c>player_data</c> at read time.
///
/// Deliberately thin: the point of this sample is to show the base system, so the actions talk to
/// <see cref="IDatabase"/> directly instead of hiding it behind a repository.
/// </summary>
[ExoService("snake_leaderboard", Version = "1.0.0", Resources = new[] { typeof(SnakeScoreRecord) },
    Category = "Game", Title = "Snake Leaderboard", Icon = "🏆")]
public class SnakeLeaderboardPlugin
{
    private const string Table = "snake_scores";

    [Inject("database")]
    public static IDatabase? Database { get; set; }

    // Declares the :player_data dependency (load order) and injects the dispatcher used to resolve names.
    [Inject("player_data")]
    public static IActionDispatcher? Actions { get; set; }

    [Inject]
    public static ILogger? Logger { get; set; }

    private static ExoforgePluginServices? _services;

    /// <summary>Typed access to other service contracts, generated from the cluster contracts.</summary>
    private static ExoforgePluginServices Services => _services ??= new ExoforgePluginServices(Actions!);

    /// <summary>
    /// Records a finished run for a player, keeping their best score, and returns that best.
    /// </summary>
    [ExoAction]
    public int SubmitScore(string playerId, string name, int score, int snakeLength)
    {
        // `name` is kept for wire compatibility but not stored: the board renders the live name from
        // player_data, so a rename can never leave a stale name behind.
        _ = name;

        var existing = Database!.Get<SnakeScoreRecord>(Table, playerId);
        bool improved = existing is null || existing.Score < score;

        int bestScore = improved ? score : existing!.Score;
        int bestLength = improved ? snakeLength : existing!.SnakeLength;

        Database.Put(Table, playerId, new SnakeScoreRecord
        {
            PlayerId = playerId,
            Score = bestScore,
            SnakeLength = bestLength,
            UpdatedAt = DateTimeOffset.UtcNow.ToUnixTimeSeconds()
        });

        Logger?.Info($"[snake_leaderboard] {playerId} best {bestScore}");
        return bestScore;
    }

    /// <summary>
    /// Returns the top <paramref name="limit"/> rows, highest score first, with each player's current
    /// display name joined from <c>player_data</c>. Returning a <see cref="Task{TResult}"/> makes the
    /// manifest infer <c>mode: :async</c>.
    /// </summary>
    [ExoAction]
    public async Task<List<SnakeLeaderboardEntry>> GetLeaderboard(int limit)
    {
        int take = limit > 0 ? limit : 10;

        var top = Database!.All<SnakeScoreRecord>(Table)
            .OrderByDescending(score => score.Score)
            .Take(take);

        var entries = new List<SnakeLeaderboardEntry>();

        foreach (var score in top)
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

    /// <summary>Current display name from player_data; falls back to the raw id when unavailable.</summary>
    private static async Task<string> DisplayNameAsync(string playerId)
    {
        if (Actions is null) return playerId;

        // Typed call generated from the player_data contract (`exo plugin stubs`): no dependency on the
        // service implementation and no hand-written DTOs.
        var response = await Services.PlayerData
            .GetPlayerAsync(new PlayerDataGetPlayerRequest { PlayerId = playerId });

        string? name = response?.Player?.Name;
        return string.IsNullOrEmpty(name) ? playerId : name!;
    }

    public static void Main() => PluginHost.Run<SnakeLeaderboardPlugin, SnakeJsonContext>();
}
