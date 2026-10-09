using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Exoforge.Client;
using Exoforge.Client.Unity;
using UnityEngine;

namespace SnakeGame
{
    [DefaultExecutionOrder(-750)]
    public class SnakeLeaderboard : MonoBehaviour
    {
        [SerializeField] private SnakeGameController? game;
        [SerializeField] private SnakePlayerController? player;
        [SerializeField] private int topN = 10;

        private const string Topic = "snake:leaderboard";

        private readonly List<SnakeLeaderboardEntry> _rows = new();
        private ExoClient? _client;

        public IReadOnlyList<SnakeLeaderboardEntry> Rows => _rows;
        public string Status { get; private set; } = "not loaded";
        public bool IsBusy { get; private set; }
        public long PersonalBest { get; private set; }
        public bool IsSubscribed { get; private set; }
        public string LastEvent { get; private set; } = "";

        private void Awake()
        {
            game ??= UnityEngine.Object.FindAnyObjectByType<SnakeGameController>(FindObjectsInactive.Include);
            player ??= UnityEngine.Object.FindAnyObjectByType<SnakePlayerController>(FindObjectsInactive.Include);
        }

        private void OnEnable()
        {
            if (game != null) game.RunEnded += OnRunEnded;
            _ = LoadAsync();
        }

        private async Task LoadAsync()
        {
            await SubscribeAsync();
            if (this == null || !isActiveAndEnabled) return;
            await RefreshAsync();
        }

        private void OnDisable()
        {
            if (game != null) game.RunEnded -= OnRunEnded;
            _ = UnsubscribeAsync();
        }

        public async Task SubscribeAsync()
        {
            try
            {
                var client = ExoforgeSDK.Client;
                _client = client;

                client.SnakeLeaderboard().OnScoreSubmitted += OnScoreSubmitted;
                await client.SubscribeAsync(Topic);

                IsSubscribed = true;
                Status = "live";
            }
            catch (Exception ex)
            {
                Status = $"offline: {ex.Message}";
                Debug.LogWarning($"[Snake] could not subscribe: {ex.Message}");
            }
        }

        private async Task UnsubscribeAsync()
        {
            IsSubscribed = false;

            var client = _client;
            if (client == null) return;
            _client = null;

            try
            {
                client.SnakeLeaderboard().OnScoreSubmitted -= OnScoreSubmitted;
                await client.UnsubscribeAsync(Topic);
            }
            catch (Exception)
            {
            }
        }

        private void OnScoreSubmitted(SnakeLeaderboardScoreSubmittedEvent score)
        {
            LastEvent = $"{score.Name} {score.Score}";
            if (string.IsNullOrEmpty(score.PlayerId)) return;

            var row = new SnakeLeaderboardEntry
            {
                PlayerId = score.PlayerId,
                Name = score.Name,
                Score = score.Score,
                SnakeLength = score.SnakeLength
            };

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
                var client = ExoforgeSDK.Client;
                PersonalBest = await client.SnakeLeaderboard().SubmitScoreAsync(
                    session.DisplayName, session.PlayerId, score, length);

                Status = $"submitted {score} — personal best {PersonalBest}";
                await RefreshAsync();
            }
            catch (Exception ex)
            {
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
            if (this == null || !isActiveAndEnabled) return;
            try
            {
                var client = _client ?? ExoforgeSDK.Client;
                var entries = await client.SnakeLeaderboard().GetLeaderboardAsync(topN);

                _rows.Clear();
                if (entries != null) _rows.AddRange(entries);

                Status = IsSubscribed
                    ? $"{_rows.Count} of top {topN} · live"
                    : $"{_rows.Count} of top {topN} loaded";
            }
            catch (Exception ex)
            {
                Status = $"offline: {ex.Message}";
                Debug.LogWarning($"[Snake] could not load leaderboard: {ex.Message}");
            }
        }
    }
}
