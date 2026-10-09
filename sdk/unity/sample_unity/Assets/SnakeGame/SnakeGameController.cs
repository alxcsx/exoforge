using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.InputSystem;

namespace SnakeGame
{
    public enum SnakeGameState { Stopped, Playing, Dead }

    public class SnakeGameController : MonoBehaviour
    {
        [Header("Game Configuration")]
        [SerializeField] private int gridWidth = 20;
        [SerializeField] private int gridHeight = 20;
        [SerializeField] private float stepInterval = 0.18f;
        [SerializeField] private int applePoints = 10;

        private float _stepTimer;
        private int _direction = 1;
        private int _pendingDirection = 1;

        private Vector2Int _head;
        private readonly List<Vector2Int> _body = new();
        private Vector2Int _food;

        private int _score;
        private int _highScore;
        private int _applesEaten;

        public event Action<int, int>? RunEnded;
        public event Action? RunStarted;

        public SnakeGameState State { get; private set; } = SnakeGameState.Stopped;
        public int Score => _score;
        public int HighScore => _highScore;
        public int SnakeLength => _body.Count + 1;
        public int ApplesEaten => _applesEaten;
        public bool IsPlaying => State == SnakeGameState.Playing;
        public string Notification { get; private set; } = "";

        public int GridWidth => gridWidth;
        public int GridHeight => gridHeight;
        public int ApplePoints
        {
            get => applePoints;
            set => applePoints = Mathf.Max(1, value);
        }

        public Vector2Int Head => _head;
        public IReadOnlyList<Vector2Int> Body => _body;
        public Vector2Int Food => _food;

        private void Start() => StartNewGame();

        private void Update()
        {
            if (State != SnakeGameState.Playing) return;

            HandleInput();
            Advance(Time.deltaTime);
        }

        public void Advance(float deltaTime)
        {
            if (State != SnakeGameState.Playing) return;

            _stepTimer += deltaTime;
            while (_stepTimer >= stepInterval && State == SnakeGameState.Playing)
            {
                _stepTimer -= stepInterval;
                _direction = _pendingDirection;
                Step();
            }
        }

        public void Turn(int direction)
        {
            if (direction < 0 || direction > 3) return;
            if (direction == _direction) return;
            if ((direction + 2) % 4 == _direction) return;

            _pendingDirection = direction;
        }

        private void HandleInput()
        {
            var keyboard = Keyboard.current;
            if (keyboard == null) return;

            if (keyboard.wKey.wasPressedThisFrame || keyboard.upArrowKey.wasPressedThisFrame) Turn(0);
            else if (keyboard.dKey.wasPressedThisFrame || keyboard.rightArrowKey.wasPressedThisFrame) Turn(1);
            else if (keyboard.sKey.wasPressedThisFrame || keyboard.downArrowKey.wasPressedThisFrame) Turn(2);
            else if (keyboard.aKey.wasPressedThisFrame || keyboard.leftArrowKey.wasPressedThisFrame) Turn(3);
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
            State = SnakeGameState.Playing;

            SpawnFood();
            Notify("Match started! Eat apples and avoid walls.");
            RunStarted?.Invoke();
        }

        public void Stop()
        {
            State = SnakeGameState.Stopped;
            Notify("Match stopped.");
        }

        private void Step()
        {
            Vector2Int next = _head;
            switch (_direction)
            {
                case 0: next.y += 1; break;
                case 1: next.x += 1; break;
                case 2: next.y -= 1; break;
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
                _score += applePoints;
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
            State = SnakeGameState.Dead;
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
                Die("Board Filled");
                return;
            }

            _food = free[UnityEngine.Random.Range(0, free.Count)];
        }

        private void Notify(string message)
        {
            Notification = message;
            Debug.Log($"[Snake] {message}");
        }
    }
}
