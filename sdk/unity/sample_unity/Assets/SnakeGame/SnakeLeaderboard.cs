using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Threading.Tasks;
using Exoforge.Client;
using Exoforge.Client.Unity;
using UnityEngine;

namespace SnakeGame
{
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

    // The only file in the sample that talks to Exoforge. Gameplay publishes RunEnded; this
    // component bridges it to the generated client. Delete it and Snake still runs.
    [DefaultExecutionOrder(-750)]
    public class SnakeLeaderboard : MonoBehaviour
    {
        [SerializeField] private SnakeGameController? game;
        [SerializeField] private SnakePlayerController? player;
        [SerializeField] private int topN = 10;

        private readonly List<SnakeScoreRow> _rows = new();

        public IReadOnlyList<SnakeScoreRow> Rows => _rows;
        public string Status { get; private set; } = "not loaded";
        public bool IsBusy { get; private set; }
        public long PersonalBest { get; private set; }

        private void Awake()
        {
            game ??= UnityEngine.Object.FindAnyObjectByType<SnakeGameController>(FindObjectsInactive.Include);
            player ??= UnityEngine.Object.FindAnyObjectByType<SnakePlayerController>(FindObjectsInactive.Include);
        }

        private void OnEnable()
        {
            if (game != null) game.RunEnded += OnRunEnded;
        }

        private void OnDisable()
        {
            if (game != null) game.RunEnded -= OnRunEnded;
        }

        private void OnRunEnded(int score, int length) => _ = SubmitRunAsync(score, length);

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
                // The session comes from sign-in and ExoforgeSDK reconnects on its own, so the bridge
                // only asks for the client. Connecting here was redundant in the happy path and
                // raced with the SDK's own reconnect loop when the link had dropped.
                var client = ExoforgeSDK.Client;

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

        public async Task RefreshAsync()
        {
            try
            {
                var client = ExoforgeSDK.Client;
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

        // Tolerant on purpose: a row with a missing or oddly-typed field still shows up.
        public static IReadOnlyList<SnakeScoreRow> ParseRows(JsonElement leaderboard)
        {
            var rows = new List<SnakeScoreRow>();

            if (leaderboard.ValueKind != JsonValueKind.Array) return rows;

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
