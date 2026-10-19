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
            if (sprite == null)
            {
                if (backgroundRenderer != null)
                {
                    backgroundRenderer.sprite = null;
                    backgroundRenderer.gameObject.SetActive(false);
                }

                var activeCam = Camera.main ?? FindAnyObjectByType<Camera>(FindObjectsInactive.Include);
                if (activeCam != null)
                {
                    activeCam.backgroundColor = Color.black;
                }
                return;
            }

            if (backgroundRenderer == null)
            {
                var bgGo = new GameObject("CameraBackground");
                backgroundRenderer = bgGo.AddComponent<SpriteRenderer>();
            }

            var cam = Camera.main ?? FindAnyObjectByType<Camera>(FindObjectsInactive.Include);
            if (cam != null)
            {
                backgroundRenderer.transform.SetParent(cam.transform, worldPositionStays: false);
                backgroundRenderer.transform.localPosition = new Vector3(0, 0, 15f);
                backgroundRenderer.transform.localRotation = Quaternion.identity;
            }
            else
            {
                backgroundRenderer.transform.SetParent(transform, worldPositionStays: false);
                backgroundRenderer.transform.localPosition = new Vector3(0, 0, 5f);
            }

            backgroundRenderer.gameObject.SetActive(true);
            backgroundRenderer.sortingOrder = -100;
            backgroundRenderer.sprite = sprite;

            UpdateBackgroundScale();
        }

        private void UpdateBackgroundScale()
        {
            if (backgroundRenderer == null || backgroundRenderer.sprite == null) return;

            var sprite = backgroundRenderer.sprite;
            var cam = Camera.main ?? FindAnyObjectByType<Camera>(FindObjectsInactive.Include);
            if (cam != null)
            {
                float camHeight = cam.orthographic
                    ? 2f * cam.orthographicSize
                    : 2f * Mathf.Tan(cam.fieldOfView * 0.5f * Mathf.Deg2Rad) * Mathf.Abs(backgroundRenderer.transform.localPosition.z);
                float camWidth = camHeight * cam.aspect;

                float scaleX = camWidth / sprite.bounds.size.x;
                float scaleY = camHeight / sprite.bounds.size.y;
                float scale = Mathf.Max(scaleX, scaleY) * 1.15f;

                backgroundRenderer.transform.localScale = new Vector3(scale, scale, 1f);
            }
            else
            {
                game ??= FindAnyObjectByType<SnakeGameController>(FindObjectsInactive.Include);
                float gridW = (game != null ? game.GridWidth : (_width > 0 ? _width : 20)) * cellSize * 2f;
                float gridH = (game != null ? game.GridHeight : (_height > 0 ? _height : 20)) * cellSize * 2f;
                backgroundRenderer.transform.localScale = new Vector3(
                    gridW / sprite.bounds.size.x,
                    gridH / sprite.bounds.size.y,
                    1f);
            }
        }

        private void OnDestroy()
        {
            if (backgroundRenderer != null && backgroundRenderer.gameObject != null)
            {
                Destroy(backgroundRenderer.gameObject);
            }
        }

        private void Awake()
        {
            game ??= FindAnyObjectByType<SnakeGameController>(FindObjectsInactive.Include);
        }

        private void LateUpdate()
        {
            Paint();
            UpdateBackgroundScale();
        }

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
