using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Exoforge.Client;
using Exoforge.Client.Unity;
using UnityEngine;

namespace SnakeGame
{
    // The only file in the sample that talks to Exoforge. Gameplay publishes RunEnded; this
    // component bridges it to the generated client. Delete it and Snake still runs.
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
            _ = LoadAsync();
        }

        // Subscribe for live updates, then load the current board so the ranking is on screen
        // before the first run ends.
        private async Task LoadAsync()
        {
            await SubscribeAsync();
            await RefreshAsync();
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

                // The generated client raises the typed event, so nothing here reads a JSON frame.
                client.SnakeLeaderboard().OnScoreSubmitted += OnScoreSubmitted;
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
                client.SnakeLeaderboard().OnScoreSubmitted -= OnScoreSubmitted;
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
                // The session comes from sign-in and ExoforgeSDK reconnects on its own, so the bridge
                // only asks for the client. Connecting here was redundant in the happy path and
                // raced with the SDK's own reconnect loop when the link had dropped.
                var client = ExoforgeSDK.Client;

                // submit_score returns the caller's best, so the HUD needs no follow-up read.
                PersonalBest = await client.SnakeLeaderboard().SubmitScoreAsync(
                    session.DisplayName, session.PlayerId, score, length);

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
