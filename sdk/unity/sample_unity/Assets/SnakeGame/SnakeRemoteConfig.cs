using System;
using System.Text.Json;
using System.Threading.Tasks;
using Exoforge.Client.Unity;
using UnityEngine;

namespace SnakeGame
{
    /// <summary>
    /// Fetches runtime gameplay configuration from the snake_config plugin and custom background
    /// image from the file_bucket plugin.
    ///
    /// Applies snake color, apple color, apple score points, and custom board background.
    /// </summary>
    public class SnakeRemoteConfig : MonoBehaviour
    {
        [SerializeField] private SnakeGameController? game;
        [SerializeField] private SnakeBoardView? boardView;

        public bool IsLoaded { get; private set; }
        public string Status { get; private set; } = "not loaded";

        private void Awake()
        {
            game ??= UnityEngine.Object.FindAnyObjectByType<SnakeGameController>(FindObjectsInactive.Include);
            boardView ??= UnityEngine.Object.FindAnyObjectByType<SnakeBoardView>(FindObjectsInactive.Include);
        }

        private void Start()
        {
            _ = LoadConfigAsync();
        }

        public async Task LoadConfigAsync()
        {
            Status = "fetching config…";
            try
            {
                var client = ExoforgeSDK.Client;

                // Dispatch get_config action to snake_config plugin
                var config = await client.SendActionAsync<JsonElement>("snake_config", "get_config", null);

                string snakeColorHex = config.TryGetProperty("snake_color", out var sc) ? sc.GetString() ?? "#3DD157" : "#3DD157";
                string appleColorHex = config.TryGetProperty("apple_color", out var ac) ? ac.GetString() ?? "#FF525C" : "#FF525C";
                int applePoints = config.TryGetProperty("apple_points", out var ap) ? ap.GetInt32() : 10;
                string bgBucket = config.TryGetProperty("background_bucket", out var bb) ? bb.GetString() ?? "snake_assets" : "snake_assets";
                string bgFileId = config.TryGetProperty("background_file_id", out var bf) ? bf.GetString() ?? "" : "";
                string bgFilename = config.TryGetProperty("background_filename", out var bfn) ? bfn.GetString() ?? "board_bg.png" : "board_bg.png";

                // Apply to game
                if (game != null)
                {
                    game.ApplePoints = applePoints;
                }

                // Apply to board view
                if (boardView != null)
                {
                    if (ColorUtility.TryParseHtmlString(snakeColorHex, out var snakeColor))
                    {
                        boardView.SetSnakeColor(snakeColor);
                    }

                    if (ColorUtility.TryParseHtmlString(appleColorHex, out var appleColor))
                    {
                        boardView.SetAppleColor(appleColor);
                    }

                    // If a background file ID is configured, download image from file_bucket
                    if (!string.IsNullOrEmpty(bgFileId))
                    {
                        try
                        {
                            byte[] imageBytes = await client.DownloadFileAsync(bgBucket, bgFileId, bgFilename);
                            if (imageBytes != null && imageBytes.Length > 0)
                            {
                                var texture = new Texture2D(2, 2);
                                if (texture.LoadImage(imageBytes))
                                {
                                    var sprite = Sprite.Create(
                                        texture,
                                        new Rect(0, 0, texture.width, texture.height),
                                        new Vector2(0.5f, 0.5f));
                                    boardView.SetBackgroundSprite(sprite);
                                }
                            }
                        }
                        catch (Exception bgEx)
                        {
                            Debug.LogWarning($"[SnakeRemoteConfig] Could not load background image: {bgEx.Message}");
                        }
                    }
                }

                IsLoaded = true;
                Status = $"loaded (points={applePoints}, snake={snakeColorHex})";
                Debug.Log($"[SnakeRemoteConfig] Config loaded: snake={snakeColorHex}, apple={appleColorHex}, points={applePoints}");
            }
            catch (Exception ex)
            {
                Status = $"offline: {ex.Message}";
                Debug.LogWarning($"[SnakeRemoteConfig] Could not load config: {ex.Message}");
            }
        }
    }
}
