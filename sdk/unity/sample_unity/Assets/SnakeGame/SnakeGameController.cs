using System;
using System.Collections.Generic;
using UnityEngine;

namespace SnakeGame
{
    /// <summary>
    /// Self-contained Snake game. Pure Unity — no backend, no networking.
    ///
    /// The only backend-facing surface is <see cref="RunEnded"/>: a finished run raises it with
    /// the score and final length, and a leaderboard component subscribes (through
    /// <c>ExoforgeSDK.Client</c>). Gameplay never holds a client or an endpoint.
    /// </summary>
    public class SnakeGameController : MonoBehaviour
    {
        [Header("Game Configuration")]
        [SerializeField] private int gridWidth = 20;
        [SerializeField] private int gridHeight = 20;
        [SerializeField] private float stepInterval = 0.18f;

        private enum GameState { Stopped, Playing, Dead }

        private GameState _state = GameState.Stopped;
        private float _stepTimer;

        // 0=Up, 1=Right, 2=Down, 3=Left
        private int _direction = 1;
        private int _pendingDirection = 1;

        private Vector2Int _head;
        private readonly List<Vector2Int> _body = new();
        private Vector2Int _food;

        private int _score;
        private int _highScore;
        private int _applesEaten;

        private string _notification = "";
        private float _notificationTimer;

        /// <summary>Raised when a run ends, with (score, snakeLength).</summary>
        public event Action<int, int>? RunEnded;

        /// <summary>Current score.</summary>
        public int Score => _score;

        /// <summary>Best score in this session.</summary>
        public int HighScore => _highScore;

        /// <summary>Current snake length, head included.</summary>
        public int SnakeLength => _body.Count + 1;

        /// <summary>True while a match is in progress.</summary>
        public bool IsPlaying => _state == GameState.Playing;

        private void Start() => StartNewGame();

        private void Update()
        {
            if (_notificationTimer > 0f)
            {
                _notificationTimer -= Time.deltaTime;
                if (_notificationTimer <= 0f) _notification = "";
            }

            if (_state != GameState.Playing) return;

            HandleInput();

            _stepTimer += Time.deltaTime;
            if (_stepTimer >= stepInterval)
            {
                _stepTimer = 0f;
                _direction = _pendingDirection;
                Step();
            }
        }

        private void HandleInput()
        {
            if ((Input.GetKeyDown(KeyCode.W) || Input.GetKeyDown(KeyCode.UpArrow)) && _direction != 2)
                _pendingDirection = 0;
            else if ((Input.GetKeyDown(KeyCode.D) || Input.GetKeyDown(KeyCode.RightArrow)) && _direction != 3)
                _pendingDirection = 1;
            else if ((Input.GetKeyDown(KeyCode.S) || Input.GetKeyDown(KeyCode.DownArrow)) && _direction != 0)
                _pendingDirection = 2;
            else if ((Input.GetKeyDown(KeyCode.A) || Input.GetKeyDown(KeyCode.LeftArrow)) && _direction != 1)
                _pendingDirection = 3;
        }

        public void StartNewGame()
        {
            _body.Clear();
            _head = new Vector2Int(gridWidth / 4, gridHeight / 2);
            _body.Add(new Vector2Int(_head.x - 1, _head.y));
            _body.Add(new Vector2Int(_head.x - 2, _head.y));

            _direction = 1;
            _pendingDirection = 1;
            _score = 0;
            _applesEaten = 0;
            _stepTimer = 0f;
            _state = GameState.Playing;

            SpawnFood();
            Notify("Match started! Eat apples and avoid walls.");
        }

        private void Step()
        {
            Vector2Int next = _head;
            switch (_direction)
            {
                case 0: next.y -= 1; break;
                case 1: next.x += 1; break;
                case 2: next.y += 1; break;
                case 3: next.x -= 1; break;
            }

            if (next.x < 0 || next.x >= gridWidth || next.y < 0 || next.y >= gridHeight)
            {
                Die("Wall Collision");
                return;
            }

            if (_body.Contains(next))
            {
                Die("Self Collision");
                return;
            }

            _body.Insert(0, _head);
            _head = next;

            if (_head == _food)
            {
                _score += 10;
                _applesEaten++;
                if (_score > _highScore) _highScore = _score;
                SpawnFood();
            }
            else
            {
                _body.RemoveAt(_body.Count - 1);
            }
        }

        private void Die(string reason)
        {
            _state = GameState.Dead;
            Notify($"Game Over: {reason}! Final Score: {_score}");
            RunEnded?.Invoke(_score, SnakeLength);
        }

        private void SpawnFood()
        {
            var free = new List<Vector2Int>();

            for (int x = 0; x < gridWidth; x++)
            {
                for (int y = 0; y < gridHeight; y++)
                {
                    var cell = new Vector2Int(x, y);
                    if (cell != _head && !_body.Contains(cell))
                    {
                        free.Add(cell);
                    }
                }
            }

            if (free.Count == 0)
            {
                _state = GameState.Dead;
                Notify($"Board filled! Final Score: {_score}");
                RunEnded?.Invoke(_score, SnakeLength);
                return;
            }

            _food = free[UnityEngine.Random.Range(0, free.Count)];
        }

        private void Notify(string message)
        {
            _notification = message;
            _notificationTimer = 3.5f;
            Debug.Log($"[Snake] {message}");
        }

        private void OnGUI()
        {
            GUI.skin.box.fontSize = 12;

            float windowWidth = Mathf.Min(Screen.width - 20, 460);
            float windowHeight = Mathf.Min(Screen.height - 20, 620);
            GUI.Box(new Rect(10, 10, windowWidth, windowHeight), "");

            GUILayout.BeginArea(new Rect(20, 20, windowWidth - 20, windowHeight - 20));

            GUILayout.BeginHorizontal();
            GUILayout.Label("🐍 <size=18><b>SNAKE</b></size>", GUILayout.Height(30));
            GUILayout.FlexibleSpace();
            string state = _state == GameState.Playing
                ? "<color=#00FF88>● PLAYING</color>"
                : (_state == GameState.Dead ? "<color=#FF4444>● GAME OVER</color>" : "<color=#888888>● STOPPED</color>");
            GUILayout.Label(state, GUILayout.Height(30));
            GUILayout.EndHorizontal();

            if (!string.IsNullOrEmpty(_notification))
            {
                GUI.color = Color.yellow;
                GUILayout.Box($"🔔 {_notification}", GUILayout.ExpandWidth(true));
                GUI.color = Color.white;
            }

            GUILayout.Space(10);
            GUILayout.Label($"Score: <b><color=#00FF88>{_score}</color></b> | High: <b>{_highScore}</b> | Apples: <b>{_applesEaten}</b>");

            float cellSize = 16f;
            Rect boardRect = GUILayoutUtility.GetRect(gridWidth * cellSize, gridHeight * cellSize);
            GUI.Box(boardRect, "");

            // Food
            GUI.color = new Color(1f, 0.2f, 0.2f);
            GUI.Box(CellRect(boardRect, _food, cellSize), "🍎");

            // Body
            GUI.color = new Color(0.2f, 0.8f, 0.3f);
            foreach (var segment in _body)
            {
                GUI.Box(CellRect(boardRect, segment, cellSize), "");
            }

            // Head
            GUI.color = new Color(0f, 1f, 0.4f);
            GUI.Box(CellRect(boardRect, _head, cellSize), "👀");
            GUI.color = Color.white;

            GUILayout.Space(8);

            GUILayout.BeginHorizontal();
            if (_state != GameState.Playing)
            {
                GUI.color = Color.green;
                if (GUILayout.Button(_state == GameState.Dead ? "🔄 Play Again" : "▶ Start Match", GUILayout.Height(36), GUILayout.Width(140)))
                {
                    StartNewGame();
                }
                GUI.color = Color.white;
            }
            else
            {
                GUI.color = Color.red;
                if (GUILayout.Button("⏹ Stop Match", GUILayout.Height(36), GUILayout.Width(140)))
                {
                    _state = GameState.Stopped;
                }
                GUI.color = Color.white;
            }

            // Touch D-Pad for Mobile / WebGL
            GUILayout.BeginVertical();
            GUILayout.BeginHorizontal();
            GUILayout.Space(40);
            if (GUILayout.Button("▲", GUILayout.Width(35), GUILayout.Height(25)) && _direction != 2) _pendingDirection = 0;
            GUILayout.EndHorizontal();
            GUILayout.BeginHorizontal();
            if (GUILayout.Button("◀", GUILayout.Width(35), GUILayout.Height(25)) && _direction != 1) _pendingDirection = 3;
            GUILayout.Space(5);
            if (GUILayout.Button("▼", GUILayout.Width(35), GUILayout.Height(25)) && _direction != 0) _pendingDirection = 2;
            GUILayout.Space(5);
            if (GUILayout.Button("▶", GUILayout.Width(35), GUILayout.Height(25)) && _direction != 3) _pendingDirection = 1;
            GUILayout.EndHorizontal();
            GUILayout.EndVertical();

            GUILayout.EndHorizontal();
            GUILayout.Label("<i>WASD / arrows to move.</i>");

            GUILayout.EndArea();
        }

        private static Rect CellRect(Rect board, Vector2Int cell, float cellSize) =>
            new(board.x + cell.x * cellSize, board.y + cell.y * cellSize, cellSize - 1, cellSize - 1);
    }
}
