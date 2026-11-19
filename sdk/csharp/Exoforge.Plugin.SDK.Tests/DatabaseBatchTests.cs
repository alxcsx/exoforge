using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using Xunit;

namespace Exoforge.Plugin.SDK.Tests;

public class DatabaseBatchTests
{
    private sealed class BatchCaptureTransport : IPluginTransport
    {
        public int DbBatchCalls { get; private set; }
        public int DbPutCalls { get; private set; }
        public int DbDeleteCalls { get; private set; }
        public int CallActionCalls { get; private set; }
        public string? LastOperationsJson { get; private set; }
        public Func<string, bool>? OnDbBatch { get; set; }

        public bool EmitEvent(string topic, string evt, string payloadJson) => true;

        public string? CallAction(string service, string action, string payloadJson)
        {
            CallActionCalls++;
            return null;
        }

        public void Log(int level, string message) { }
        public string? DbGet(string table, string key) => null;
        public string? DbAll(string table) => null;
        public bool DbPut(string table, string key, string valueJson) { DbPutCalls++; return true; }
        public bool DbDelete(string table, string key) { DbDeleteCalls++; return true; }
        public long ClockNow() => 0;

        public bool DbBatch(string operationsJson)
        {
            DbBatchCalls++;
            LastOperationsJson = operationsJson;
            return OnDbBatch != null ? OnDbBatch(operationsJson) : true;
        }
    }

    [ExoService("batch_probe", Version = "1.0.0")]
    private sealed class BatchProbePlugin
    {
        [ExoAction("run_batch", Mode = ActionMode.Sync)]
        public string RunBatch()
        {
            Exo.Database.Transaction(tx =>
            {
                tx.Put("scores", "p1", new TestScore { PlayerId = "p1", Score = 100 });
                tx.ExecuteSql($"UPDATE custom_scores SET score = {200} WHERE player_id = {"p1"}");
                tx.Delete("scores", "p2");
            });
            return "committed";
        }
    }

    [Fact]
    public void Transaction_OnlyRecordsInsideLambda_AndSendsOneDbBatchHostCall()
    {
        var transport = new BatchCaptureTransport();
        HostBridge.UseTransport(transport);

        try
        {
            var db = new HostDatabase("batch_ext");

            db.Transaction(tx =>
            {
                tx.Put("scores", "p1", new TestScore { PlayerId = "p1", Score = 100 });
                tx.Put(new TestScore { PlayerId = "p2", Score = 250 });
                tx.Execute("UPDATE custom_scores SET score = $1 WHERE player_id = $2", 150, "p1");
                tx.ExecuteSql($"UPDATE custom_scores SET score = {300} WHERE player_id = {"p2"}");
                tx.Delete("scores", "stale");
                tx.Delete<TestScore>("p3");

                // While the callback is still executing, nothing has been sent to the transport yet.
                Assert.Equal(0, transport.DbBatchCalls);
                Assert.Equal(0, transport.DbPutCalls);
                Assert.Equal(0, transport.DbDeleteCalls);
                Assert.Equal(0, transport.CallActionCalls);
            });

            Assert.Equal(1, transport.DbBatchCalls);
            Assert.Equal(0, transport.DbPutCalls);
            Assert.Equal(0, transport.DbDeleteCalls);
            Assert.Equal(0, transport.CallActionCalls);
            Assert.NotNull(transport.LastOperationsJson);

            using var doc = JsonDocument.Parse(transport.LastOperationsJson!);
            var ops = doc.RootElement;
            Assert.Equal(JsonValueKind.Array, ops.ValueKind);
            Assert.Equal(6, ops.GetArrayLength());

            Assert.Equal("put", ops[0].GetProperty("action").GetString());
            Assert.Equal("scores", ops[0].GetProperty("table").GetString());
            Assert.Equal("p1", ops[0].GetProperty("key").GetString());
            Assert.Equal(100, ops[0].GetProperty("value").GetProperty("score").GetInt32());

            Assert.Equal("put", ops[1].GetProperty("action").GetString());
            Assert.Equal("custom_scores", ops[1].GetProperty("table").GetString());
            Assert.Equal("p2", ops[1].GetProperty("key").GetString());
            Assert.Equal(250, ops[1].GetProperty("value").GetProperty("score").GetInt32());

            Assert.Equal("execute", ops[2].GetProperty("action").GetString());
            Assert.Equal("UPDATE custom_scores SET score = $1 WHERE player_id = $2", ops[2].GetProperty("sql").GetString());
            Assert.Equal(150, ops[2].GetProperty("args")[0].GetInt32());
            Assert.Equal("p1", ops[2].GetProperty("args")[1].GetString());

            Assert.Equal("execute", ops[3].GetProperty("action").GetString());
            Assert.Equal("UPDATE custom_scores SET score = $1 WHERE player_id = $2", ops[3].GetProperty("sql").GetString());
            Assert.Equal(300, ops[3].GetProperty("args")[0].GetInt32());
            Assert.Equal("p2", ops[3].GetProperty("args")[1].GetString());

            Assert.Equal("delete", ops[4].GetProperty("action").GetString());
            Assert.Equal("scores", ops[4].GetProperty("table").GetString());
            Assert.Equal("stale", ops[4].GetProperty("key").GetString());

            Assert.Equal("delete", ops[5].GetProperty("action").GetString());
            Assert.Equal("custom_scores", ops[5].GetProperty("table").GetString());
            Assert.Equal("p3", ops[5].GetProperty("key").GetString());
        }
        finally
        {
            HostBridge.UseTransport(null);
        }
    }

    [Fact]
    public void ExecuteBatch_WithFormattableStrings_ParameterizesAndSendsOneDbBatchCall()
    {
        var transport = new BatchCaptureTransport();
        HostBridge.UseTransport(transport);

        try
        {
            var db = new HostDatabase("batch_ext");
            string evil = "p1'; DROP TABLE scores; --";
            int amount = 75;

            db.ExecuteBatch(new FormattableString[]
            {
                $"INSERT INTO scores (player_id, score) VALUES ({evil}, {amount})",
                $"DELETE FROM lobby WHERE player_id = {evil}"
            });

            Assert.Equal(1, transport.DbBatchCalls);
            Assert.NotNull(transport.LastOperationsJson);

            using var doc = JsonDocument.Parse(transport.LastOperationsJson!);
            var ops = doc.RootElement;
            Assert.Equal(2, ops.GetArrayLength());

            Assert.Equal("execute", ops[0].GetProperty("action").GetString());
            Assert.Equal("INSERT INTO scores (player_id, score) VALUES ($1, $2)", ops[0].GetProperty("sql").GetString());
            Assert.DoesNotContain("DROP TABLE", ops[0].GetProperty("sql").GetString());
            Assert.Equal(evil, ops[0].GetProperty("args")[0].GetString());
            Assert.Equal(75, ops[0].GetProperty("args")[1].GetInt32());

            Assert.Equal("execute", ops[1].GetProperty("action").GetString());
            Assert.Equal("DELETE FROM lobby WHERE player_id = $1", ops[1].GetProperty("sql").GetString());
            Assert.Equal(evil, ops[1].GetProperty("args")[0].GetString());
        }
        finally
        {
            HostBridge.UseTransport(null);
        }
    }

    [Fact]
    public void ExecuteBatch_WithTuplesAndDbBatchOperations_SendsOneDbBatchCall()
    {
        var transport = new BatchCaptureTransport();
        HostBridge.UseTransport(transport);

        try
        {
            var db = new HostDatabase("batch_ext");

            db.ExecuteBatch(new (string Sql, object?[]? Args)[]
            {
                ("INSERT INTO t VALUES ($1)", new object?[] { "a" }),
                ("DELETE FROM t WHERE id = $1", new object?[] { "b" })
            });

            Assert.Equal(1, transport.DbBatchCalls);

            db.ExecuteBatch(new[]
            {
                DbBatchOperation.Put("items", "i1", new TestItem { Id = "i1", Name = "Sword" }),
                DbBatchOperation.ExecuteSql($"UPDATE items SET name = {"Shield"} WHERE id = {"i1"}"),
                DbBatchOperation.Delete("items", "i2")
            });

            Assert.Equal(2, transport.DbBatchCalls);
        }
        finally
        {
            HostBridge.UseTransport(null);
        }
    }

    [Fact]
    public void Transaction_WhenCallbackThrows_DoesNotSendDbBatchHostCall()
    {
        var transport = new BatchCaptureTransport();
        HostBridge.UseTransport(transport);

        try
        {
            var db = new HostDatabase("batch_ext");

            Assert.Throws<InvalidOperationException>(() =>
            {
                db.Transaction(tx =>
                {
                    tx.Put("scores", "p1", new TestScore { PlayerId = "p1", Score = 10 });
                    throw new InvalidOperationException("aborted before commit");
                });
            });

            Assert.Equal(0, transport.DbBatchCalls);
        }
        finally
        {
            HostBridge.UseTransport(null);
        }
    }

    [Fact]
    public async Task NativeTransport_DbBatch_PropagatesStructuredErrorWithFailingIndex()
    {
        const string hello =
            "{\"type\":\"hello\",\"protocol\":1,\"host\":\"exoforge\",\"capabilities\":[\"action_result\",\"host_call\",\"host_log\"]}";

        var plugin = new BatchProbePlugin();
        using var host = new HostSimulator();

        host.Send(hello);
        host.Send("{\"type\":\"action\",\"id\":7,\"action\":\"run_batch\",\"payload\":{}}");

        var run = Task.Run(() => PluginHost.RunInstance(plugin, host, host.Output, null));

        string? call = host.ReadFrame("host_call", TimeSpan.FromSeconds(10));
        Assert.NotNull(call);

        using (var callDoc = JsonDocument.Parse(call!))
        {
            var root = callDoc.RootElement;
            Assert.Equal("db_batch", root.GetProperty("op").GetString());
            var ops = root.GetProperty("args").GetProperty("operations");
            Assert.Equal(3, ops.GetArrayLength());

            long callId = root.GetProperty("id").GetInt64();
            host.Send(
                $"{{\"type\":\"host_call_result\",\"id\":{callId},\"result\":{{\"ok\":false,\"index\":1,\"error\":{{\"code\":\"postgres_error\",\"index\":1,\"message\":\"check constraint violated\"}}}}}}");
        }

        string? actionResult = host.ReadFrame("action_result", TimeSpan.FromSeconds(10));
        Assert.NotNull(actionResult);

        host.CloseInput();
        await run.WaitAsync(TimeSpan.FromSeconds(10));

        using var resultDoc = JsonDocument.Parse(actionResult!);
        Assert.Equal("error", resultDoc.RootElement.GetProperty("status").GetString());
        string message = resultDoc.RootElement.GetProperty("error").GetProperty("message").GetString()!;
        Assert.Contains("index 1", message);
        Assert.Contains("check constraint violated", message);
    }

    [Fact]
    public void ExoDatabaseException_ThrowIfError_ParsesFailedIndexFromStructuredError()
    {
        var ex = Assert.Throws<ExoDatabaseException>(() =>
            ExoDatabaseException.ThrowIfError(
                "batch",
                "{\"ok\":false,\"index\":2,\"error\":{\"code\":\"postgres_error\",\"index\":2,\"message\":\"duplicate key\"}}"));

        Assert.Equal("batch", ex.Table);
        Assert.Equal(2, ex.FailedIndex);
        Assert.Equal(2, ex.Index);
        Assert.Contains("index 2", ex.Message);
        Assert.Contains("duplicate key", ex.ServerError);
    }

    [Fact]
    public void InMemoryDatabase_Transaction_AppliesWritesAtomicallyAndRollsBackOnException()
    {
        using var test = ExoTestHost.Start("batch_mem");

        Exo.Database.Transaction(tx =>
        {
            tx.Put("scores", "p1", new TestScore { PlayerId = "p1", Score = 100 });
            tx.Put(new TestScore { PlayerId = "p2", Score = 200 });
        });

        Assert.Equal(100, test.Database.Get<TestScore>("scores", "p1")?.Score);
        Assert.Equal(200, test.Database.Get<TestScore>("custom_scores", "p2")?.Score);

        Assert.Throws<InvalidOperationException>(() =>
        {
            Exo.Database.Transaction(tx =>
            {
                tx.Delete("scores", "p1");
                tx.Put("scores", "p3", new TestScore { PlayerId = "p3", Score = 300 });
                throw new InvalidOperationException("boom");
            });
        });

        // p1 is still intact and p3 was never written
        Assert.Equal(100, test.Database.Get<TestScore>("scores", "p1")?.Score);
        Assert.Null(test.Database.Get<TestScore>("scores", "p3"));
    }

    [Fact]
    public void ITransaction_IsWriteOnly_AndExposesNoReadMethods()
    {
        var methods = typeof(ITransaction).GetMethods(BindingFlags.Public | BindingFlags.Instance);
        Assert.DoesNotContain(methods, m => m.Name.StartsWith("Get", StringComparison.OrdinalIgnoreCase));
        Assert.DoesNotContain(methods, m => m.Name.StartsWith("All", StringComparison.OrdinalIgnoreCase));
        Assert.DoesNotContain(methods, m => m.Name.StartsWith("First", StringComparison.OrdinalIgnoreCase));
        Assert.DoesNotContain(methods, m => m.Name.StartsWith("Query", StringComparison.OrdinalIgnoreCase));
    }
}
