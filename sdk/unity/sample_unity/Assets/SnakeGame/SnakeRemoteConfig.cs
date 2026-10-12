using System;
using System.Text.Json;
using System.Threading.Tasks;
using Exoforge.Client;
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
        public SnakeConfigData? ConfigData { get; private set; }

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

                // Typesafe generated stub for snake_config
                var config = await client.SnakeConfig().GetConfigAsync();
                if (this == null) return;
                ConfigData = config;

                string snakeColorHex = !string.IsNullOrEmpty(config.SnakeColor) ? config.SnakeColor : "#3DD157";
                string appleColorHex = !string.IsNullOrEmpty(config.AppleColor) ? config.AppleColor : "#FF525C";
                int applePoints = config.ApplePoints > 0 ? (int)config.ApplePoints : 10;
                string bgBucket = "snake_assets";
                string bgFileId = config.BackgroundFileId ?? "";
                string bgAddressable = config.BackgroundAddressable ?? "";

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

                    // 1. Fetch Addressables Manifest by tag "latest" via typesafe generated stub
                    try
                    {
                        var manifest = await client.UnityAddressables().GetManifestAsync("latest");
                        if (manifest != null)
                        {
                            string mVer = manifest.Version ?? "";
                            string mTag = manifest.Tag ?? "";
                            Debug.Log($"[SnakeRemoteConfig] Fetched Addressables manifest for tag '{mTag}' (version {mVer})");

                            if (string.IsNullOrEmpty(bgAddressable) && manifest.Assets.ValueKind == JsonValueKind.Array && manifest.Assets.GetArrayLength() > 0)
                            {
                                var firstAsset = manifest.Assets[0];
                                if (firstAsset.TryGetProperty("address", out var firstAddr))
                                {
                                    bgAddressable = firstAddr.GetString() ?? "";
                                    Debug.Log($"[SnakeRemoteConfig] Resolved background address from 'latest' manifest: '{bgAddressable}'");
                                }
                            }
                        }
                    }
                    catch (Exception mEx)
                    {
                        Debug.LogWarning($"[SnakeRemoteConfig] Addressables get_manifest (tag=latest) error: {mEx.Message}");
                    }

                    // 2. Try Addressables Background Reference (True Addressables runtime)
                    bool addressableLoaded = false;
                    if (!string.IsNullOrEmpty(bgAddressable))
                    {
                        Sprite? sprite = null;
                        try
                        {
                            var handle = UnityEngine.AddressableAssets.Addressables.LoadAssetAsync<Sprite>(bgAddressable);
                            sprite = await handle.Task;
                        }
                        catch (Exception addrEx)
                        {
                            Debug.LogWarning($"[SnakeRemoteConfig] Addressables API load error for '{bgAddressable}': {addrEx.Message}. Attempting local fallback…");
                        }

                        if (sprite != null && boardView != null)
                        {
                            boardView.SetBackgroundSprite(sprite);
                            addressableLoaded = true;
                            Debug.Log($"[SnakeRemoteConfig] Loaded Addressable background asset via Addressables runtime: '{bgAddressable}'");
                        }
                        else
                        {
#if UNITY_EDITOR
                            if (boardView != null)
                            {
                                var editorSprite = UnityEditor.AssetDatabase.LoadAssetAtPath<Sprite>($"Assets/SnakeGame/Backgrounds/{bgAddressable}.png");
                                if (editorSprite != null)
                                {
                                    boardView.SetBackgroundSprite(editorSprite);
                                    addressableLoaded = true;
                                    Debug.Log($"[SnakeRemoteConfig] Loaded background asset via AssetDatabase: '{bgAddressable}'");
                                }
                            }
#endif
                            if (!addressableLoaded)
                            {
                                try
                                {
                                    string localAssetPath = System.IO.Path.Combine(Application.dataPath, "SnakeGame", "Backgrounds", bgAddressable + ".png");
                                    if (System.IO.File.Exists(localAssetPath))
                                    {
                                        byte[] imgData = System.IO.File.ReadAllBytes(localAssetPath);
                                        var tex = new Texture2D(2, 2);
                                        if (tex.LoadImage(imgData))
                                        {
                                            var fbSprite = Sprite.Create(tex, new Rect(0, 0, tex.width, tex.height), new Vector2(0.5f, 0.5f));
                                            boardView?.SetBackgroundSprite(fbSprite);
                                            addressableLoaded = true;
                                            Debug.Log($"[SnakeRemoteConfig] Loaded fallback background asset: '{bgAddressable}'");
                                        }
                                    }
                                }
                                catch (Exception fbEx)
                                {
                                    Debug.LogWarning($"[SnakeRemoteConfig] Fallback local load error: {fbEx.Message}");
                                }
                            }
                        }
                    }

                    // 2. Fallback to File Bucket background if not loaded via Addressables
                    if (!addressableLoaded && !string.IsNullOrEmpty(bgFileId))
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
                                    boardView?.SetBackgroundSprite(sprite);
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
