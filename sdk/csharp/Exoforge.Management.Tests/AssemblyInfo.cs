using Xunit;

// CLI and Management tests manipulate process-wide state (such as Console.Out, environment and working directories).
[assembly: CollectionBehavior(DisableTestParallelization = true)]
