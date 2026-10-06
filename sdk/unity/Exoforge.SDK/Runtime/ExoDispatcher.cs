using System;
using System.Collections.Concurrent;
using System.Threading;

namespace Exoforge.Client;

/// <summary>
/// Unity Main Thread Synchronization Dispatcher.
/// Queues callbacks and event notifications arriving on network background threads
/// to be safely executed on the main game thread during frame updates.
/// </summary>
public class ExoDispatcher
{
    private readonly ConcurrentQueue<Action> _executionQueue = new();
    private readonly SynchronizationContext? _syncContext;

    public ExoDispatcher(bool useSynchronizationContext = true)
    {
        if (useSynchronizationContext)
        {
            _syncContext = SynchronizationContext.Current;
        }
    }

    /// <summary>
    /// Enqueues an action to be executed on the main thread.
    /// </summary>
    public void Post(Action action)
    {
        if (_syncContext != null)
        {
            _syncContext.Post(_ =>
            {
                try
                {
                    action();
                }
                catch (Exception ex)
                {
                    Console.Error.WriteLine($"[ExoDispatcher] Uncaught exception in callback: {ex}");
                }
            }, null);
        }
        else
        {
            _executionQueue.Enqueue(action);
        }
    }

    /// <summary>
    /// Pumps all queued actions on the calling thread.
    /// Call this from Unity MonoBehaviour.Update().
    /// </summary>
    public void Update()
    {
        while (_executionQueue.TryDequeue(out var action))
        {
            try
            {
                action();
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"[ExoDispatcher] Uncaught exception in callback: {ex}");
            }
        }
    }

    /// <summary>
    /// Gets the number of pending callbacks in the queue.
    /// </summary>
    public int PendingCount => _executionQueue.Count;
}
