namespace Exoforge.Plugins.SnakeLeaderboard;

/// <summary>
/// Request payload for the <c>player_data.get_player</c> action. Typed (not an anonymous object) so
/// it is covered by the plugin's JSON context and stays NativeAOT-safe.
/// </summary>
public record PlayerProfileRequest
{
    public string PlayerId { get; init; } = "";
}

/// <summary>
/// The slice of a <c>player_data</c> profile we read to resolve a display name.
/// </summary>
public record PlayerProfile
{
    public string PlayerId { get; init; } = "";
    public string? Name { get; init; }
}

/// <summary>
/// Response envelope of the <c>player_data.get_player</c> action.
/// </summary>
public record PlayerProfileResponse
{
    public PlayerProfile? Player { get; init; }
}
