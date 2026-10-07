using System;
using UnityEngine;

namespace SnakeGame
{
    /// <summary>
    /// Everything the player sees: the board, the score, the name prompt, the leaderboard.
    ///
    /// Deliberately primitive — the board is a <c>gridWidth × gridHeight</c> point-filtered texture
    /// where one pixel <em>is</em> one coloured square, and the panels are IMGUI. No art, no prefab,
    /// no Canvas, so the sample stays about the Exoforge integration rather than about Unity setup.
    ///
    /// This component lives on an always-active object: the name prompt has to work before
    /// gameplay is switched on.
    /// </summary>
    [DefaultExecutionOrder(-700)]
    public class SnakeGameView : MonoBehaviour
    {
        [Header("Layout")]
        [SerializeField] private float panelWidth = 320f;

        [Header("Scene")]
        [SerializeField] private SnakeGameController? game;
        [SerializeField] private SnakePlayerController? player;
        [SerializeField] private SnakeLeaderboard? leaderboard;


        private string _nameInput = "";
        private bool _submittingName;
        private string _nameError = "";

        private void Awake()
        {
            // Refs are wired by the scene setup; fall back to a search so hand-edited scenes work.
            game ??= FindAny<SnakeGameController>();
            player ??= FindAny<SnakePlayerController>();
            leaderboard ??= FindAny<SnakeLeaderboard>();
        }

        private void OnEnable()
        {
            if (player != null)
            {
                player.DisplayNameRequired += OnDisplayNameRequired;
            }
        }

        private void OnDisable()
        {
            if (player != null)
            {
                player.DisplayNameRequired -= OnDisplayNameRequired;
            }
        }

        private void OnDisplayNameRequired()
        {
            _nameInput = "";
            _nameError = "";
        }

        private static T? FindAny<T>() where T : Component =>
            UnityEngine.Object.FindAnyObjectByType<T>(FindObjectsInactive.Include);

        // ---- board -------------------------------------------------------------------------

        // ---- hud ---------------------------------------------------------------------------

        private void OnGUI()
        {
            if (game == null) return;

            // The board is drawn with sprites (SnakeBoardView); this is the panel beside it.
            DrawScorePanel(new Rect(20f, 20f, panelWidth, Mathf.Min(Screen.height - 40f, 560f)));

            if (player != null && player.NeedsDisplayName)
            {
                DrawNamePrompt();
            }
        }


        private void DrawScorePanel(Rect panel)
        {
            GUILayout.BeginArea(panel);

            GUILayout.Label("<size=20><b>🐍 SNAKE</b></size>");
            GUILayout.Space(4);

            string state = game!.State switch
            {
                SnakeGameState.Playing => "<color=#00FF88>● PLAYING</color>",
                SnakeGameState.Dead => "<color=#FF4444>● GAME OVER</color>",
                _ => "<color=#888888>● STOPPED</color>"
            };
            GUILayout.Label(state);

            GUILayout.Label($"Score <b><color=#00FF88>{game.Score}</color></b>   High <b>{game.HighScore}</b>   Length <b>{game.SnakeLength}</b>");

            if (!string.IsNullOrEmpty(game.Notification))
            {
                GUILayout.Space(4);
                GUILayout.Label($"<i>{game.Notification}</i>");
            }

            if (player != null && player.IsSignedIn)
            {
                GUILayout.Space(4);
                GUILayout.Label($"Playing as <b>{player.DisplayName}</b>");
            }

            GUILayout.Space(8);

            GUILayout.BeginHorizontal();
            if (game.IsPlaying)
            {
                if (GUILayout.Button("⏹ Stop", GUILayout.Height(28))) game.Stop();
            }
            else if (GUILayout.Button("▶ Play", GUILayout.Height(28)))
            {
                game.StartNewGame();
            }

            if (GUILayout.Button("↻ Refresh board", GUILayout.Height(28)) && leaderboard != null)
            {
                _ = leaderboard.RefreshAsync();
            }
            GUILayout.EndHorizontal();

            GUILayout.Space(10);
            DrawLeaderboard();

            GUILayout.EndArea();
        }

        private void DrawLeaderboard()
        {
            GUILayout.Label("<b>🏆 Leaderboard</b> <i>(server, shared)</i>");

            if (leaderboard == null)
            {
                GUILayout.Label("—");
                return;
            }

            if (leaderboard.Rows.Count == 0)
            {
                GUILayout.Label("<i>No scores yet.</i>");
            }
            else
            {
                for (int i = 0; i < leaderboard.Rows.Count; i++)
                {
                    var row = leaderboard.Rows[i];
                    string me = player != null && player.PlayerId == row.PlayerId ? " <color=#00FF88>◀ you</color>" : "";
                    GUILayout.Label($"{i + 1,2}. <b>{row.Score,5}</b>  {row.Name}{me}");
                }
            }

            if (!string.IsNullOrEmpty(leaderboard.Status))
            {
                GUILayout.Label($"<size=10><i>{leaderboard.Status}</i></size>");
            }
        }

        private void DrawNamePrompt()
        {
            const float width = 380f;
            const float height = 180f;

            var rect = new Rect((Screen.width - width) / 2f, (Screen.height - height) / 2f, width, height);
            GUI.Box(rect, "");

            GUILayout.BeginArea(new Rect(rect.x + 20f, rect.y + 20f, width - 40f, height - 40f));

            GUILayout.Label("<size=16><b>Choose a name</b></size>");
            GUILayout.Label("<i>It is shown on the shared leaderboard.</i>");
            GUILayout.Space(8);

            GUI.SetNextControlName("ExoNameField");
            _nameInput = GUILayout.TextField(_nameInput ?? "", 16);

            if (!string.IsNullOrEmpty(_nameError))
            {
                GUILayout.Label($"<color=#FF6666>{_nameError}</color>");
            }

            GUILayout.Space(8);
            GUILayout.BeginHorizontal();

            bool canSubmit = !_submittingName && !string.IsNullOrWhiteSpace(_nameInput);

            using (new GuiEnabled(canSubmit))
            {
                if (GUILayout.Button(_submittingName ? "Saving…" : "▶ Play", GUILayout.Height(30)))
                {
                    _ = SubmitNameAsync();
                }
            }

            GUILayout.EndHorizontal();
            GUILayout.EndArea();

            if (Event.current.type == EventType.Repaint && GUI.GetNameOfFocusedControl() != "ExoNameField")
            {
                GUI.FocusControl("ExoNameField");
            }
        }

        private async System.Threading.Tasks.Task SubmitNameAsync()
        {
            if (player == null) return;

            _submittingName = true;
            _nameError = "";

            try
            {
                bool ok = await player.SetDisplayNameAsync(_nameInput);

                if (!ok)
                {
                    _nameError = "Could not save that name — try another.";
                }
            }
            finally
            {
                _submittingName = false;
            }
        }

        /// <summary>Scoped <c>GUI.enabled</c> — IMGUI has no using-block of its own.</summary>
        private readonly struct GuiEnabled : IDisposable
        {
            private readonly bool _previous;

            public GuiEnabled(bool enabled)
            {
                _previous = GUI.enabled;
                GUI.enabled = enabled;
            }

            public void Dispose() => GUI.enabled = _previous;
        }
    }
}
