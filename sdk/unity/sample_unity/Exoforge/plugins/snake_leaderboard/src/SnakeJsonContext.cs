using System.Text.Json.Serialization;

namespace Exoforge.Plugins.SnakeLeaderboard;

/// <summary>
/// Compile-time JSON metadata for every record that crosses the plugin boundary. NativeAOT trims
/// reflection, so <see cref="System.Text.Json"/> needs a source-generated context; the (apparently
/// empty) class body is filled in by the source generator from the <c>[JsonSerializable]</c>
/// attributes. Add a type here whenever a new record crosses an action, event, or the database.
///
/// The naming policy must match the host wire format (snake_case).
/// </summary>
[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.SnakeCaseLower)]
[JsonSerializable(typeof(SnakeScoreRecord))]
[JsonSerializable(typeof(SnakeLeaderboardEntry))]
[JsonSerializable(typeof(PlayerProfileRequest))]
[JsonSerializable(typeof(PlayerProfile))]
[JsonSerializable(typeof(PlayerProfileResponse))]
internal partial class SnakeJsonContext : JsonSerializerContext
{
}
