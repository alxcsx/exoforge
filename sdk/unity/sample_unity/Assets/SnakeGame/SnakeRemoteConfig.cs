using System;
using System.Text.Json;
using System.Threading.Tasks;
using Exoforge.Client.Unity;
using UnityEngine;

namespace SnakeGame
{
    public class SnakeRemoteConfig : MonoBehaviour
    {
        [SerializeField] private SnakeGameController? game;
        [SerializeField] private SnakeBoardView? boardView;
        [SerializeField] private SnakePlayerController? playerController;

        public bool IsLoaded { get; private set; }
        public string Status { get; private set; } = "not loaded";

        private void Awake()
        {
            game ??= UnityEngine.Object.FindAnyObjectByType<SnakeGameController>(FindObjectsInactive.Include);
            boardView ??= UnityEngine.Object.FindAnyObjectByType<SnakeBoardView>(FindObjectsInactive.Include);
            playerController ??= UnityEngine.Object.FindAnyObjectByType<SnakePlayerController>(FindObjectsInactive.Include);
            if (playerController != null)
            {
                playerController.SessionReady += async _ => await LoadConfigAsync();
            }
        }

        private void Start()
        {
            _ = LoadConfigAsync();
        }

        private void OnEnable()
        {
            if (!IsLoaded)
            {
                _ = LoadConfigAsync();
            }
        }

        public async Task LoadConfigAsync()
        {
            if (this == null) return;
            Debug.Log("[SnakeRemoteConfig] Loading config…");
            Status = "fetching config…";
            try
            {
                var client = ExoforgeSDK.Client;
                var mgr = ExoforgeManager.Instance;
                if (mgr != null && !mgr.IsConnected)
                {
                    try { client = await mgr.GetClientAsync(); }
                    catch { }
                }

                var config = await client.SendActionAsync<JsonElement>("snake_config", "get_config", null);
                if (this == null) return;

                string snakeColorHex = config.TryGetProperty("snake_color", out var sc) ? sc.GetString() ?? "#3DD157" : "#3DD157";
                string appleColorHex = config.TryGetProperty("apple_color", out var ac) ? ac.GetString() ?? "#FF525C" : "#FF525C";
                int applePoints = 10;
                if (config.TryGetProperty("apple_points", out var ap))
                {
                    if (ap.ValueKind == JsonValueKind.Number && ap.TryGetInt32(out var pNum)) applePoints = pNum;
                    else if (ap.ValueKind == JsonValueKind.String && int.TryParse(ap.GetString(), out var pStr)) applePoints = pStr;
                }
                string bgBucket = config.TryGetProperty("background_bucket", out var bb) ? bb.GetString() ?? "snake_assets" : "snake_assets";
                string bgFileId = config.TryGetProperty("background_file_id", out var bf) ? bf.GetString() ?? "" : "";

                if (game != null)
                {
                    game.ApplePoints = applePoints;
                }

                if (boardView != null)
                {
                    if (ColorUtility.TryParseHtmlString(snakeColorHex, out var snakeColor))
                    {
                        boardView.SetSnakeColor(snakeColor);
                        Debug.Log($"[SnakeRemoteConfig] Loaded snake color: {snakeColorHex}");
                    }

                    if (ColorUtility.TryParseHtmlString(appleColorHex, out var appleColor))
                    {
                        boardView.SetAppleColor(appleColor);
                        Debug.Log($"[SnakeRemoteConfig] Loaded apple color: {appleColorHex}");
                    }

                    if (!string.IsNullOrEmpty(bgFileId))
                    {
                        try
                        {
                            byte[] imageBytes = await client.DownloadFileAsync(bgBucket, bgFileId);
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

                            Debug.Log($"[SnakeRemoteConfig] Loaded background image from bucket '{bgBucket}' with file ID '{bgFileId}'");
                        }
                        catch (Exception bgEx)
                        {
                            Debug.LogWarning($"[SnakeRemoteConfig] Could not load background image: {bgEx.Message}");
                        }
                    }
                }
                Debug.Log("[SnakeRemoteConfig] Config loaded successfully");

                IsLoaded = true;
                Status = $"loaded (points={applePoints}, snake={snakeColorHex})";
            }
            catch (Exception ex)
            {
                Status = $"offline: {ex.Message}";
                Debug.LogWarning($"[SnakeRemoteConfig] Could not load config: {ex.Message}");
            }
        }
    }
}
