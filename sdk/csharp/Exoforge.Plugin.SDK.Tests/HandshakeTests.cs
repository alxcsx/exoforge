using System.IO;
using System.Text;
using Exoforge.Plugin.SDK;
using Xunit;

namespace Exoforge.Plugin.SDK.Tests;

[ExoService("handshake_probe", Version = "1.0.0")]
public class HandshakeProbe
{
    [ExoAction("ping", Mode = ActionMode.Sync)]
    public int Ping() => 42;

    [ExoAction("emit", Mode = ActionMode.Sync)]
    public string Emit()
    {
        HostBridge.EmitEvent("probe:events", "probe_emitted", new { });
        return "done";
    }
}

/// <summary>
/// The hello exchange. The host declares its protocol and the frames it handles; the plugin answers
/// with its own, and from then on both sides rely on what was said instead of assuming it.
///
/// The other implementation is `Exoforge.Drivers.Runtime.PluginProtocol` and the spec is Agents.MD,
/// "The plugin wire protocol"; these assertions are this side's golden copy of it.
/// </summary>
public class HandshakeTests
{
    [Fact]
    public void The_plugin_answers_hello_with_its_protocol_and_capabilities()
    {
        var output = new MemoryStream();

        PluginHost.RunInstance(
            new HandshakeProbe(),
            Lines("{\"type\":\"hello\",\"protocol\":1,\"host\":\"exoforge\",\"capabilities\":[\"action_result\",\"host_call\",\"host_log\"]}"),
            output,
            null);

        Assert.True(HostBridge.Handshaken);
        Assert.Equal(1, HostBridge.HostProtocol);
        Assert.True(HostBridge.HostSupports("host_call"));
        Assert.True(HostBridge.HostSupports("host_log"));

        string written = Encoding.UTF8.GetString(output.ToArray());
        Assert.Contains("\"type\":\"hello\"", written);
        Assert.Contains("\"protocol\":1", written);
        Assert.Contains("\"capabilities\":[\"action\",\"event\",\"host_call_result\",\"lifecycle\"]", written);
    }

    [Fact]
    public void A_host_that_did_not_declare_host_call_fails_the_action_with_that_reason()
    {
        var output = new MemoryStream();

        // The host declares host_log (so the trace has somewhere to go) but not host_call.
        PluginHost.RunInstance(
            new HandshakeProbe(),
            Lines(
                "{\"type\":\"hello\",\"protocol\":1,\"host\":\"exoforge\",\"capabilities\":[\"action_result\",\"host_log\"]}",
                "{\"type\":\"action\",\"id\":1,\"action\":\"emit\",\"payload\":{}}"),
            output,
            null);

        Assert.False(HostBridge.HostSupports("host_call"));

        string written = Encoding.UTF8.GetString(output.ToArray());

        // The trace says why, and the caller gets an error rather than a hang on an unanswered call.
        Assert.Contains("\"type\":\"host_log\"", written);
        Assert.Contains("\"status\":\"error\"", written);
        Assert.Contains("host_call", written);
    }

    [Fact]
    public void Host_hello_with_postgres_dialect_sets_HostBridge_and_Exo_Database_Dialect()
    {
        try
        {
            PluginHost.RunInstance(
                new HandshakeProbe(),
                Lines("{\"type\":\"hello\",\"protocol\":1,\"host\":\"exoforge\",\"capabilities\":[\"action_result\",\"host_call\",\"host_log\"],\"dialect\":\"postgres\"}"),
                new MemoryStream(),
                null);

            Assert.Equal(DatabaseDialect.Postgres, HostBridge.DatabaseDialect);
            Assert.Equal(DatabaseDialect.Postgres, Exo.Database.Dialect);
        }
        finally
        {
            HostBridge.UseTransport(null);
        }
    }

    [Fact]
    public void Host_hello_with_sqlite_dialect_sets_HostBridge_and_Exo_Database_Dialect()
    {
        try
        {
            PluginHost.RunInstance(
                new HandshakeProbe(),
                Lines("{\"type\":\"hello\",\"protocol\":1,\"host\":\"exoforge\",\"capabilities\":[\"action_result\",\"host_call\",\"host_log\"],\"dialect\":\"sqlite\"}"),
                new MemoryStream(),
                null);

            Assert.Equal(DatabaseDialect.Sqlite, HostBridge.DatabaseDialect);
            Assert.Equal(DatabaseDialect.Sqlite, Exo.Database.Dialect);
        }
        finally
        {
            HostBridge.UseTransport(null);
        }
    }

    [Fact]
    public void Host_hello_without_dialect_keeps_DatabaseDialect_Unknown()
    {
        try
        {
            PluginHost.RunInstance(
                new HandshakeProbe(),
                Lines("{\"type\":\"hello\",\"protocol\":1,\"host\":\"exoforge\",\"capabilities\":[\"action_result\",\"host_call\",\"host_log\"]}"),
                new MemoryStream(),
                null);

            Assert.True(HostBridge.Handshaken);
            Assert.Equal(DatabaseDialect.Unknown, HostBridge.DatabaseDialect);
            Assert.Equal(DatabaseDialect.Unknown, Exo.Database.Dialect);
        }
        finally
        {
            HostBridge.UseTransport(null);
        }
    }

    [Fact]
    public void Host_hello_with_unrecognized_dialect_keeps_Unknown_without_failing_handshake()
    {
        var output = new MemoryStream();

        try
        {
            PluginHost.RunInstance(
                new HandshakeProbe(),
                Lines(
                    "{\"type\":\"hello\",\"protocol\":1,\"host\":\"exoforge\",\"capabilities\":[\"action_result\",\"host_call\",\"host_log\"],\"dialect\":\"oracle\"}",
                    "{\"type\":\"action\",\"id\":1,\"action\":\"ping\",\"payload\":{}}"),
                output,
                null);

            Assert.True(HostBridge.Handshaken);
            Assert.Equal(DatabaseDialect.Unknown, HostBridge.DatabaseDialect);
            Assert.Equal(DatabaseDialect.Unknown, Exo.Database.Dialect);

            string written = Encoding.UTF8.GetString(output.ToArray());
            Assert.Contains("\"type\":\"hello\"", written);
            Assert.Contains("\"status\":\"ok\",\"data\":42", written);
        }
        finally
        {
            HostBridge.UseTransport(null);
        }
    }

    [Fact]
    public void Starting_a_new_session_without_dialect_resets_Exo_Database_Dialect_to_Unknown()
    {
        try
        {
            PluginHost.RunInstance(
                new HandshakeProbe(),
                Lines("{\"type\":\"hello\",\"protocol\":1,\"host\":\"exoforge\",\"capabilities\":[\"action_result\",\"host_call\",\"host_log\"],\"dialect\":\"postgres\"}"),
                new MemoryStream(),
                null);

            Assert.Equal(DatabaseDialect.Postgres, HostBridge.DatabaseDialect);
            Assert.Equal(DatabaseDialect.Postgres, Exo.Database.Dialect);

            PluginHost.RunInstance(
                new HandshakeProbe(),
                Lines("{\"type\":\"hello\",\"protocol\":1,\"host\":\"exoforge\",\"capabilities\":[\"action_result\",\"host_call\",\"host_log\"]}"),
                new MemoryStream(),
                null);

            Assert.Equal(DatabaseDialect.Unknown, HostBridge.DatabaseDialect);
            Assert.Equal(DatabaseDialect.Unknown, Exo.Database.Dialect);
        }
        finally
        {
            HostBridge.UseTransport(null);
        }
    }

    [Fact]
    public void InMemoryDatabase_exposes_its_own_Dialect_in_test_host()
    {
        using var test = ExoTestHost.Start("dialect_test");

        Assert.Equal(DatabaseDialect.Unknown, Exo.Database.Dialect);

        test.Database.Dialect = DatabaseDialect.Sqlite;
        Assert.Equal(DatabaseDialect.Sqlite, Exo.Database.Dialect);
    }

    private static StringReader Lines(params string[] lines) =>
        new(string.Join("\n", lines) + "\n");
}
