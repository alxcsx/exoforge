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
        [Header("Scene")]
        [SerializeField] private SnakeGameController? game;
        [SerializeField] private SnakePlayerController? player;
        [SerializeField] private SnakeLeaderboard? leaderboard;

        [Header("Board colours")]
        [SerializeField] private Color squareA = new(0.10f, 0.12f, 0.17f);
        [SerializeField] private Color squareB = new(0.13f, 0.16f, 0.22f);
        [SerializeField] private Color bodyColor = new(0.24f, 0.82f, 0.34f);
        [SerializeField] private Color headColor = new(0.62f, 1.00f, 0.68f);
        [SerializeField] private Color foodColor = new(1.00f, 0.32f, 0.36f);

        [Header("Layout")]
        [SerializeField] private float boardPixels = 380f;
        [SerializeField] private float panelWidth = 320f;

        private Texture2D? _board;
        private Color32[] _pixels = Array.Empty<Color32>();
        private int _pixelWidth;
        private int _pixelHeight;

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

        private void OnDestroy()
        {
            if (_board != null)
            {
                Destroy(_board);
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

        private void EnsureBuffers(int width, int height)
        {
            if (_pixelWidth == width && _pixelHeight == height && _board != null)
            {
                return;
            }

            _pixelWidth = width;
            _pixelHeight = height;
            _pixels = new Color32[width * height];

            if (_board != null)
            {
                Destroy(_board);
            }

            _board = new Texture2D(width, height, TextureFormat.RGBA32, false)
            {
                name = "SnakeBoard",
                filterMode = FilterMode.Point,   // one pixel, one crisp square
                wrapMode = TextureWrapMode.Clamp,
                hideFlags = HideFlags.HideAndDontSave
            };
        }

        /// <summary>
        /// Paints every cell into the pixel buffer, row-major from the bottom-left, and returns it.
        ///
        /// Pure index maths over <see cref="SnakeGameController"/>'s state — no rendering — so the
        /// board can be checked headlessly (<c>ExoforgeSampleCheck.Run</c>).
        /// </summary>
        public Color32[] BuildPixels()
        {
            if (game == null) return Array.Empty<Color32>();

            int w = game.GridWidth;
            int h = game.GridHeight;
            EnsureBuffers(w, h);

            var a = (Color32)squareA;
            var b = (Color32)squareB;

            // Checkerboard, so the grid reads as a grid of squares even when it is empty.
            for (int y = 0; y < h; y++)
            {
                for (int x = 0; x < w; x++)
                {
                    _pixels[y * w + x] = (x + y) % 2 == 0 ? a : b;
                }
            }

            foreach (var segment in game.Body)
            {
                _pixels[segment.y * w + segment.x] = bodyColor;
            }

            var head = game.Head;
            _pixels[head.y * w + head.x] = headColor;

            var food = game.Food;
            _pixels[food.y * w + food.x] = foodColor;

            return _pixels;
        }

        private void PaintBoard()
        {
            if (game == null || _board == null) return;

            _board.SetPixels32(BuildPixels());
            _board.Apply(false);
        }

        // ---- hud ---------------------------------------------------------------------------

        private void OnGUI()
        {
            if (game == null) return;

            PaintBoard();

            float cell = boardPixels / game.GridWidth;
            float boardSize = cell * game.GridWidth;
            var boardRect = new Rect(24f, 64f, boardSize, boardSize);

            GUI.Box(boardRect, "");
            GUI.DrawTexture(boardRect, _board!, ScaleMode.StretchToFill, false);

            DrawScorePanel(new Rect(boardRect.xMax + 20f, boardRect.y, panelWidth, boardSize));

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
                    string me = player != null && player.DisplayName == row.Name ? " <color=#00FF88>◀ you</color>" : "";
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
