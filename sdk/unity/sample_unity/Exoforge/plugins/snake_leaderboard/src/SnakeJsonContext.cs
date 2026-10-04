using System.Text.Json.Serialization;

namespace Exoforge.Plugins.SnakeLeaderboard;

/// <summary>
/// Compile-time JSON metadata for this plugin's own records. Generated contract stubs register their
/// own context (see the generated module initializer), and <c>PluginJson</c> combines them.
/// </summary>
[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.SnakeCaseLower)]
[JsonSerializable(typeof(SnakeScoreRecord))]
[JsonSerializable(typeof(SnakeLeaderboardEntry))]
internal partial class SnakeJsonContext : JsonSerializerContext
{
}
