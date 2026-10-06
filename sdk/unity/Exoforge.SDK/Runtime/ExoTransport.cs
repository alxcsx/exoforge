using System;
using System.IO;
using System.Net.WebSockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace Exoforge.Client;

/// <summary>
/// Transport layer handling raw WebSocket framing over ClientWebSocket.
/// Thread-safe send and resilient background receive loop.
/// </summary>
public class ExoTransport : IDisposable
{
    private ClientWebSocket? _webSocket;
    private CancellationTokenSource? _cts;
    private readonly SemaphoreSlim _sendLock = new(1, 1);
    private Task? _receiveTask;

    public bool IsConnected => _webSocket != null && _webSocket.State == WebSocketState.Open;

    public event Action<string>? OnMessageReceived;
    public event Action? OnConnected;
    public event Action<Exception?>? OnDisconnected;

    public async Task ConnectAsync(Uri serverUri, CancellationToken cancellationToken = default)
    {
        if (IsConnected)
        {
            return;
        }

        _cts?.Cancel();
        _cts = new CancellationTokenSource();

        _webSocket?.Dispose();
        _webSocket = new ClientWebSocket();

        using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, _cts.Token);
        await _webSocket.ConnectAsync(serverUri, linkedCts.Token).ConfigureAwait(false);

        OnConnected?.Invoke();

        _receiveTask = Task.Run(() => ReceiveLoopAsync(_cts.Token));
    }

    public async Task SendAsync(string text, CancellationToken cancellationToken = default)
    {
        if (!IsConnected || _webSocket == null)
        {
            throw new InvalidOperationException("WebSocket is not connected.");
        }

        byte[] bytes = Encoding.UTF8.GetBytes(text);
        var buffer = new ArraySegment<byte>(bytes);

        await _sendLock.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            await _webSocket.SendAsync(buffer, WebSocketMessageType.Text, true, cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            _sendLock.Release();
        }
    }

    public async Task DisconnectAsync(CancellationToken cancellationToken = default)
    {
        if (_webSocket == null)
        {
            return;
        }

        _cts?.Cancel();

        try
        {
            if (_webSocket.State == WebSocketState.Open)
            {
                await _webSocket.CloseAsync(WebSocketCloseStatus.NormalClosure, "Client disconnecting", cancellationToken)
                    .ConfigureAwait(false);
            }
        }
        catch
        {
            // Ignore socket closure errors
        }
        finally
        {
            _webSocket.Dispose();
            _webSocket = null;
            OnDisconnected?.Invoke(null);
        }
    }

    private async Task ReceiveLoopAsync(CancellationToken cancellationToken)
    {
        var buffer = new byte[8192];
        var memoryStream = new MemoryStream();

        try
        {
            while (!cancellationToken.IsCancellationRequested && _webSocket != null && _webSocket.State == WebSocketState.Open)
            {
                memoryStream.SetLength(0);
                WebSocketReceiveResult result;

                do
                {
                    result = await _webSocket.ReceiveAsync(new ArraySegment<byte>(buffer), cancellationToken).ConfigureAwait(false);

                    if (result.MessageType == WebSocketMessageType.Close)
                    {
                        await _webSocket.CloseAsync(WebSocketCloseStatus.NormalClosure, "Closing", CancellationToken.None).ConfigureAwait(false);
                        OnDisconnected?.Invoke(null);
                        return;
                    }

                    memoryStream.Write(buffer, 0, result.Count);
                }
                while (!result.EndOfMessage);

                if (result.MessageType == WebSocketMessageType.Text)
                {
                    string message = Encoding.UTF8.GetString(memoryStream.ToArray());
                    OnMessageReceived?.Invoke(message);
                }
            }
        }
        catch (OperationCanceledException)
        {
            // Normal cancellation
        }
        catch (Exception ex)
        {
            OnDisconnected?.Invoke(ex);
        }
    }

    public void Dispose()
    {
        _cts?.Cancel();
        _cts?.Dispose();
        _webSocket?.Dispose();
        _sendLock.Dispose();
    }
}
