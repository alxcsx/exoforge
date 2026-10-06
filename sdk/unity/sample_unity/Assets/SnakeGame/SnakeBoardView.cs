using System;
using System.Linq;
using UnityEngine;

namespace SnakeGame
{
    /// <summary>
    /// Draws the board as coloured squares — one pooled <see cref="SpriteRenderer"/> per cell.
    ///
    /// A runtime-generated 1x1 white sprite is tinted per cell, so there is no art to import and no
    /// prefab to wire: the grid, the snake and the apple are all the same square. The board is centred
    /// on the origin with one world unit per cell, which is what the camera frames.
    ///
    /// Reads the game, never drives it. <see cref="CellColour"/> is pure, so the headless check can
    /// assert what a cell will look like without rendering anything.
    /// </summary>
    [DefaultExecutionOrder(-650)]
    public class SnakeBoardView : MonoBehaviour
    {
        [Header("Scene")]
        [SerializeField] private SnakeGameController? game;

        [Header("Colours")]
        [SerializeField] private Color squareA = new(0.10f, 0.12f, 0.17f);
        [SerializeField] private Color squareB = new(0.13f, 0.16f, 0.22f);
        [SerializeField] private Color bodyColor = new(0.24f, 0.82f, 0.34f);
        [SerializeField] private Color headColor = new(0.62f, 1.00f, 0.68f);
        [SerializeField] private Color foodColor = new(1.00f, 0.32f, 0.36f);

        [Header("Layout")]
        [SerializeField] private float cellSize = 1f;

        private static Sprite? _square;
        private SpriteRenderer[] _cells = Array.Empty<SpriteRenderer>();
        private int _width;
        private int _height;

        private void Awake()
        {
            // Wired by the scene setup; the search keeps a hand-made scene working.
            game ??= FindAnyObjectByType<SnakeGameController>(FindObjectsInactive.Include);
        }

        private void LateUpdate() => Paint();

        /// <summary>What a cell looks like right now. Pure — no renderer involved.</summary>
        public Color32 CellColour(Vector2Int cell)
        {
            if (game == null) return squareA;

            if (cell == game.Head) return headColor;
            if (cell == game.Food) return foodColor;
            if (game.Body.Contains(cell)) return bodyColor;

            // Checkerboard, so the grid reads as a grid of squares even when it is empty.
            return (cell.x + cell.y) % 2 == 0 ? squareA : squareB;
        }

        /// <summary>
        /// World position of a cell, with the board centred on the origin.
        ///
        /// Reads the grid from the game rather than from the pooled renderers, which only exist once
        /// a frame has run — otherwise this is wrong in the editor, where LateUpdate does not.
        /// </summary>
        public Vector3 CellToWorld(Vector2Int cell)
        {
            int width = game != null ? game.GridWidth : _width;
            int height = game != null ? game.GridHeight : _height;

            return new Vector3(
                (cell.x - (width - 1) * 0.5f) * cellSize,
                (cell.y - (height - 1) * 0.5f) * cellSize,
                0f);
        }

        private void Paint()
        {
            if (game == null) return;

            EnsureCells();
            if (_cells.Length == 0) return;

            for (int y = 0; y < _height; y++)
            {
                for (int x = 0; x < _width; x++)
                {
                    _cells[y * _width + x].color = CellColour(new Vector2Int(x, y));
                }
            }
        }

        private void EnsureCells()
        {
            if (_width == game!.GridWidth && _height == game.GridHeight && _cells.Length > 0)
            {
                return;
            }

            _width = game.GridWidth;
            _height = game.GridHeight;

            // Rebuild rather than resize: the grid only changes if someone edits the serialized field.
            foreach (var cell in _cells)
            {
                if (cell != null) Destroy(cell.gameObject);
            }

            _cells = new SpriteRenderer[_width * _height];

            for (int y = 0; y < _height; y++)
            {
                for (int x = 0; x < _width; x++)
                {
                    var go = new GameObject($"Cell {x},{y}");
                    go.transform.SetParent(transform, worldPositionStays: false);
                    go.transform.localPosition = CellToWorld(new Vector2Int(x, y));
                    go.transform.localScale = Vector3.one * cellSize;

                    var renderer = go.AddComponent<SpriteRenderer>();
                    renderer.sprite = Square;
                    _cells[y * _width + x] = renderer;
                }
            }
        }

        private static Sprite Square => _square != null ? _square : _square = CreateSquare();

        /// <summary>A 1x1 white sprite, point-filtered, created once for the whole sample.</summary>
        private static Sprite CreateSquare()
        {
            var texture = new Texture2D(1, 1, TextureFormat.RGBA32, false)
            {
                name = "SnakeCell",
                filterMode = FilterMode.Point,
                hideFlags = HideFlags.HideAndDontSave,
            };

            texture.SetPixel(0, 0, Color.white);
            texture.Apply();

            var sprite = Sprite.Create(texture, new Rect(0f, 0f, 1f, 1f), new Vector2(0.5f, 0.5f), 1f);
            sprite.name = "SnakeCell";
            sprite.hideFlags = HideFlags.HideAndDontSave;

            return sprite;
        }
    }
}
