using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Exoforge.Plugin.SDK;
using Xunit;

namespace Exoforge.Plugin.SDK.Tests;

[ExoService("concurrent_host_calls", Version = "1.0.0")]
public class ConcurrentHostCallPlugin
{
    public IActionDispatcher? Actions { get; set; }

    public int EventsHandled { get; private set; }

    public void OnEvent(string name) => EventsHandled++;

    /// <summary>
    /// Fires every call before awaiting any. The host answers them in reverse id order, and the
    /// check inside is against the reply to each call's own request.
    /// </summary>
    [ExoAction("fan_out", Mode = ActionMode.Async)]
    public async Task<int> FanOut(int count)
    {
        var calls = new List<Task<int>>();

        for (int i = 0; i < count; i++)
        {
            calls.Add(Actions!.CallActionAsync<int>("dependency", "ping", new { n = i }));
        }

        int[] results = await Task.WhenAll(calls);

        // A reply routed to the wrong caller shows up here as a value that is not its own.
        for (int i = 0; i < results.Length; i++)
        {
            if (results[i] != i * 10)
            {
                return -1;
            }
        }

        return results.Sum(value => value / 10);
    }

    [ExoAction("one_call", Mode = ActionMode.Sync)]
    public int OneCall() => Actions!.CallAction<int>("dependency", "ping", new { });

    /// <summary>
    /// An async action that awaits one call and then blocks on a second: the sync wrapper must work
    /// on a continuation thread, which is where deadlock would surface.
    /// </summary>
    [ExoAction("mixed", Mode = ActionMode.Async)]
    public async Task<int> Mixed()
    {
        int first = await Actions!.CallActionAsync<int>("dependency", "ping", new { n = 1 });
        int second = Actions.CallAction<int>("dependency", "ping", new { n = 2 });
        return first + second;
    }
}

/// <summary>
/// A host that answers while the plugin is still running: stdin is a queue the test pushes into
/// (closing it is EOF), stdout is a queue the test reads lines from.
/// </summary>
internal sealed class HostSimulator : TextReader
{
    private readonly BlockingCollection<string?> _frames = new();
    private readonly HostOutput _output = new();

    public Stream Output => _output;

    public void Send(string frame) => _frames.Add(frame);

    public void CloseInput() => _frames.CompleteAdding();

    public override string? ReadLine()
    {
        try
        {
            return _frames.Take();
        }
        catch (InvalidOperationException)
        {
            return null; // completed and empty: EOF
        }
    }

    public string? ReadFrame(Func<JsonElement, bool> match, TimeSpan timeout)
    {
        DateTime deadline = DateTime.UtcNow + timeout;

        while (true)
        {
            TimeSpan remaining = deadline - DateTime.UtcNow;
            if (remaining <= TimeSpan.Zero) return null;

            string? line = _output.ReadLine(remaining);
            if (line is null) return null;

            using var doc = JsonDocument.Parse(line);
            if (match(doc.RootElement)) return line;
        }
    }

    public string? ReadFrame(string type, TimeSpan timeout) =>
        ReadFrame(root => root.TryGetProperty("type", out var t) && t.GetString() == type, timeout);

    private sealed class HostOutput : Stream
    {
        private readonly object _gate = new();
        private readonly StringBuilder _pending = new();
        private readonly Queue<string> _lines = new();
        private bool _closed;

        public override bool CanRead => false;
        public override bool CanSeek => false;
        public override bool CanWrite => true;
        public override long Length => throw new NotSupportedException();
        public override long Position { get => throw new NotSupportedException(); set => throw new NotSupportedException(); }

        public override void Write(byte[] buffer, int offset, int count)
        {
            lock (_gate)
            {
                _pending.Append(Encoding.UTF8.GetString(buffer, offset, count));

                while (true)
                {
                    string text = _pending.ToString();
                    int newline = text.IndexOf('\n');
                    if (newline < 0) break;

                    _lines.Enqueue(text.Substring(0, newline));
                    _pending.Clear().Append(text.Substring(newline + 1));
                }

                Monitor.PulseAll(_gate);
            }
        }

        public string? ReadLine(TimeSpan timeout)
        {
            DateTime deadline = DateTime.UtcNow + timeout;

            lock (_gate)
            {
                while (_lines.Count == 0)
                {
                    TimeSpan remaining = deadline - DateTime.UtcNow;
                    if (_closed || remaining <= TimeSpan.Zero) return null;
                    Monitor.Wait(_gate, remaining);
                }

                return _lines.Dequeue();
            }
        }

        public override void Close()
        {
            lock (_gate)
            {
                _closed = true;
                Monitor.PulseAll(_gate);
            }
        }

        public override void Flush() { }
        public override int Read(byte[] buffer, int offset, int count) => throw new NotSupportedException();
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
    }
}

/// <summary>
/// A host call is multiplexed: the id is taken atomically, the reply is routed by the reader, and
/// any number of calls can be in flight. A plugin that fires fifty of them at once must get fifty
/// answers, each to its own request, whatever order the host sends them in.
/// </summary>
public class ConcurrentHostCallTests
{
    private const string Hello =
        "{\"type\":\"hello\",\"protocol\":1,\"host\":\"exoforge\",\"capabilities\":[\"action_result\",\"host_call\",\"host_log\"]}";

    [Fact]
    public async Task Fifty_calls_in_flight_each_get_the_reply_to_their_own_request_answered_out_of_order()
    {
        var plugin = new ConcurrentHostCallPlugin();
        using var host = new HostSimulator();

        host.Send(Hello);
        host.Send("{\"type\":\"action\",\"id\":1,\"action\":\"fan_out\",\"payload\":{\"count\":50}}");

        var run = Task.Run(() => PluginHost.RunInstance(plugin, host, host.Output, null));

        var calls = new List<(long Id, int N)>();
        string? actionResult = null;

        // Collect host calls without answering: a transport that serialised them could never
        // reach the fiftieth.
        while (actionResult is null)
        {
            string? line = host.ReadFrame(_ => true, TimeSpan.FromSeconds(10));
            Assert.NotNull(line);

            using var frame = JsonDocument.Parse(line!);
            var root = frame.RootElement;

            switch (root.GetProperty("type").GetString())
            {
                case "action_result":
                    actionResult = line;
                    break;

                case "host_call":
                    calls.Add((root.GetProperty("id").GetInt64(),
                               root.GetProperty("args").GetProperty("payload").GetProperty("n").GetInt32()));

                    if (calls.Count == 50)
                    {
                        foreach (var call in Enumerable.Reverse(calls))
                        {
                            host.Send($"{{\"type\":\"host_call_result\",\"id\":{call.Id},\"result\":{call.N * 10}}}");
                        }
                    }

                    break;
            }
        }

        Assert.Equal(50, calls.Count);

        host.CloseInput();
        await run.WaitAsync(TimeSpan.FromSeconds(10));

        using var doc = JsonDocument.Parse(actionResult!);
        Assert.Equal("ok", doc.RootElement.GetProperty("status").GetString());

        // FanOut returns the sum of the request numbers, and -1 if any caller saw a reply that
        // was not its own.
        Assert.Equal(1225, doc.RootElement.GetProperty("data").GetInt32());
    }

    [Fact]
    public async Task An_event_arriving_while_a_host_call_is_pending_runs_after_the_action()
    {
        var plugin = new ConcurrentHostCallPlugin();
        using var host = new HostSimulator();

        host.Send(Hello);
        host.Send("{\"type\":\"action\",\"id\":1,\"action\":\"one_call\",\"payload\":{}}");

        var run = Task.Run(() => PluginHost.RunInstance(plugin, host, host.Output, null));

        string? call = host.ReadFrame("host_call", TimeSpan.FromSeconds(10));
        Assert.NotNull(call);

        // The plugin is blocked on the call; an event must still wait its turn behind the action.
        host.Send("{\"type\":\"event\",\"event\":\"pinged\",\"payload\":{}}");

        using (var doc = JsonDocument.Parse(call!))
        {
            host.Send($"{{\"type\":\"host_call_result\",\"id\":{doc.RootElement.GetProperty("id").GetInt64()},\"result\":42}}");
        }

        string? result = host.ReadFrame("action_result", TimeSpan.FromSeconds(10));
        Assert.NotNull(result);

        using (var doc = JsonDocument.Parse(result!))
        {
            Assert.Equal("ok", doc.RootElement.GetProperty("status").GetString());
            Assert.Equal(42, doc.RootElement.GetProperty("data").GetInt32());
        }

        host.CloseInput();
        await run.WaitAsync(TimeSpan.FromSeconds(10));

        Assert.Equal(1, plugin.EventsHandled);
    }

    [Fact]
    public async Task An_unanswered_host_call_times_out()
    {
        TimeSpan previous = PluginHost.HostCallTimeout;
        PluginHost.HostCallTimeout = TimeSpan.FromMilliseconds(150);

        try
        {
            var plugin = new ConcurrentHostCallPlugin();
            using var host = new HostSimulator();

            host.Send(Hello);
            host.Send("{\"type\":\"action\",\"id\":1,\"action\":\"one_call\",\"payload\":{}}");

            var run = Task.Run(() => PluginHost.RunInstance(plugin, host, host.Output, null));

            Assert.NotNull(host.ReadFrame("host_call", TimeSpan.FromSeconds(10)));
            Assert.NotNull(host.ReadFrame("host_log", TimeSpan.FromSeconds(10)));

            string? result = host.ReadFrame("action_result", TimeSpan.FromSeconds(10));
            Assert.NotNull(result);

            using var doc = JsonDocument.Parse(result!);
            Assert.Equal("error", doc.RootElement.GetProperty("status").GetString());

            var error = doc.RootElement.GetProperty("error");
            Assert.Equal("timeout", error.GetProperty("code").GetString());
            Assert.Contains("within 150 ms", error.GetProperty("message").GetString());

            host.CloseInput();
            await run.WaitAsync(TimeSpan.FromSeconds(10));
        }
        finally
        {
            PluginHost.HostCallTimeout = previous;
        }
    }

    [Fact]
    public async Task The_host_closing_stdin_fails_a_pending_call_instead_of_hanging()
    {
        var plugin = new ConcurrentHostCallPlugin();
        using var host = new HostSimulator();

        host.Send(Hello);
        host.Send("{\"type\":\"action\",\"id\":1,\"action\":\"one_call\",\"payload\":{}}");

        var run = Task.Run(() => PluginHost.RunInstance(plugin, host, host.Output, null));

        // Close stdin while the call is in flight, with no reply ever sent.
        Assert.NotNull(host.ReadFrame("host_call", TimeSpan.FromSeconds(10)));
        host.CloseInput();

        string? result = host.ReadFrame("action_result", TimeSpan.FromSeconds(10));
        Assert.NotNull(result);

        using var doc = JsonDocument.Parse(result!);
        Assert.Equal("error", doc.RootElement.GetProperty("status").GetString());

        var error = doc.RootElement.GetProperty("error");
        Assert.Equal("invalid_operation", error.GetProperty("code").GetString());
        Assert.Contains("closed stdin", error.GetProperty("message").GetString());

        await run.WaitAsync(TimeSpan.FromSeconds(10));
    }

    [Fact]
    public async Task A_sync_host_call_from_an_async_action_still_completes()
    {
        var plugin = new ConcurrentHostCallPlugin();
        using var host = new HostSimulator();

        host.Send(Hello);
        host.Send("{\"type\":\"action\",\"id\":1,\"action\":\"mixed\",\"payload\":{}}");

        var run = Task.Run(() => PluginHost.RunInstance(plugin, host, host.Output, null));

        // Answer each call as it arrives: the second one comes from the action's continuation
        // thread, blocked in the sync wrapper while the reader is what has to complete it.
        string? actionResult = null;

        while (actionResult is null)
        {
            string? line = host.ReadFrame(_ => true, TimeSpan.FromSeconds(10));
            Assert.NotNull(line);

            using var frame = JsonDocument.Parse(line!);
            var root = frame.RootElement;

            switch (root.GetProperty("type").GetString())
            {
                case "action_result":
                    actionResult = line;
                    break;

                case "host_call":
                    int n = root.GetProperty("args").GetProperty("payload").GetProperty("n").GetInt32();
                    host.Send($"{{\"type\":\"host_call_result\",\"id\":{root.GetProperty("id").GetInt64()},\"result\":{n * 10}}}");
                    break;
            }
        }

        host.CloseInput();
        await run.WaitAsync(TimeSpan.FromSeconds(10));

        using var doc = JsonDocument.Parse(actionResult!);
        Assert.Equal("ok", doc.RootElement.GetProperty("status").GetString());
        Assert.Equal(30, doc.RootElement.GetProperty("data").GetInt32());
    }
}
