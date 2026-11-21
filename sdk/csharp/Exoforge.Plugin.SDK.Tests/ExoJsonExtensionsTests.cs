using System.Collections.Generic;
using System.Text.Json;
using Exoforge.Plugin.SDK;
using Xunit;

namespace Exoforge.Plugin.SDK.Tests;

public class ExoJsonExtensionsTests
{
    private static JsonElement J(string json) => JsonDocument.Parse(json).RootElement.Clone();

    private sealed class Row { public string ItemId { get; set; } = ""; public int Quantidade { get; set; } }

    [Fact]
    public void Undefined_and_null_never_throw()
    {
        var undefined = default(JsonElement);
        Assert.Null(undefined.As<Row>());
        Assert.Empty(undefined.AsList<Row>());
        Assert.Empty(undefined.AsDictionary<Row>());
        Assert.Null(undefined.Path("a"));
        Assert.Null(undefined.GetString("a"));
        Assert.Empty(undefined.Items());
        Assert.Equal("null", undefined.ToJson());
        Assert.Null(J("null").As<Row>());
    }

    [Fact]
    public void As_reads_snake_case_into_pascal_case_properties()
    {
        var row = J("{\"item_id\":\"sword\",\"quantidade\":3}").As<Row>();
        Assert.Equal("sword", row!.ItemId);
        Assert.Equal(3, row.Quantidade);
    }

    [Fact]
    public void AsList_and_AsDictionary_skip_nulls()
    {
        var list = J("[{\"item_id\":\"a\"},null,{\"item_id\":\"b\"}]").AsList<Row>();
        Assert.Equal(new[] { "a", "b" }, list.ConvertAll(r => r.ItemId));
        var dict = J("{\"x\":{\"item_id\":\"a\"},\"y\":null}").AsDictionary<Row>();
        Assert.Single(dict);
        Assert.Equal("a", dict["x"].ItemId);
        Assert.Empty(J("{\"a\":1}").AsList<Row>());
    }

    [Fact]
    public void TryAs_reports_a_value_of_the_wrong_shape_without_throwing()
    {
        Assert.False(J("\"text\"").TryAs<Row>(out _));
        Assert.True(J("{\"item_id\":\"a\"}").TryAs<Row>(out var ok));
        Assert.Equal("a", ok!.ItemId);
    }

    [Theory]
    [InlineData("a.b[1].c", "x")]
    [InlineData("a.b[0].c", null)]            // c is absent on the first element
    [InlineData("a['odd-key']", "ok")]
    [InlineData("a.['odd key']", "ok2")]
    [InlineData("a.b[5].c", null)]            // out of range
    [InlineData("a.b[-1].c", null)]           // negative index
    [InlineData("a.b[x]", null)]
    [InlineData("a.b[", null)]
    [InlineData("a..b", null)]
    [InlineData("a.zzz", null)]
    [InlineData("", null)]
    public void Path_follows_keys_indexes_and_quoted_keys(string path, string? expected)
    {
        var doc = J("{\"a\":{\"b\":[{\"d\":1},{\"c\":\"x\"}],\"odd-key\":\"ok\",\"odd key\":\"ok2\"}}");
        Assert.Equal(expected, doc.GetString(path));
    }

    [Fact]
    public void Typed_getters_convert_what_they_can_and_return_null_otherwise()
    {
        var doc = J("{\"n\":5,\"f\":1.9,\"s\":\"12\",\"t\":true,\"w\":\"abc\",\"o\":{}}");
        Assert.Equal(5L, doc.GetLong("n"));
        Assert.Null(doc.GetLong("f"));                 // not silently truncated
        Assert.Equal(12L, doc.GetLong("s"));
        Assert.Equal(1.9, doc.GetDouble("f"));
        Assert.Equal(true, doc.GetBool("t"));
        Assert.Equal("true", doc.GetString("t"));
        Assert.Null(doc.GetLong("w"));
        Assert.Null(doc.GetString("o"));               // an object is not a string, and it does not throw
        Assert.Null(doc.GetBool("w"));
    }

    [Fact]
    public void Parsing_ignores_the_current_culture()
    {
        var saved = System.Globalization.CultureInfo.CurrentCulture;
        try
        {
            System.Globalization.CultureInfo.CurrentCulture = new System.Globalization.CultureInfo("pt-BR");
            Assert.Equal(1.5, J("{\"v\":\"1.5\"}").GetDouble("v"));
        }
        finally { System.Globalization.CultureInfo.CurrentCulture = saved; }
    }

    [Fact]
    public void FromObject_and_ToJson_round_trip()
    {
        var el = ExoJsonExtensions.FromObject(new Row { ItemId = "a", Quantidade = 2 });
        Assert.Equal("a", el.GetString("item_id") ?? el.GetString("ItemId"));
        Assert.Contains("\n", el.ToJson(indent: true));
    }
}
