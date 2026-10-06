using System;
using System.Collections.Concurrent;
using System.Net;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace Exoforge.Client.Tests;

/// <summary>
/// A minimal WebSocket server for transport tests.
///
/// <see cref="ExoClient"/> and <see cref="ExoTransport"/> are Unity-free, so reconnect, timeout and
/// error-surfacing behaviour belongs here rather than in the integration tests — which need a live
/// cluster and therefore skip in CI.
///
/// The server is deliberately dumb: it accepts one connection, records what the client sends, lets
/// the test push frames, and can drop the connection on demand. Nothing about the Exoforge protocol
/// is implemented — that is the point, so a test can say exactly what the client receives.
/// </summary>
internal sealed class StubWebSocketServer : IAsyncDisposable
{
    private readonly HttpListener _listener = new();
    private readonly CancellationTokenSource _cts = new();
    private readonly ConcurrentQueue<string> _received = new();
    private readonly SemaphoreSlim _receivedSignal = new(0);
    private readonly Task _acceptLoop;

    private WebSocket? _socket;
    private int _connectionCount;

    private StubWebSocketServer(int port)
    {
        Uri = new Uri($"ws://127.0.0.1:{port}/ws");
        _listener.Prefixes.Add($"http://127.0.0.1:{port}/");
        _listener.Start();
        _acceptLoop = Task.Run(() => AcceptLoopAsync(_cts.Token));
    }

    /// <summary>The endpoint a client should connect to.</summary>
    public Uri Uri { get; }

    /// <summary>How many connections have been accepted — a second one means a reconnect happened.</summary>
    public int ConnectionCount => Volatile.Read(ref _connectionCount);

    /// <summary>True while a client is connected.</summary>
    public bool HasClient => _socket?.State == WebSocketState.Open;

    /// <summary>Starts a server on a free loopback port.</summary>
    public static StubWebSocketServer Start() => new(FreePort());

    /// <summary>Sends one text frame to the connected client.</summary>
    public async Task SendAsync(string json)
    {
        var socket = _socket ?? throw new InvalidOperationException("No client is connected.");

        byte[] bytes = Encoding.UTF8.GetBytes(json);
        await socket.SendAsync(bytes, WebSocketMessageType.Text, endOfMessage: true, CancellationToken.None);
    }

    /// <summary>Sends an action result for <paramref name="requestId"/>.</summary>
    public Task SendActionResultAsync(string requestId, string data = "{}") =>
        SendAsync($"{{\"type\":\"action_result\",\"id\":\"{requestId}\",\"status\":\"ok\",\"data\":{data}}}");

    /// <summary>
    /// Drops the connection without a close handshake, so the client sees a transport failure rather
    /// than an orderly shutdown — which is what a dropped network looks like.
    /// </summary>
    public void DropConnection()
    {
        var socket = _socket;
        _socket = null;

        if (socket == null) return;

        // Abort() alone does not tear down the underlying connection under HttpListener, so the
        // client keeps reporting IsConnected. Disposing the socket is what actually drops it.
        try { socket.Abort(); } catch { /* already gone */ }
        try { socket.Dispose(); } catch { /* already gone */ }
    }

    /// <summary>Waits for the next frame the client sent, or throws if none arrives in time.</summary>
    public async Task<string> NextReceivedAsync(TimeSpan timeout)
    {
        if (!await _receivedSignal.WaitAsync(timeout))
        {
            throw new TimeoutException("The client sent nothing within " + timeout);
        }

        _received.TryDequeue(out string? frame);
        return frame ?? "";
    }

    /// <summary>Every frame the client has sent so far.</summary>
    public string[] Received() => _received.ToArray();

    private async Task AcceptLoopAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            HttpListenerContext context;

            try
            {
                context = await _listener.GetContextAsync();
            }
            catch (Exception)
            {
                return; // listener stopped
            }

            if (!context.Request.IsWebSocketRequest)
            {
                context.Response.StatusCode = 400;
                context.Response.Close();
                continue;
            }

            HttpListenerWebSocketContext wsContext;

            try
            {
                wsContext = await context.AcceptWebSocketAsync(subProtocol: null);
            }
            catch (Exception)
            {
                continue;
            }

            Interlocked.Increment(ref _connectionCount);
            _socket = wsContext.WebSocket;

            _ = Task.Run(() => ReceiveLoopAsync(wsContext.WebSocket, cancellationToken), CancellationToken.None);
        }
    }

    private async Task ReceiveLoopAsync(WebSocket socket, CancellationToken cancellationToken)
    {
        var buffer = new byte[8192];

        try
        {
            while (!cancellationToken.IsCancellationRequested && socket.State == WebSocketState.Open)
            {
                var result = await socket.ReceiveAsync(buffer, cancellationToken);

                if (result.MessageType == WebSocketMessageType.Close)
                {
                    // Complete the handshake. Returning without replying leaves the client's
                    // CloseAsync waiting forever, which looks exactly like a client-side hang.
                    try
                    {
                        await socket.CloseOutputAsync(WebSocketCloseStatus.NormalClosure, null, CancellationToken.None);
                    }
                    catch
                    {
                        // The client may already be gone.
                    }

                    return;
                }
                if (result.Count == 0) continue;

                _received.Enqueue(Encoding.UTF8.GetString(buffer, 0, result.Count));
                _receivedSignal.Release();
            }
        }
        catch (Exception)
        {
            // A dropped or aborted connection ends the loop; the test decides what that means.
        }
    }

    /// <summary>Binds a socket to port 0 and reads back what the OS chose.</summary>
    private static int FreePort()
    {
        var probe = new TcpListener(IPAddress.Loopback, 0);
        probe.Start();
        int port = ((IPEndPoint)probe.LocalEndpoint).Port;
        probe.Stop();
        return port;
    }

    public ValueTask DisposeAsync()
    {
        _cts.Cancel();
        DropConnection();

        try { _listener.Stop(); } catch { /* already stopped */ }

        _cts.Dispose();
        _receivedSignal.Dispose();

        return ValueTask.CompletedTask;
    }
}
