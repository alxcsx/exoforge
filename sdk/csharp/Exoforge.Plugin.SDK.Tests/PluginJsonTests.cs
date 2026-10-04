using System;
using System.Collections.Generic;
using System.Text.Json.Serialization;
using Exoforge.Plugin.SDK;
using Xunit;

namespace Exoforge.Plugin.SDK.Tests;

public record TypedScoreRow
{
    public string PlayerId { get; init; } = "";
    public string Name { get; init; } = "";
    public int Score { get; init; }
}

/// <summary>Mirrors what a plugin ships for NativeAOT: snake_case names, one entry per record type.</summary>
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
