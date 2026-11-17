using System.IO;
using Exoforge.Plugin.SDK;
using Xunit;

namespace Exoforge.Plugin.SDK.Tests;

[ExoService("frame_loop", Version = "1.0.0")]
public class FrameLoopPlugin
{
    public int Dispatched { get; private set; }

    public string? HostResult { get; private set; }

    public int EventsHandled { get; private set; }

    public string? EventHostResult { get; private set; }

    /// <summary>An event handler that itself asks the host a question: the re-entrancy the loop must avoid.</summary>
    public void OnEvent(string name, System.Text.Json.JsonElement payload)
    {
        EventsHandled++;
        EventHostResult = HostBridge.DbGet("events", name);
    }

    [ExoAction("count", Mode = ActionMode.Sync)]
    public int Count()
    {
        Dispatched++;
        return Dispatched;
    }

    [ExoAction("with_host_call", Mode = ActionMode.Sync)]
    public string WithHostCall()
    {
        Dispatched++;
        HostResult = HostBridge.DbGet("t", "k");
        return HostResult ?? "null";
    }

    [ExoAction("with_host_call_and_event", Mode = ActionMode.Sync)]
    public string WithHostCallAndEvent()
    {
        Dispatched++;
        HostResult = HostBridge.DbGet("t", "k");
        return HostResult ?? "null";
    }

    [ExoAction("fail_with_action_exception", Mode = ActionMode.Sync)]
    public void FailWithActionException() =>
        throw new ExoActionException("insufficient_funds", "You need 10 coins");

    [ExoAction("fail_with_invalid_operation", Mode = ActionMode.Sync)]
    public void FailWithInvalidOperation() =>
        throw new System.InvalidOperationException("Bad state reached");

    [ExoAction("trigger_db_error", Mode = ActionMode.Sync)]
    public void TriggerDbError()
    {
        HostBridge.DbGet("missing_table", "k");
    }
}

/// <summary>
/// The frame loop reads stdin through one reader for the whole process.
///
/// It used to open a second one per host call. Two readers over one stdin each buffer ahead, so a
/// host call could not see a reply the loop had already buffered, and everything the host call's
/// reader buffered past its own line was discarded when it was disposed — the next action frame.
/// </summary>
public class FrameLoopTests
{
    [Fact]
    public void A_host_call_sees_its_reply_and_the_next_frame_still_runs()
    {
        var plugin = new FrameLoopPlugin();

        // Back to back, the way they arrive when the host writes more than one frame in one go.
        var input = new StringReader(string.Join("\n", new[]
        {
            "{\"type\":\"action\",\"id\":1,\"action\":\"with_host_call\",\"payload\":{}}",
            "{\"type\":\"host_call_result\",\"id\":1,\"result\":{\"v\":1}}",
            "{\"type\":\"action\",\"id\":2,\"action\":\"count\",\"payload\":{}}",
            ""
        }));

        PluginHost.RunInstance(plugin, input);

        Assert.Equal("{\"v\":1}", plugin.HostResult);
        Assert.Equal(2, plugin.Dispatched);
    }

    [Fact]
    public void An_action_arriving_during_a_host_call_is_replayed_not_dropped()
    {
        var plugin = new FrameLoopPlugin();

        // The second action frame arrives while the first is blocked inside its host call: the
        // host call's read loop must buffer it for the main loop, not swallow it (M33 Fix 6).
        var input = new StringReader(string.Join("\n", new[]
        {
            "{\"type\":\"action\",\"id\":1,\"action\":\"with_host_call\",\"payload\":{}}",
            "{\"type\":\"action\",\"id\":2,\"action\":\"count\",\"payload\":{}}",
            "{\"type\":\"host_call_result\",\"id\":1,\"result\":{\"v\":1}}",
            ""
        }));

        PluginHost.RunInstance(plugin, input);

        Assert.Equal(2, plugin.Dispatched);
        Assert.Equal("{\"v\":1}", plugin.HostResult);
    }

    /// <summary>
    /// A [ExoWebhook] handler's parameter is the whole frame the router sends (body, raw_body,
    /// json, headers, method, query); binding it by parameter name produced null.
    /// </summary>
    [Fact]
    public void A_webhook_payload_parameter_binds_the_whole_frame()
    {
        using var doc = System.Text.Json.JsonDocument.Parse(
            "{\"body\":\"raw_data\",\"raw_body\":\"raw_data\",\"json\":{\"id\":\"evt_1\"}," +
            "\"headers\":{\"sig\":\"xyz\"},\"method\":\"POST\",\"query\":{\"tenant\":\"acme\"}}");

        var payload = ExoDispatch.Get<WebhookPayload>(doc.RootElement, "payload", null!);

        Assert.NotNull(payload);
        Assert.Equal("raw_data", payload!.Body);
        Assert.Equal("raw_data", payload.RawBody);
        Assert.Equal("POST", payload.Method);
        Assert.Equal("xyz", payload.Headers!["sig"]);
        Assert.Equal("acme", payload.Query!["tenant"]);
        Assert.Equal("evt_1", payload.Json.GetProperty("id").GetString());
    }

    [Fact]
    public void An_event_arriving_during_a_host_call_is_handled_after_the_call_completes()
    {
        var plugin = new FrameLoopPlugin();

        // The event is delivered while the action is blocked on its host call. Dispatching it inline
        // re-entered OnEvent, whose own host call consumed (and dropped) the outer reply. It must
        // instead run after the action returns, and its own host call must still be answered.
        var input = new StringReader(string.Join("\n", new[]
        {
            "{\"type\":\"action\",\"id\":1,\"action\":\"with_host_call_and_event\",\"payload\":{}}",
            "{\"type\":\"event\",\"event\":\"score_updated\",\"payload\":{\"value\":7}}",
            "{\"type\":\"host_call_result\",\"id\":1,\"result\":{\"outer\":true}}",
            "{\"type\":\"host_call_result\",\"id\":2,\"result\":{\"event\":true}}",
            ""
        }));

        PluginHost.RunInstance(plugin, input);

        Assert.Equal("{\"outer\":true}", plugin.HostResult);
        Assert.Equal(1, plugin.EventsHandled);
        Assert.Equal("{\"event\":true}", plugin.EventHostResult);
    }

    [Fact]
    public void An_action_throwing_ExoActionException_returns_structured_code_and_message()
    {
        var plugin = new FrameLoopPlugin();
        var output = new MemoryStream();
        var input = new StringReader("{\"type\":\"action\",\"id\":42,\"action\":\"fail_with_action_exception\",\"payload\":{}}\n");

        PluginHost.RunInstance(plugin, input, output, null);

        string written = System.Text.Encoding.UTF8.GetString(output.ToArray());
        Assert.Contains("\"type\":\"action_result\"", written);
        Assert.Contains("\"id\":42", written);
        Assert.Contains("\"status\":\"error\"", written);
        Assert.Contains("\"code\":\"insufficient_funds\"", written);
        Assert.Contains("\"message\":\"You need 10 coins\"", written);
    }

    [Fact]
    public void An_action_throwing_standard_exception_is_wrapped_into_normalized_code_and_message()
    {
        var plugin = new FrameLoopPlugin();
        var output = new MemoryStream();
        var input = new StringReader("{\"type\":\"action\",\"id\":43,\"action\":\"fail_with_invalid_operation\",\"payload\":{}}\n");

        PluginHost.RunInstance(plugin, input, output, null);

        string written = System.Text.Encoding.UTF8.GetString(output.ToArray());
        Assert.Contains("\"type\":\"action_result\"", written);
        Assert.Contains("\"id\":43", written);
        Assert.Contains("\"status\":\"error\"", written);
        Assert.Contains("\"code\":\"invalid_operation\"", written);
        Assert.Contains("\"message\":\"Bad state reached\"", written);
    }

    [Fact]
    public void An_action_triggering_database_error_throws_and_reports_error()
    {
        var plugin = new FrameLoopPlugin();
        var output = new MemoryStream();
        var input = new StringReader(string.Join("\n", new[]
        {
            "{\"type\":\"action\",\"id\":44,\"action\":\"trigger_db_error\",\"payload\":{}}",
            "{\"type\":\"host_call_result\",\"id\":1,\"result\":{\"ok\":false,\"error\":\"table missing\"}}",
            ""
        }));

        PluginHost.RunInstance(plugin, input, output, null);

        string written = System.Text.Encoding.UTF8.GetString(output.ToArray());
        Assert.Contains("\"type\":\"action_result\"", written);
        Assert.Contains("\"id\":44", written);
        Assert.Contains("\"status\":\"error\"", written);
    }

    [Fact]
    public void An_action_triggering_database_error_with_non_string_error_reports_error()
    {
        var plugin = new FrameLoopPlugin();
        var output = new MemoryStream();
        var input = new StringReader(string.Join("\n", new[]
        {
            "{\"type\":\"action\",\"id\":45,\"action\":\"trigger_db_error\",\"payload\":{}}",
            "{\"type\":\"host_call_result\",\"id\":1,\"result\":{\"ok\":false,\"error\":{\"code\":\"missing_table\",\"id\":42}}}",
            ""
        }));

        PluginHost.RunInstance(plugin, input, output, null);

        string written = System.Text.Encoding.UTF8.GetString(output.ToArray());
        Assert.Contains("\"type\":\"action_result\"", written);
        Assert.Contains("\"id\":45", written);
        Assert.Contains("\"status\":\"error\"", written);
    }
}
