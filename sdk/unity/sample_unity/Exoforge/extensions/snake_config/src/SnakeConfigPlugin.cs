using System;
using System.Text.Json.Serialization;
using Exoforge.Plugin.SDK;
using Exoforge.Plugins.Generated;

namespace Exoforge.Plugins.SnakeConfig;

[ExoService("snake_config", Version = "1.0.0",
    Category = "Game", Title = "Snake Configuration", Icon = "⚙️")]
public class SnakeConfigPlugin
{
    private const string Table = "snake_config";
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
        var record = Database?.Get<SnakeConfigRecord>(Table, ConfigKey);
        if (record == null)
        {
            record = new SnakeConfigRecord();
            Database?.Put(Table, ConfigKey, record);
        }
        return record.ToData();
    }

    [ExoAction]
    public SnakeConfigData UpdateConfig(
        string? snakeColor,
        string? appleColor,
        int? applePoints,
        string? backgroundFileId,
        string? backgroundAddressable)
    {
        var current = Database?.Get<SnakeConfigRecord>(Table, ConfigKey) ?? new SnakeConfigRecord();
        var updated = current.With(snakeColor, appleColor, applePoints, backgroundFileId, backgroundAddressable);

        Database?.Put(Table, ConfigKey, updated);
        Logger?.Info($"[snake_config] Updated config: points={updated.ApplePoints}, snake={updated.SnakeColor}");

        return updated.ToData();
    }
}

[ExoSingletonResource("snake_config", PrimaryKey = "key")]
public record SnakeConfigRecord
{
    [JsonPropertyName("key"), ExoColumn(Label = "Key")]
    public string Key { get; init; } = "active_config";

    [JsonPropertyName("snake_color"), ExoColumn(Label = "Snake Color", InputType = ExoInput.Color)]
    public string SnakeColor { get; init; } = "#3DD157";

    [JsonPropertyName("apple_color"), ExoColumn(Label = "Apple Color", InputType = ExoInput.Color)]
    public string AppleColor { get; init; } = "#FF525C";

    [JsonPropertyName("apple_points"), ExoColumn(Label = "Apple Points")]
    public int ApplePoints { get; init; } = 10;

    [JsonPropertyName("background_file_id"), ExoColumn(Label = "Background File ID", Role = "file_reference", Bucket = "snake_assets")]
    public string BackgroundFileId { get; init; } = "";

    [JsonPropertyName("background_addressable"), ExoColumn(Label = "Background Addressable", InputType = IUnityAddressablesService.AddressableRef)]
    public string BackgroundAddressable { get; init; } = "Background_CyberGrid";

    [JsonPropertyName("updated_at"), ExoColumn(Label = "Updated At")]
    public long UpdatedAt { get; init; }

    public SnakeConfigData ToData() => new(SnakeColor, AppleColor, ApplePoints, BackgroundFileId, BackgroundAddressable);

    public SnakeConfigRecord With(string? snake, string? apple, int? points, string? fileId, string? addressable) => this with
    {
        SnakeColor = !string.IsNullOrEmpty(snake) ? snake : SnakeColor,
        AppleColor = !string.IsNullOrEmpty(apple) ? apple : AppleColor,
        ApplePoints = points.HasValue && points.Value > 0 ? points.Value : ApplePoints,
        BackgroundFileId = fileId ?? BackgroundFileId,
        BackgroundAddressable = addressable ?? BackgroundAddressable,
        UpdatedAt = DateTimeOffset.UtcNow.ToUnixTimeSeconds()
    };
}

// DTO
public record SnakeConfigData(
    [property: JsonPropertyName("snake_color")] string SnakeColor = "#3DD157",
    [property: JsonPropertyName("apple_color")] string AppleColor = "#FF525C",
    [property: JsonPropertyName("apple_points")] int ApplePoints = 10,
    [property: JsonPropertyName("background_file_id")] string BackgroundFileId = "",
    [property: JsonPropertyName("background_addressable")] string BackgroundAddressable = "Background_CyberGrid"
);
