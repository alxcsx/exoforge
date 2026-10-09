using System;
using System.Linq;
using UnityEngine;

namespace SnakeGame
{
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

        [Header("Background")]
        [SerializeField] private SpriteRenderer? backgroundRenderer;

        private static Sprite? _square;
        private SpriteRenderer[] _cells = Array.Empty<SpriteRenderer>();
        private int _width;
        private int _height;

        public Color BodyColor { get => bodyColor; set => bodyColor = value; }
        public Color HeadColor { get => headColor; set => headColor = value; }
        public Color FoodColor { get => foodColor; set => foodColor = value; }

        public void SetSnakeColor(Color color)
        {
            bodyColor = color;
            headColor = Color.Lerp(color, Color.white, 0.35f);
        }

        public void SetAppleColor(Color color)
        {
            foodColor = color;
        }

        public void SetBackgroundSprite(Sprite? sprite)
        {
            if (backgroundRenderer == null)
            {
                var bgGo = new GameObject("BoardBackground");
                bgGo.transform.SetParent(transform, worldPositionStays: false);
                bgGo.transform.localPosition = new Vector3(0, 0, 1f);
                backgroundRenderer = bgGo.AddComponent<SpriteRenderer>();
            }

            backgroundRenderer.sprite = sprite;
            if (sprite != null && game != null)
            {
                float targetWidth = game.GridWidth * cellSize;
                float targetHeight = game.GridHeight * cellSize;
                backgroundRenderer.transform.localScale = new Vector3(
                    targetWidth / sprite.bounds.size.x,
                    targetHeight / sprite.bounds.size.y,
                    1f);
            }
        }

        private void Awake()
        {
            game ??= FindAnyObjectByType<SnakeGameController>(FindObjectsInactive.Include);
        }

        private void LateUpdate() => Paint();

        public Color32 CellColour(Vector2Int cell)
        {
            if (game == null) return squareA;
            if (cell == game.Head) return headColor;
            if (cell == game.Food) return foodColor;
            if (game.Body.Contains(cell)) return bodyColor;

            return (cell.x + cell.y) % 2 == 0 ? squareA : squareB;
        }

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
