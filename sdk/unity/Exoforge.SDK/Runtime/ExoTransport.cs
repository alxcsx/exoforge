using System;
using System.IO;
using System.Net.WebSockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace Exoforge.Client;

/// <summary>
/// Transport layer handling raw WebSocket framing over <see cref="ClientWebSocket"/>.
///
/// Thread-safe send and a background receive loop. Each connection owns its own socket, token and
/// receive loop, and a new connection drains the previous one first — a loop must never outlive the
/// socket it is reading.
/// </summary>
public class ExoTransport : IDisposable
{
    private ClientWebSocket? _webSocket;
    private CancellationTokenSource? _cts;
    private Task? _receiveTask;
    private int _disconnectNotified;
    private readonly SemaphoreSlim _sendLock = new(1, 1);

    public bool IsConnected => _webSocket is { State: WebSocketState.Open };

    public event Action<string>? OnMessageReceived;
    public event Action? OnConnected;
    public event Action<Exception?>? OnDisconnected;

    public async Task ConnectAsync(Uri serverUri, CancellationToken cancellationToken = default)
    {
        if (IsConnected)
        {
            return;
        }

        // Drain the previous connection before replacing it. Skipping this left the old receive loop
        // inside ReceiveAsync; because it read the socket through the field, it then issued a second
        // receive on the *new* socket, splitting frames between two readers and firing a late
        // OnDisconnected that a reconnect handler would misread as the new connection failing.
        await TeardownAsync(notify: false, CancellationToken.None).ConfigureAwait(false);

        var cts = new CancellationTokenSource();
        var socket = new ClientWebSocket();

        _cts = cts;
        _webSocket = socket;
        Interlocked.Exchange(ref _disconnectNotified, 0);

        try
        {
            using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, cts.Token);
            await socket.ConnectAsync(serverUri, linkedCts.Token).ConfigureAwait(false);
        }
        catch
        {
            _webSocket = null;
            _cts = null;
            socket.Dispose();
            cts.Dispose();
            throw;
        }

        OnConnected?.Invoke();

        // The socket and token are captured: the loop never reads them from a field that a later
        // connect could swap underneath it.
        _receiveTask = Task.Run(() => ReceiveLoopAsync(socket, cts.Token), CancellationToken.None);
    }

    public async Task SendAsync(string text, CancellationToken cancellationToken = default)
    {
        var socket = _webSocket;

        if (socket is not { State: WebSocketState.Open })
        {
            throw new InvalidOperationException("WebSocket is not connected.");
        }

        byte[] bytes = Encoding.UTF8.GetBytes(text);
        var buffer = new ArraySegment<byte>(bytes);

        await _sendLock.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            await socket.SendAsync(buffer, WebSocketMessageType.Text, true, cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            _sendLock.Release();
        }
    }

    public Task DisconnectAsync(CancellationToken cancellationToken = default) =>
        TeardownAsync(notify: true, cancellationToken);

    private async Task TeardownAsync(bool notify, CancellationToken cancellationToken)
    {
        var socket = _webSocket;
        var cts = _cts;
        var loop = _receiveTask;

        _webSocket = null;
        _cts = null;
        _receiveTask = null;

        cts?.Cancel();

        if (socket is { State: WebSocketState.Open })
        {
            try
            {
                await socket.CloseAsync(WebSocketCloseStatus.NormalClosure, "Client disconnecting", cancellationToken)
                    .ConfigureAwait(false);
            }
            catch
            {
                // A close that fails is not interesting: the socket is going away either way.
            }
        }

        if (loop != null)
        {
            try
            {
                await loop.ConfigureAwait(false);
            }
            catch
            {
                // The loop reports its own failures through OnDisconnected.
            }
        }

        socket?.Dispose();
        cts?.Dispose();

        if (notify)
        {
            NotifyDisconnected(null);
        }
    }

    private async Task ReceiveLoopAsync(WebSocket socket, CancellationToken cancellationToken)
    {
        var buffer = new byte[8192];
        var message = new MemoryStream();

        try
        {
            while (!cancellationToken.IsCancellationRequested && socket.State == WebSocketState.Open)
            {
                message.SetLength(0);
                WebSocketReceiveResult result;

                do
                {
                    result = await socket.ReceiveAsync(new ArraySegment<byte>(buffer), cancellationToken)
                        .ConfigureAwait(false);

                    if (result.MessageType == WebSocketMessageType.Close)
                    {
                        return;
                    }

                    message.Write(buffer, 0, result.Count);
                }
                while (!result.EndOfMessage);

                if (result.MessageType == WebSocketMessageType.Text)
                {
                    OnMessageReceived?.Invoke(Encoding.UTF8.GetString(message.ToArray()));
                }
            }
        }
        catch (OperationCanceledException)
        {
            // Normal cancellation: the connection is being torn down.
        }
        catch (Exception ex)
        {
            NotifyDisconnected(ex);
            return;
        }

        NotifyDisconnected(null);
    }

    /// <summary>
    /// Reports a dropped connection exactly once per connection.
    ///
    /// Both the receive loop and <see cref="DisconnectAsync"/> can reach this, and a duplicate
    /// notification is indistinguishable from the new connection failing — which is precisely what a
    /// reconnect handler must not be told.
    /// </summary>
    private void NotifyDisconnected(Exception? error)
    {
        if (Interlocked.Exchange(ref _disconnectNotified, 1) != 0)
        {
            return;
        }

        OnDisconnected?.Invoke(error);
    }

    public void Dispose()
    {
        _cts?.Cancel();

        _webSocket?.Dispose();
        _webSocket = null;

        _cts?.Dispose();
        _cts = null;

        _sendLock.Dispose();
    }
}
