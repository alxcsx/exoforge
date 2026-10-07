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
        public SnakeScoreRow(string playerId, string name, long score, long length)
        {
            PlayerId = playerId;
            Name = name;
            Score = score;
            Length = length;
        }

        public string PlayerId { get; }
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

        private const string Topic = "snake:leaderboard";
        private const string EventName = "score_submitted";

        private readonly List<SnakeScoreRow> _rows = new();
        private ExoClient? _client;

        public IReadOnlyList<SnakeScoreRow> Rows => _rows;
        public string Status { get; private set; } = "not loaded";
        public bool IsBusy { get; private set; }
        public long PersonalBest { get; private set; }

        /// <summary>True while the board is subscribed to live updates.</summary>
        public bool IsSubscribed { get; private set; }

        /// <summary>The last update that arrived as an event, for the HUD and for tests.</summary>
        public string LastEvent { get; private set; } = "";

        private void Awake()
        {
            game ??= UnityEngine.Object.FindAnyObjectByType<SnakeGameController>(FindObjectsInactive.Include);
            player ??= UnityEngine.Object.FindAnyObjectByType<SnakePlayerController>(FindObjectsInactive.Include);
        }

        private void OnEnable()
        {
            if (game != null) game.RunEnded += OnRunEnded;

            // This is what opens the socket. Everything else this sample does is request/response,
            // which goes over HTTP, and the connection is lazy: subscribing is the first thing that
            // actually needs realtime.
            _ = SubscribeAsync();
        }

        private void OnDisable()
        {
            if (game != null) game.RunEnded -= OnRunEnded;
            _ = UnsubscribeAsync();
        }

        /// <summary>Subscribes to the board so scores land without asking for them.</summary>
        public async Task SubscribeAsync()
        {
            try
            {
                var client = ExoforgeSDK.Client;

                // Held, so unsubscribing does not have to ask for a client. ExoforgeSDK.Client builds
                // one on demand, and OnDisable runs during scene teardown - asking there created a
                // host that outlived everything and poisoned the next test.
                _client = client;

                client.OnAnyEvent += OnEvent;
                await client.SubscribeAsync(Topic);

                IsSubscribed = true;
                Status = "live";
            }
            catch (Exception ex)
            {
                // The sample stays playable offline; only the live board is unavailable.
                Status = $"offline: {ex.Message}";
                Debug.LogWarning($"[Snake] could not subscribe: {ex.Message}");
            }
        }

        private async Task UnsubscribeAsync()
        {
            IsSubscribed = false;

            var client = _client;

            if (client == null)
            {
                return;
            }

            _client = null;

            try
            {
                client.OnAnyEvent -= OnEvent;
                await client.UnsubscribeAsync(Topic);
            }
            catch (Exception)
            {
                // Going away. The server drops the subscription with the connection anyway.
            }
        }

        // A score landed on the board. Merged into the rows we already have rather than re-read: the
        // event carries what the board shows, and not having to ask is the whole point of subscribing.
        // The board's own refresh still resolves names live, so a rename is corrected there.
        private void OnEvent(ExoEventFrame frame)
        {
            if (frame.Event != EventName) return;

            var row = new SnakeScoreRow(
                ReadString(frame.Payload, "player_id"),
                ReadString(frame.Payload, "name"),
                ReadLong(frame.Payload, "score"),
                ReadLong(frame.Payload, "snake_length"));

            if (string.IsNullOrEmpty(row.PlayerId)) return;

            LastEvent = $"{row.Name} {row.Score}";

            int existing = _rows.FindIndex(r => r.PlayerId == row.PlayerId);

            if (existing >= 0)
            {
                _rows[existing] = row;
            }
            else
            {
                _rows.Add(row);
            }

            _rows.Sort((a, b) => b.Score.CompareTo(a.Score));

            if (_rows.Count > topN)
            {
                _rows.RemoveRange(topN, _rows.Count - topN);
            }

            Status = $"{_rows.Count} of top {topN} live";
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
                    ReadString(row, "player_id"),
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
