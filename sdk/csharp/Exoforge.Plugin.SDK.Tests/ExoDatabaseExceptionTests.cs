using System;
using Exoforge.Plugin.SDK;
using Xunit;

namespace Exoforge.Plugin.SDK.Tests;

public class ExoDatabaseExceptionTests
{
    private sealed class MockTransport : IPluginTransport
    {
        public Func<string, string, string?>? OnDbGet { get; set; }
        public Func<string, string?>? OnDbAll { get; set; }
        public Func<string, string, string, bool>? OnDbPut { get; set; }
        public Func<string, string, bool>? OnDbDelete { get; set; }

        public bool EmitEvent(string topic, string evt, string payloadJson) => true;
        public string? CallAction(string service, string action, string payloadJson) => null;
        public void Log(int level, string message) { }
        public string? DbGet(string table, string key) => OnDbGet != null ? OnDbGet(table, key) : null;
        public string? DbAll(string table) => OnDbAll != null ? OnDbAll(table) : null;
        public bool DbPut(string table, string key, string valueJson) => OnDbPut != null ? OnDbPut(table, key, valueJson) : true;
        public bool DbDelete(string table, string key) => OnDbDelete != null ? OnDbDelete(table, key) : true;
        public long ClockNow() => 0;
    }

    [Fact]
    public void Exception_PropertiesAndConstructors_AreCorrect()
    {
        var ex = new ExoDatabaseException("users", "table not found");
        Assert.Equal("users", ex.Table);
        Assert.Equal("table not found", ex.ServerError);
        Assert.Contains("users", ex.Message);
        Assert.Contains("table not found", ex.Message);

        var inner = new InvalidOperationException("inner");
        var exWithInner = new ExoDatabaseException("items", "db connection error", inner);
        Assert.Equal("items", exWithInner.Table);
        Assert.Equal("db connection error", exWithInner.ServerError);
        Assert.Same(inner, exWithInner.InnerException);
    }

    [Fact]
    public void HostDatabase_Put_ThrowsExoDatabaseException_OnFailure()
    {
        var mock = new MockTransport
        {
            OnDbPut = (table, key, val) => false
        };
        HostBridge.UseTransport(mock);

        var context = new HostPluginContext("test_ext");
        Action action = () => context.Database.Put("scores", "player1", "{\"score\":100}");
        var ex = Assert.Throws<ExoDatabaseException>(action);

        Assert.Equal("scores", ex.Table);
        Assert.Contains("failed", ex.ServerError);
    }

    [Fact]
    public void HostDatabase_Delete_ThrowsExoDatabaseException_OnFailure()
    {
        var mock = new MockTransport
        {
            OnDbDelete = (table, key) => false
        };
        HostBridge.UseTransport(mock);

        var context = new HostPluginContext("test_ext");
        Action action = () => context.Database.Delete("scores", "player1");
        var ex = Assert.Throws<ExoDatabaseException>(action);

        Assert.Equal("scores", ex.Table);
        Assert.Contains("failed", ex.ServerError);
    }

    [Fact]
    public void HostDatabase_Get_ThrowsExoDatabaseException_OnErrorJson()
    {
        var mock = new MockTransport
        {
            OnDbGet = (table, key) => "{\"ok\":false,\"error\":\"no such table: scores\"}"
        };
        HostBridge.UseTransport(mock);

        var context = new HostPluginContext("test_ext");
        Action action = () => context.Database.Get<string>("scores", "player1");
        var ex = Assert.Throws<ExoDatabaseException>(action);

        Assert.Equal("scores", ex.Table);
        Assert.Equal("no such table: scores", ex.ServerError);
    }

    [Fact]
    public void HostDatabase_All_ThrowsExoDatabaseException_OnErrorJson()
    {
        var mock = new MockTransport
        {
            OnDbAll = (table) => "{\"ok\":false,\"error\":\"database disk image is malformed\"}"
        };
        HostBridge.UseTransport(mock);

        var context = new HostPluginContext("test_ext");
        Action action = () => context.Database.All<string>("scores");
        var ex = Assert.Throws<ExoDatabaseException>(action);

        Assert.Equal("scores", ex.Table);
        Assert.Equal("database disk image is malformed", ex.ServerError);
    }

    [Fact]
    public void HostDatabase_Get_ThrowsExoDatabaseException_OnNonStringErrorProperty()
    {
        var mock = new MockTransport
        {
            OnDbGet = (table, key) => "{\"ok\":false,\"error\":{\"code\":\"missing_resource_table\",\"details\":123}}"
        };
        HostBridge.UseTransport(mock);

        var context = new HostPluginContext("test_ext");
        Action action = () => context.Database.Get<string>("scores", "player1");
        var ex = Assert.Throws<ExoDatabaseException>(action);

        Assert.Equal("scores", ex.Table);
        Assert.Contains("missing_resource_table", ex.ServerError);
    }
}
