using System.Text.Json.Serialization;

namespace Exoforge.Plugins.SnakeLeaderboard;

// Source-generated JSON for this plugin's records — NativeAOT has no reflection. Generated
// service clients register their own context and the SDK combines them.
[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.SnakeCaseLower)]
[JsonSerializable(typeof(SnakeScoreRecord))]
[JsonSerializable(typeof(SnakeLeaderboardEntry))]
[JsonSerializable(typeof(SnakeScoreSubmitted))]
internal partial class SnakeJsonContext : JsonSerializerContext
{
}
