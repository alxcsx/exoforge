using System;
using System.Collections.Generic;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using Exoforge.Plugin.SDK;
using Xunit;

namespace Exoforge.Plugin.SDK.Tests;

/// <summary>
/// The values JSON cannot hold. Each of these used to be written raw, which made the whole frame
/// unparseable on the host - so a plugin worked until a position went sideways, and then failed with
/// a decode error naming no field.
/// </summary>
public class UnrepresentableValueTests
{
    [Theory]
    [InlineData(double.NaN)]
    [InlineData(double.PositiveInfinity)]
    [InlineData(double.NegativeInfinity)]
    public void A_non_finite_double_is_refused_rather_than_written_as_invalid_json(double value)
    {
        var error = Assert.Throws<InvalidOperationException>(() => PluginJson.Serialize(value));

        Assert.Contains("NaN or infinity", error.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void A_non_finite_float_is_refused_too()
    {
        Assert.Throws<InvalidOperationException>(() => PluginJson.Serialize(float.NaN));
    }

    [Fact]
    public void A_finite_double_still_goes_through()
    {
        Assert.Equal("1.5", PluginJson.Serialize(1.5));
    }

    /// <summary>A truncated emoji is the usual way to get one of these.</summary>
    [Fact]
    public void A_lone_surrogate_does_not_produce_invalid_json()
    {
        string json = PluginJson.Serialize("half \ud83d");

        Assert.Equal("\"half \ufffd\"", json);
        JsonNode.Parse(json);
    }

    [Fact]
    public void A_matched_pair_survives_intact()
    {
        Assert.Equal("\"ok \ud83d\ude00\"", PluginJson.Serialize("ok \ud83d\ude00"));
    }
}

/// <summary>
/// An anonymous return, which is the case the hint exists for.
/// </summary>
/// <remarks>
/// It serializes here - a test run has reflection - and fails in the published plugin, which is the
/// worst shape a failure can take: green tests, broken build. And the obvious advice cannot be
/// followed, because a compiler-generated type cannot be named in source, so
/// <c>[JsonSerializable(typeof(...))]</c> is not missing, it is unwritable.
/// </remarks>
public class AnonymousTypeTests
{
    /// <summary>
    /// Which is the point of being framework-dependent: reflection is available, so an anonymous
    /// object serialises and a record is a contract rather than a requirement.
    /// </summary>
    [Fact]
    public void An_anonymous_object_serializes_where_reflection_is_available()
    {
        Assert.Equal("{\"value\":1}", PluginJson.Serialize(new { value = 1 }));
    }

}

public record TypedScoreRow
{
    public string PlayerId { get; init; } = "";
    public string Name { get; init; } = "";
    public int Score { get; init; }
}

/// <summary>A context a plugin may still declare itself: snake_case names, one entry per record.</summary>
[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.SnakeCaseLower)]
[JsonSerializable(typeof(TypedScoreRow))]
internal partial class TestJsonContext : JsonSerializerContext
{
}

public record TypedOtherRow
{
    public int Value { get; init; }
}

[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.SnakeCaseLower)]
[JsonSerializable(typeof(TypedOtherRow))]
internal partial class OtherJsonContext : JsonSerializerContext
{
}

public class StaticInjectedPlugin
{
    [Inject("database")]
    public static IDatabase? Database { get; set; }

    [Inject]
    public static ILogger? Logger { get; set; }
}

public class PluginJsonTests
{
    [Fact]
    public void Serialize_UsesSnakeCase_AndRoundTrips()
    {
        var json = PluginJson.Serialize(new TypedScoreRow { PlayerId = "p1", Name = "Viper", Score = 7 });

        Assert.Contains("\"player_id\":\"p1\"", json);

        var back = PluginJson.Deserialize<TypedScoreRow>(json);
        Assert.NotNull(back);
        Assert.Equal("p1", back!.PlayerId);
        Assert.Equal(7, back.Score);
    }

    [Fact]
    public void Serialize_ListBecomesJsonArray()
    {
        var json = PluginJson.Serialize(new List<TypedScoreRow>
        {
            new() { PlayerId = "a", Score = 1 },
            new() { PlayerId = "b", Score = 2 }
        });

        Assert.StartsWith("[", json);
        Assert.Contains("\"player_id\":\"a\"", json);
        Assert.Contains("\"player_id\":\"b\"", json);
    }

    [Fact]
    public void Serialize_WithSourceGeneratedContext_RoundTrips()
    {
        PluginJson.UseContext(new TestJsonContext());
        try
        {
            var json = PluginJson.Serialize(new TypedScoreRow { PlayerId = "p2", Score = 9 });
            Assert.Contains("\"player_id\":\"p2\"", json);
            Assert.Equal(9, PluginJson.Deserialize<TypedScoreRow>(json)!.Score);
        }
        finally
        {
            PluginJson.UseContext(null);
        }
    }

    [Fact]
    public void AddContext_CombinesMultipleContexts()
    {
        PluginJson.UseContext(null);
        try
        {
            PluginJson.AddContext(new TestJsonContext());
            PluginJson.AddContext(new OtherJsonContext());

            Assert.Equal(9, PluginJson.Deserialize<TypedScoreRow>("{\"score\":9}")!.Score);
            Assert.Equal(5, PluginJson.Deserialize<TypedOtherRow>("{\"value\":5}")!.Value);
        }
        finally
        {
            PluginJson.UseContext(null);
        }
    }

    [Fact]
    public void Wire_InjectsStaticCapabilities()
    {
        var context = new HostPluginContext("static_plugin");
        StaticInjectedPlugin.Database = null;
        StaticInjectedPlugin.Logger = null;

        HostPluginContext.Wire(new StaticInjectedPlugin(), context);

        Assert.Same(context.Database, StaticInjectedPlugin.Database);
        Assert.Same(context.Logger, StaticInjectedPlugin.Logger);
    }
}
