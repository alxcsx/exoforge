using System;
using System.Collections.Generic;
using System.Text.Json.Serialization;
using Exoforge.Plugin.SDK;

namespace Exoforge.Plugins.SnakeConfig;

public record SnakeConfigData
{
    [JsonPropertyName("snake_color")]
    public string SnakeColor { get; init; } = "#3DD157";

    [JsonPropertyName("apple_color")]
    public string AppleColor { get; init; } = "#FF525C";

    [JsonPropertyName("apple_points")]
    public int ApplePoints { get; init; } = 10;

    [JsonPropertyName("background_bucket")]
    public string BackgroundBucket { get; init; } = "snake_assets";

    [JsonPropertyName("background_file_id")]
    public string BackgroundFileId { get; init; } = "";

    [JsonPropertyName("background_filename")]
    public string BackgroundFilename { get; init; } = "board_bg.png";
}

[ExoService("snake_config", Version = "1.0.0",
    Category = "Game", Title = "Snake Configuration", Icon = "⚙️")]
public class SnakeConfigPlugin
{
    private const string Table = "game_config";
    private const string ConfigKey = "active_config";

    [Inject("database")]
    public IDatabase? Database { get; set; }

    [Inject]
    public ILogger? Logger { get; set; }

    [ExoAction]
    public SnakeConfigData GetConfig()
    {
        var existing = Database?.Get<SnakeConfigRecord>(Table, ConfigKey);
        if (existing == null)
        {
            var defaults = new SnakeConfigData();
            Database?.Put(Table, ConfigKey, new SnakeConfigRecord
            {
                Key = ConfigKey,
                SnakeColor = defaults.SnakeColor,
                AppleColor = defaults.AppleColor,
                ApplePoints = defaults.ApplePoints,
                BackgroundBucket = defaults.BackgroundBucket,
                BackgroundFileId = defaults.BackgroundFileId,
                BackgroundFilename = defaults.BackgroundFilename,
                UpdatedAt = DateTimeOffset.UtcNow.ToUnixTimeSeconds()
            });
            return defaults;
        }

        return new SnakeConfigData
        {
            SnakeColor = existing.SnakeColor,
            AppleColor = existing.AppleColor,
            ApplePoints = existing.ApplePoints,
            BackgroundBucket = existing.BackgroundBucket,
            BackgroundFileId = existing.BackgroundFileId,
            BackgroundFilename = existing.BackgroundFilename
        };
    }

    [ExoAction]
    public SnakeConfigData UpdateConfig(
        string? snakeColor,
        string? appleColor,
        int? applePoints,
        string? backgroundBucket,
        string? backgroundFileId,
        string? backgroundFilename)
    {
        var current = GetConfig();
        var updated = new SnakeConfigRecord
        {
            Key = ConfigKey,
            SnakeColor = !string.IsNullOrEmpty(snakeColor) ? snakeColor : current.SnakeColor,
            AppleColor = !string.IsNullOrEmpty(appleColor) ? appleColor : current.AppleColor,
            ApplePoints = applePoints.HasValue && applePoints.Value > 0 ? applePoints.Value : current.ApplePoints,
            BackgroundBucket = !string.IsNullOrEmpty(backgroundBucket) ? backgroundBucket : current.BackgroundBucket,
            BackgroundFileId = backgroundFileId ?? current.BackgroundFileId,
            BackgroundFilename = !string.IsNullOrEmpty(backgroundFilename) ? backgroundFilename : current.BackgroundFilename,
            UpdatedAt = DateTimeOffset.UtcNow.ToUnixTimeSeconds()
        };

        Database?.Put(Table, ConfigKey, updated);
        Logger?.Info($"[snake_config] Updated config: points={updated.ApplePoints}, snake={updated.SnakeColor}");

        return new SnakeConfigData
        {
            SnakeColor = updated.SnakeColor,
            AppleColor = updated.AppleColor,
            ApplePoints = updated.ApplePoints,
            BackgroundBucket = updated.BackgroundBucket,
            BackgroundFileId = updated.BackgroundFileId,
            BackgroundFilename = updated.BackgroundFilename
        };
    }
}

[ExoResource("snake_config_records", PrimaryKey = "key")]
public record SnakeConfigRecord
{
    [ExoColumn(Label = "Key")]
    public string Key { get; init; } = "";

    [ExoColumn(Label = "Snake Color")]
    public string SnakeColor { get; init; } = "#3DD157";

    [ExoColumn(Label = "Apple Color")]
    public string AppleColor { get; init; } = "#FF525C";

    [ExoColumn(Label = "Apple Points")]
    public int ApplePoints { get; init; } = 10;

    [ExoColumn(Label = "Background Bucket")]
    public string BackgroundBucket { get; init; } = "snake_assets";

    [ExoColumn(Label = "Background File ID")]
    public string BackgroundFileId { get; init; } = "";

    [ExoColumn(Label = "Background Filename")]
    public string BackgroundFilename { get; init; } = "board_bg.png";

    [ExoColumn(Label = "Updated At")]
    public long UpdatedAt { get; init; }
}
