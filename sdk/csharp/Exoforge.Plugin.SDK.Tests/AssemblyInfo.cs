using Xunit;

// HostBridge's transport is process-wide by design: a plugin is its own process, so there is
// exactly one. Tests share it, so they must not run concurrently.
[assembly: CollectionBehavior(DisableTestParallelization = true)]
