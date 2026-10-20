using System;
using Exoforge.Plugin.SDK;
using Exoforge.Plugins.Generated;

namespace Exoforge.Plugins.SnakeConfig;

[ExoService("snake_config", Version = "1.0.0",
    Category = "Game", Title = "Snake Configuration", Icon = "⚙️")]
public class SnakeConfigPlugin
{
    [ExoAction]
    public SnakeConfigDto GetConfig()
    {
        var schema = ExoServices.Database.First<SnakeConfigSchema>();
        if (schema == null)
        {
            schema = new SnakeConfigSchema();
            ExoServices.Database.Put(schema);
        }
        return new SnakeConfigDto(schema);
    }

    [ExoAction]
    public SnakeConfigDto UpdateConfig(
        string? snakeColor,
        string? appleColor,
        int? applePoints,
        string? backgroundFileId,
        string? backgroundAddressable)
    {
        var current = ExoServices.Database.First<SnakeConfigSchema>() ?? new SnakeConfigSchema();
        var updated = current.With(snakeColor, appleColor, applePoints, backgroundFileId, backgroundAddressable);

        ExoServices.Database.Put(updated);
        ExoServices.Logger.Info($"[snake_config] Updated config: points={updated.ApplePoints}, snake={updated.SnakeColor}");

        return new SnakeConfigDto(updated);
    }
}

[ExoSingletonResource("snake_config", PrimaryKey = "key")]
public record SnakeConfigSchema
{
    [ExoColumn(Label = "Key")]
    public string Key { get; init; } = "active_config";

    [ExoColumn(Label = "Snake Color", InputType = ExoInput.Color)]
    public string SnakeColor { get; init; } = "#3DD157";

    [ExoColumn(Label = "Apple Color", InputType = ExoInput.Color)]
    public string AppleColor { get; init; } = "#FF525C";

    [ExoColumn(Label = "Apple Points")]
    public int ApplePoints { get; init; } = 10;

    [ExoColumn(Label = "Background File ID", Role = "file_reference", Bucket = "snake_assets")]
    public string BackgroundFileId { get; init; } = "";

    [ExoColumn(Label = "Background Addressable", InputType = IUnityAddressablesService.AddressableRef)]
    public string BackgroundAddressable { get; init; } = "Background_CyberGrid";

    [ExoColumn(Label = "Updated At")]
    public long UpdatedAt { get; init; }

    public SnakeConfigSchema With(string? snake, string? apple, int? points, string? fileId, string? addressable) => this with
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
public record SnakeConfigDto(
    string SnakeColor = "#3DD157",
    string AppleColor = "#FF525C",
    int ApplePoints = 10,
    string BackgroundFileId = "",
    string BackgroundAddressable = "Background_CyberGrid"
)
{
    public SnakeConfigDto(SnakeConfigSchema schema)
        : this(
            schema.SnakeColor,
            schema.AppleColor,
            schema.ApplePoints,
            schema.BackgroundFileId,
            schema.BackgroundAddressable)
    {
    }
}
