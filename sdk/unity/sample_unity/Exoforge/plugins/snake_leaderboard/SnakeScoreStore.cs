using System.Collections.Generic;
using System.Linq;
using Exoforge.Plugin.SDK;

namespace Exoforge.Plugins.SnakeLeaderboard;

/// <summary>
/// Persistence for leaderboard rows, on top of the plugin's isolated <see cref="IDatabase"/>.
/// Keeps all storage details out of the plugin actions.
/// </summary>
public sealed class SnakeScoreStore
{
    private const string Table = "snake_scores";

    private readonly IDatabase _database;

    public SnakeScoreStore(IDatabase database)
    {
        _database = database;
    }

    /// <summary>The player's stored best, or <c>null</c> if they have never played.</summary>
    public SnakeScoreRecord? Get(string playerId) => _database.Get<SnakeScoreRecord>(Table, playerId);

    /// <summary>Writes (overwrites) the player's row.</summary>
    public void Put(SnakeScoreRecord score) => _database.Put(Table, score.PlayerId, score);

    /// <summary>The highest scores first, capped at <paramref name="limit"/>.</summary>
    public IReadOnlyList<SnakeScoreRecord> Top(int limit) =>
        _database.All<SnakeScoreRecord>(Table)
            .OrderByDescending(score => score.Score)
            .Take(limit)
            .ToList();
}
