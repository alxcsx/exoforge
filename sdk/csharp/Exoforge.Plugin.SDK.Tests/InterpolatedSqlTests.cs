using System;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using Xunit;

namespace Exoforge.Plugin.SDK.Tests;

public class InterpolatedSqlTests
{
    private record ScoreRow(string PlayerId, int Score);

    private sealed class RecordingDatabase : IDatabase
    {
        public string? LastSql { get; private set; }
        public object?[]? LastArgs { get; private set; }
        public IReadOnlyList<object> QueryResult { get; set; } = Array.Empty<object>();
        public int ExecuteResult { get; set; }

        public T? Get<T>(string table, string key) => default;
        public IReadOnlyList<T> All<T>(string table) => Array.Empty<T>();
        public void Put<T>(string table, string key, T value) { }
        public void Delete(string table, string key) { }

        public IReadOnlyList<T> Query<T>(string sql, params object?[] args)
        {
            LastSql = sql;
            LastArgs = args;
            var list = new List<T>(QueryResult.Count);
            foreach (var item in QueryResult) list.Add((T)item);
            return list;
        }

        public T? QuerySingle<T>(string sql, params object?[] args)
        {
            LastSql = sql;
            LastArgs = args;
            return default;
        }

        public int Execute(string sql, params object?[] args)
        {
            LastSql = sql;
            LastArgs = args;
            return ExecuteResult;
        }
    }

    [Fact]
    public void QuerySql_GeneratesPositionalPlaceholdersAndPreservesArgumentOrder()
    {
        var expected = new ScoreRow("p1", 250);
        var db = new RecordingDatabase { QueryResult = new object[] { expected } };

        string region = "eu";
        int minScore = 100;
        int limit = 10;

        var rows = db.QuerySql<ScoreRow>(
            $"SELECT player_id, score FROM scores WHERE region = {region} AND score >= {minScore} LIMIT {limit}");

        Assert.Equal(
            "SELECT player_id, score FROM scores WHERE region = $1 AND score >= $2 LIMIT $3",
            db.LastSql);
        Assert.Equal(new object?[] { "eu", 100, 10 }, db.LastArgs);
        Assert.Single(rows);
        Assert.Equal(expected, rows[0]);
    }

    [Fact]
    public void ExecuteSql_GeneratesPositionalPlaceholdersAndReturnsAffectedRows()
    {
        var db = new RecordingDatabase { ExecuteResult = 3 };

        int score = 500;
        string playerId = "p1";

        int affected = db.ExecuteSql($"UPDATE scores SET score = {score} WHERE player_id = {playerId}");

        Assert.Equal("UPDATE scores SET score = $1 WHERE player_id = $2", db.LastSql);
        Assert.Equal(new object?[] { 500, "p1" }, db.LastArgs);
        Assert.Equal(3, affected);
    }

    [Fact]
    public void QuerySql_InjectionString_StaysAnArgumentAndIsNotConcatenated()
    {
        var db = new RecordingDatabase();
        string evil = "'; DROP TABLE scores; --";

        db.QuerySql<ScoreRow>($"SELECT * FROM scores WHERE player_id = {evil}");

        Assert.Equal("SELECT * FROM scores WHERE player_id = $1", db.LastSql);
        Assert.DoesNotContain("DROP TABLE", db.LastSql);
        Assert.Equal(new object?[] { evil }, db.LastArgs);
    }

    [Fact]
    public void ExecuteSql_NullArgument_PreservedAsNull()
    {
        var db = new RecordingDatabase();
        string? nickname = null;
        string playerId = "p1";

        db.ExecuteSql($"UPDATE players SET nickname = {nickname} WHERE id = {playerId}");

        Assert.Equal("UPDATE players SET nickname = $1 WHERE id = $2", db.LastSql);
        Assert.NotNull(db.LastArgs);
        Assert.Equal(2, db.LastArgs!.Length);
        Assert.Null(db.LastArgs[0]);
        Assert.Equal("p1", db.LastArgs[1]);
    }

    [Fact]
    public void QuerySql_FormatSpecifiersAndAlignment_AreIgnoredAndRawValuePassed()
    {
        var db = new RecordingDatabase();
        double minScore = 12.345;
        string tag = "vip";

        db.QuerySql<ScoreRow>($"SELECT * FROM scores WHERE score >= {minScore:F1} AND tag = {tag,-10}");

        Assert.Equal("SELECT * FROM scores WHERE score >= $1 AND tag = $2", db.LastSql);
        Assert.Equal(new object?[] { 12.345, "vip" }, db.LastArgs);
    }

    [Fact]
    public void QuerySql_ReusedFormatIndexEscapedBracesAndNoArgs_Work()
    {
        var db = new RecordingDatabase();

        var reused = FormattableStringFactory.Create(
            "SELECT '{{}}' AS meta FROM t WHERE a = {0} OR b = {0}",
            "same");
        db.QuerySql<ScoreRow>(reused);

        Assert.Equal("SELECT '{}' AS meta FROM t WHERE a = $1 OR b = $2", db.LastSql);
        Assert.Equal(new object?[] { "same", "same" }, db.LastArgs);

        db.QuerySql<ScoreRow>($"SELECT * FROM scores");

        Assert.Equal("SELECT * FROM scores", db.LastSql);
        Assert.Empty(db.LastArgs!);
    }

    [Fact]
    public void QuerySqlAndExecuteSql_ThrowOnNullArguments()
    {
        var db = new RecordingDatabase();
        IDatabase nullDb = null!;
        FormattableString nullSql = null!;

        Assert.Throws<ArgumentNullException>(() => nullDb.QuerySql<ScoreRow>($"SELECT 1"));
        Assert.Throws<ArgumentNullException>(() => db.QuerySql<ScoreRow>(nullSql));
        Assert.Throws<ArgumentNullException>(() => nullDb.ExecuteSql($"DELETE FROM t"));
        Assert.Throws<ArgumentNullException>(() => db.ExecuteSql(nullSql));
    }
}
