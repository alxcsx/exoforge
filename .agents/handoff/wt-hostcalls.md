# wt/hostcalls: concurrent host calls from a native extension  (worktree /Users/alexcs/projects/exoforge-wt/hostcalls)
Read wt-common.md first. Today sdk/csharp/Exoforge.Plugin.SDK/PluginHost.cs HostCall (~L775) is synchronous:
`++_nextHostCallId` (not thread-safe) and it reads stdin on the calling thread until its reply, with
BufferedFrames/BufferedHostCallResults for frames that arrive meanwhile. Two threads calling at once race.
Want the multiplexed-connection pattern (what a GenServer owning a Port does):
- One background reader owns stdin and routes every frame.
- A host call takes its id with Interlocked.Increment, registers a TaskCompletionSource in a
  ConcurrentDictionary, writes under the existing WriteLock and awaits it; the reader completes it.
  Per-call timeout + CancellationToken.
- action/event/lifecycle frames go to a single-consumer Channel<T>, so actions and OnEvent still run one at a
  time (the BUG-17 guarantee: an event arriving during a host call runs after the current action).
- Async host APIs await instead of blocking a thread; sync wrappers keep working (no deadlock when called
  from an action - check the sync-over-async path carefully).
- Wire protocol unchanged (extension_protocol_test.exs / HandshakeTests.cs stay green).
- Delete BufferedFrames/BufferedHostCallResults if the new loop makes them dead.
Tests (Plugin.SDK.Tests): Task.WhenAll of 50 host calls answered out of order all get their own result;
an event during a host call still runs after the action (keep FrameLoopTests); timeout; host EOF fails
pending calls instead of hanging. Run core native_extension_runner/extension_protocol tests too.
