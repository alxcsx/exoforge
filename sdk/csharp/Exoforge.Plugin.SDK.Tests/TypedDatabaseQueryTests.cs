using System;
using System.Collections.Generic;
using Xunit;

namespace Exoforge.Plugin.SDK.Tests;

[ExoResource("query_orders")]
public record QueryOrder
{
    public string Id { get; init; } = "";
    [ExoColumn(Name = "item_key", ForeignKey = true, ReferencesType = typeof(QueryItem))]
    public string ItemId { get; init; } = "";
    [ExoNavigation(nameof(ItemId))]
    public QueryItem? Item { get; set; }
    public int Total { get; init; }
    public bool IsPaid { get; init; }
}

[ExoResource("query_items")]
public record QueryItem { public string Id { get; init; } = ""; }

// The shape of another extension's record, as a generated stub class is: plain, no [ExoResource].
public class StubItem { public string Id { get; set; } = ""; public string Nome { get; set; } = ""; }

[ExoResource("stub_orders")]
public record StubOrder
{
    public string Id { get; init; } = "";
    [ExoColumn(ForeignKey = true, References = "itens.id")]
    public string ItemId { get; init; } = "";
    [ExoNavigation(nameof(ItemId))]
    public StubItem? Item { get; set; }
}

public class TypedDatabaseQueryTests
{
    private sealed class RecordingDatabase : IDatabase
    {
        public string? Sql;
        public object?[] Args = Array.Empty<object?>();
        public readonly Dictionary<(string, string), object> Rows = new();
        public T? Get<T>(string table, string key) => Rows.TryGetValue((table, key), out var row) ? (T)row : default;
        public IReadOnlyList<T> All<T>(string table) => Array.Empty<T>();
        public void Put<T>(string table, string key, T value) => Rows[(table, key)] = value!;
        public void Delete(string table, string key) { }
        public IReadOnlyList<T> Query<T>(string sql, params object?[] args)
        {
            Sql = sql; Args = args;
            if (typeof(T).Name.Contains("DatabaseCount", StringComparison.Ordinal))
            {
                var count = Activator.CreateInstance(typeof(T))!;
                typeof(T).GetProperty("Value")!.SetValue(count, 3L);
                return new[] { (T)count };
            }
            return Array.Empty<T>();
        }
        public T? QuerySingle<T>(string sql, params object?[] args) => default;
        public int Execute(string sql, params object?[] args) => 0;
    }

    [Fact]
    public void Where_OrderAndPaging_UseMappedColumnsAndParameters()
    {
        var db = new RecordingDatabase();
        var minimum = 25;
        db.Table<QueryOrder>().Where(x => x.IsPaid && x.Total >= minimum && x.Id != "cancelled")
            .OrderByDescending(x => x.Total).Skip(4).Take(2).ToList();

        Assert.Equal("SELECT * FROM \"query_orders\" WHERE ((\"is_paid\" = TRUE AND \"total\" >= $1) AND \"id\" <> $2) ORDER BY \"total\" DESC LIMIT 2 OFFSET 4", db.Sql);
        Assert.Equal(new object?[] { 25, "cancelled" }, db.Args);
    }

    [Fact]
    public void FindBy_Count_ExistsAndInclude_UseTypedTableMetadata()
    {
        var db = new RecordingDatabase();
        var table = db.Table<QueryOrder>();
        db.Rows[("query_items", "sword")] = new QueryItem { Id = "sword" };

        Assert.Equal(3, table.Where(x => !x.IsPaid || x.Total < 5).Count());
        Assert.Contains("FROM (SELECT * FROM \"query_orders\"", db.Sql);
        Assert.Contains("NOT \"is_paid\" = TRUE", db.Sql);
        Assert.Equal("sword", table.Include<QueryItem>(new QueryOrder { ItemId = "sword" }, x => x.ItemId)!.Id);
        table.FindBy(x => x.Id == "one");
        Assert.Contains("LIMIT 1", db.Sql);
    }

    [Fact]
    public void Include_RequiresExplicitNavigationPairing()
    {
        var db = new RecordingDatabase();
        var query = db.Table<QueryOrder>().Include(x => x.Item);

        Assert.Throws<NotSupportedException>(() => query.ToList());
    }

    [Fact]
    public void Include_AcceptsAPlainStubClassForAnotherExtensionsResource()
    {
        var db = new RecordingDatabase();
        // The FK declares the target (References); the navigation type is only the shape rows are read into.
        var query = db.Table<StubOrder>().Include(x => x.Item);

        Assert.Throws<NotSupportedException>(() => query.ToList());   // reached the host call, not a pairing error
    }
}
