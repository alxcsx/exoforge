using System;
using System.Text.Json.Nodes;
using Exoforge.Plugin.SDK;

namespace Exoforge.Plugins.SnakeServer;

/// <summary>
/// Persisted Snake leaderboard row.
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

    [ExoColumn(Label = "Apples Eaten", Sortable = true)]
    public int ApplesEaten { get; init; }
}

public record FoodSpawnedPayload(int X, int Y, int Points);
public record GameOverPayload(string PlayerId, int FinalScore, string Reason);
public record ChallengeReceivedPayload(string FromPlayer, int ScoreToBeat, string Message);

/// <summary>
/// Authoritative Snake game server.
///
/// Plain C# — no WASM, no C. <see cref="Main"/> hands control to the SDK host loop, which reads
/// action requests from stdin, dispatches them to the <c>[ExoAction]</c> methods below, and writes
/// results back. Host capabilities (events, database) go through <see cref="HostBridge"/>.
/// </summary>
[ExoService("snake_server", Version = "1.0.0", Resources = new[] { typeof(SnakeScoreRecord) },
    Category = "Game", Title = "Snake Server", Icon = "🐍")]
public class SnakeServerPlugin
{
    // Authoritative match state (one active match per plugin process).
    private int _width = 20, _height = 20;
    private int _headX, _headY;
    private int _length, _score, _apples, _alive;
    private int _foodX, _foodY;

    /// <summary>Starts a match and spawns the first apple.</summary>
    [ExoAction("start_game", Mode = ActionMode.Sync, Transport = ActionTransport.Auto)]
    [ExoEvent("food_spawned", typeof(FoodSpawnedPayload), Topic = "snake:events")]
    public int StartGame(int width, int height)
    {
        _width = width > 0 ? width : 20;
        _height = height > 0 ? height : 20;
        _headX = _width / 4;
        _headY = _height / 2;
        _length = 3;
        _score = 0;
        _apples = 0;
        _alive = 1;
        _foodX = _width / 2;
        _foodY = _height / 2;

        EmitFood();
        HostBridge.LogInfo($"[snake_server] match started on {_width}x{_height}");
        return 1;
    }

    /// <summary>Authoritative movement step: validates the move and resolves collisions.</summary>
    [ExoAction("move", Mode = ActionMode.Sync, Transport = ActionTransport.WebSocket)]
    [ExoEvent("food_spawned", typeof(FoodSpawnedPayload), Topic = "snake:events")]
    [ExoEvent("game_over", typeof(GameOverPayload), Topic = "snake:events")]
    public int Move(int currentX, int currentY, int direction, int foodX, int foodY)
    {
        if (_alive == 0) return 0;

        int nx = currentX, ny = currentY;
        switch (direction)
        {
            case 0: ny -= 1; break;
            case 1: nx += 1; break;
            case 2: ny += 1; break;
            case 3: nx -= 1; break;
        }

        if (nx < 0 || nx >= _width || ny < 0 || ny >= _height)
        {
            _alive = 0;
            HostBridge.EmitEvent("snake:events", "game_over", new JsonObject
            {
                ["player_id"] = "player",
                ["final_score"] = _score,
                ["reason"] = "wall_collision"
            });
            return 0;
        }

        _headX = nx;
        _headY = ny;

        if (nx == foodX && ny == foodY)
        {
            _score += 10;
            _apples += 1;
            _length += 1;
            SpawnFood();
            EmitFood();
            return 2;
        }

        return 1;
    }

    /// <summary>Persists a finished run and returns the player's rank.</summary>
    [ExoAction("submit_score", Mode = ActionMode.Sync, Transport = ActionTransport.Http)]
    public int SubmitScore(int score, int snakeLength)
    {
        HostBridge.DbPut("snake_scores", $"run_{score}",
            new JsonObject { ["score"] = score, ["snake_length"] = snakeLength });

        if (score >= 500) return 1;
        if (score >= 200) return 2;
        return 5;
    }

    /// <summary>Returns how many leaderboard rows the caller may read.</summary>
    [ExoAction("get_leaderboard", Mode = ActionMode.Sync, Transport = ActionTransport.Http)]
    public int GetLeaderboard(int limit) => limit > 0 ? limit : 10;

    /// <summary>Broadcasts a social challenge to another player.</summary>
    [ExoAction("send_challenge", Mode = ActionMode.Sync, Transport = ActionTransport.Auto)]
    [ExoEvent("challenge_received", typeof(ChallengeReceivedPayload), Topic = "snake:social")]
    public int SendChallenge(int scoreToBeat)
    {
        HostBridge.EmitEvent("snake:social", "challenge_received", new JsonObject
        {
            ["from_player"] = "challenger",
            ["score_to_beat"] = scoreToBeat,
            ["message"] = "Can you beat my score?"
        });
        return 1;
    }

    private void EmitFood() =>
        HostBridge.EmitEvent("snake:events", "food_spawned", new JsonObject
        {
            ["x"] = _foodX,
            ["y"] = _foodY,
            ["points"] = 10
        });

    private void SpawnFood()
    {
        _foodX = (_foodX + 7) % _width;
        _foodY = (_foodY + 11) % _height;
    }

    public static void Main() => PluginHost.Run<SnakeServerPlugin>();
}
