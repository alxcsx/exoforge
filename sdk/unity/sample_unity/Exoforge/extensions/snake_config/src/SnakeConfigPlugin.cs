using System;
using System.Collections.Generic;
using System.Text.Json.Serialization;
using Exoforge.Plugin.SDK;
using Exoforge.Plugins.Generated;

namespace Exoforge.Plugins.SnakeConfig;

// DTO
public record SnakeConfigData
{
    [JsonPropertyName("snake_color")]
    public string SnakeColor { get; init; } = "#3DD157";

    [JsonPropertyName("apple_color")]
    public string AppleColor { get; init; } = "#FF525C";

    [JsonPropertyName("apple_points")]
    public int ApplePoints { get; init; } = 10;

    [JsonPropertyName("background_file_id")]
    public string BackgroundFileId { get; init; } = "";

    [JsonPropertyName("background_addressable")]
    public string BackgroundAddressable { get; init; } = "Background_CyberGrid";
}

[ExoService("snake_config", Version = "1.0.0",
    Category = "Game", Title = "Snake Configuration", Icon = "⚙️")]
public class SnakeConfigPlugin
{
    private const string Table = "game_config";
    private const string ConfigKey = "active_config";

    [Inject]
    public IDatabase? Database { get; set; }

    [Inject]
    public ILogger? Logger { get; set; }

    [Inject]
    public IUnityAddressablesService? Addressables { get; set; }

    [ExoAction]
    public SnakeConfigData GetConfig()
    {
        var existing = Database?.Get<SnakeConfigRecord>(Table, ConfigKey)
                       ?? Database?.QuerySingle<SnakeConfigRecord>($"SELECT * FROM {Table} WHERE key = $1", ConfigKey);

        if (existing == null)
        {
            var defaults = new SnakeConfigData();
            Database?.Put(Table, ConfigKey, new SnakeConfigRecord
            {
                Key = ConfigKey,
                SnakeColor = defaults.SnakeColor,
                AppleColor = defaults.AppleColor,
                ApplePoints = defaults.ApplePoints,
                BackgroundFileId = defaults.BackgroundFileId,
                BackgroundAddressable = defaults.BackgroundAddressable,
                UpdatedAt = DateTimeOffset.UtcNow.ToUnixTimeSeconds()
            });
            return defaults;
        }

        return new SnakeConfigData
        {
            SnakeColor = existing.SnakeColor,
            AppleColor = existing.AppleColor,
            ApplePoints = existing.ApplePoints,
            BackgroundFileId = existing.BackgroundFileId,
            BackgroundAddressable = existing.BackgroundAddressable
        };
    }

    [ExoAction]
    public SnakeConfigData UpdateConfig(
        string? snakeColor,
        string? appleColor,
        int? applePoints,
        string? backgroundFileId,
        string? backgroundAddressable)
    {
        var current = GetConfig();
        var updated = new SnakeConfigRecord
        {
            Key = ConfigKey,
            SnakeColor = !string.IsNullOrEmpty(snakeColor) ? snakeColor : current.SnakeColor,
            AppleColor = !string.IsNullOrEmpty(appleColor) ? appleColor : current.AppleColor,
            ApplePoints = applePoints.HasValue && applePoints.Value > 0 ? applePoints.Value : current.ApplePoints,
            BackgroundFileId = backgroundFileId ?? current.BackgroundFileId,
            BackgroundAddressable = !string.IsNullOrEmpty(backgroundAddressable) ? backgroundAddressable : current.BackgroundAddressable,
            UpdatedAt = DateTimeOffset.UtcNow.ToUnixTimeSeconds()
        };

        Database?.Put(Table, ConfigKey, updated);
        Logger?.Info($"[snake_config] Updated config: points={updated.ApplePoints}, snake={updated.SnakeColor}, addressable={updated.BackgroundAddressable}");

        return new SnakeConfigData
        {
            SnakeColor = updated.SnakeColor,
            AppleColor = updated.AppleColor,
            ApplePoints = updated.ApplePoints,
            BackgroundFileId = updated.BackgroundFileId,
            BackgroundAddressable = updated.BackgroundAddressable
        };
    }
}

[ExoSingletonResource("snake_config", PrimaryKey = "key")]
public record SnakeConfigRecord
{
    [JsonPropertyName("key")]
    [ExoColumn(Label = "Key")]
    public string Key { get; init; } = "active_config";

    [JsonPropertyName("snake_color")]
    [ExoColumn(Label = "Snake Color", InputType = ExoInput.Color)]
    public string SnakeColor { get; init; } = "#3DD157";

    [JsonPropertyName("apple_color")]
    [ExoColumn(Label = "Apple Color", InputType = ExoInput.Color)]
    public string AppleColor { get; init; } = "#FF525C";

    [JsonPropertyName("apple_points")]
    [ExoColumn(Label = "Apple Points")]
    public int ApplePoints { get; init; } = 10;

    [JsonPropertyName("background_file_id")]
    [ExoColumn(Label = "Background File ID", Role = "file_reference", Bucket = "snake_assets")]
    public string BackgroundFileId { get; init; } = "";

    [JsonPropertyName("background_addressable")]
    [ExoColumn(Label = "Background Addressable", InputType = IUnityAddressablesService.AddressableRef)]
    public string BackgroundAddressable { get; init; } = "Background_CyberGrid";

    [JsonPropertyName("updated_at")]
    [ExoColumn(Label = "Updated At")]
    public long UpdatedAt { get; init; }
}
