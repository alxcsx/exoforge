using Xunit;

// ExoTransport's KeepAliveInterval and CloseTimeout are process-wide, and tests that connect
// mutate them. Running them concurrently let one test's 150ms interval reach another's socket.
[assembly: CollectionBehavior(DisableTestParallelization = true)]
