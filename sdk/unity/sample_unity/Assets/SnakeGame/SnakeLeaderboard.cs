using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Threading.Tasks;
using Exoforge.Client;
using Exoforge.Client.Unity;
using UnityEngine;

namespace SnakeGame
{
    /// <summary>One row of the shared leaderboard.</summary>
    public readonly struct SnakeScoreRow
    {
        public SnakeScoreRow(string name, long score, long length)
        {
            Name = name;
            Score = score;
            Length = length;
        }

        public string Name { get; }
        public long Score { get; }
        public long Length { get; }
    }

    /// <summary>
    /// The bridge between the game and the server. This is the only place in the sample that talks
    /// to Exoforge: it listens for <see cref="SnakeGameController.RunEnded"/> and forwards the score
    /// to the <c>snake_leaderboard</c> plugin.
    ///
    /// Gameplay itself knows nothing about the backend — swap this component out and Snake still runs.
    ///
    /// Lives on an always-active object so the subscription is in place before the first run ends.
    /// </summary>
    [DefaultExecutionOrder(-750)]
    public class SnakeLeaderboard : MonoBehaviour
    {
        [SerializeField] private SnakeGameController? game;
        [SerializeField] private SnakePlayerController? player;
        [SerializeField] private int topN = 10;

        private readonly List<SnakeScoreRow> _rows = new();

        /// <summary>The current ranking, highest first.</summary>
        public IReadOnlyList<SnakeScoreRow> Rows => _rows;

        /// <summary>Last thing that happened, for the HUD.</summary>
        public string Status { get; private set; } = "not loaded";

        public bool IsBusy { get; private set; }

        /// <summary>This player's best score, as last reported by the server.</summary>
        public long PersonalBest { get; private set; }

        private void Awake()
        {
            game ??= UnityEngine.Object.FindAnyObjectByType<SnakeGameController>(FindObjectsInactive.Include);
            player ??= UnityEngine.Object.FindAnyObjectByType<SnakePlayerController>(FindObjectsInactive.Include);
        }

        private void OnEnable()
        {
            if (game != null)
            {
                game.RunEnded += OnRunEnded;
            }
        }

        private void OnDisable()
        {
            if (game != null)
            {
                game.RunEnded -= OnRunEnded;
            }
        }

        private void OnRunEnded(int score, int length) => _ = SubmitRunAsync(score, length);

        /// <summary>Records a finished run on the server, then refreshes the ranking.</summary>
        public async Task SubmitRunAsync(int score, int length)
        {
            var session = player?.Session;

            if (session == null || string.IsNullOrEmpty(session.PlayerId))
            {
                Status = "not signed in — score not submitted";
                return;
            }

            IsBusy = true;
            Status = "submitting…";

            try
            {
                var client = await ExoforgeSDK.ConnectAsync();

                var best = await client.SnakeLeaderboard().SubmitScoreAsync(
                    session.DisplayName, session.PlayerId, score, length);

                PersonalBest = ReadLong(best);
                Status = $"submitted {score} — personal best {PersonalBest}";

                await RefreshAsync();
            }
            catch (Exception ex)
            {
                // The sample stays playable offline; only the shared board is unavailable.
                Status = $"offline: {ex.Message}";
                Debug.LogWarning($"[Snake] leaderboard unavailable: {ex.Message}");
            }
            finally
            {
                IsBusy = false;
            }
        }

        /// <summary>Reloads the ranking from the server.</summary>
        public async Task RefreshAsync()
        {
            try
            {
                var client = await ExoforgeSDK.ConnectAsync();
                var result = await client.SnakeLeaderboard().GetLeaderboardAsync(topN);

                _rows.Clear();
                _rows.AddRange(ParseRows(result));

                Status = $"{_rows.Count} of top {topN} loaded";
            }
            catch (Exception ex)
            {
                Status = $"offline: {ex.Message}";
                Debug.LogWarning($"[Snake] could not load leaderboard: {ex.Message}");
            }
        }

        /// <summary>
        /// Reads the rows the plugin returns. Tolerant on purpose: a row with a missing or
        /// oddly-typed field still shows up, just with a placeholder value.
        /// </summary>
        public static IReadOnlyList<SnakeScoreRow> ParseRows(JsonElement leaderboard)
        {
            var rows = new List<SnakeScoreRow>();

            if (leaderboard.ValueKind != JsonValueKind.Array)
            {
                return rows;
            }

            foreach (var row in leaderboard.EnumerateArray())
            {
                rows.Add(new SnakeScoreRow(
                    ReadString(row, "name"),
                    ReadLong(row, "score"),
                    ReadLong(row, "snake_length")));
            }

            return rows;
        }

        private static long ReadLong(JsonElement element) =>
            element.ValueKind == JsonValueKind.Number ? element.GetInt64() : 0;

        private static long ReadLong(JsonElement row, string property) =>
            row.ValueKind == JsonValueKind.Object && row.TryGetProperty(property, out var value)
                ? ReadLong(value)
                : 0;

        private static string ReadString(JsonElement row, string property) =>
            row.ValueKind == JsonValueKind.Object && row.TryGetProperty(property, out var value)
                ? value.GetString() ?? "?"
                : "?";
    }
}
