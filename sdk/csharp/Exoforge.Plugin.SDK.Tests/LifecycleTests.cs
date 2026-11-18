using System.IO;
using System.Text;
using System.Threading.Tasks;
using Exoforge.Plugin.SDK;
using Xunit;

namespace Exoforge.Plugin.SDK.Tests;

[ExoService("lifecycle_probe", Version = "1.0.0")]
public class LifecycleProbe
{
    public int Calls { get; private set; }

    public void OnExtensionStart() => Calls++;
}

[ExoService("lifecycle_async_probe", Version = "1.0.0")]
public class LifecycleAsyncProbe
{
    public int Calls { get; private set; }

    public async Task OnExtensionStart()
    {
        await Task.Delay(10);
        Calls++;
    }
}

[ExoService("lifecycle_error_probe", Version = "1.0.0")]
public class LifecycleErrorProbe
{
    public void OnExtensionStart() =>
        throw new ExoActionException("seed_failed", "seed data could not be written");
}

[ExoService("lifecycle_none_probe", Version = "1.0.0")]
public class LifecycleNoneProbe
{
    [ExoAction("ping", Mode = ActionMode.Sync)]
    public int Ping() => 1;
}

[ExoService("lifecycle_seed_probe", Version = "1.0.0")]
public class LifecycleSeedProbe
{
    public int StartupCalls { get; private set; }
    public int SeedCalls { get; private set; }
    public bool SeedRanAfterStartup { get; private set; }

    public void OnExtensionStart() => StartupCalls++;

    [ExoSeed]
    public void Seed()
    {
        SeedCalls++;
        SeedRanAfterStartup = StartupCalls > 0;
    }
}

[ExoService("lifecycle_async_seed_probe", Version = "1.0.0")]
public class LifecycleAsyncSeedProbe
{
    public int SeedCalls { get; private set; }

    [ExoSeed]
    public async Task SeedAsync()
    {
        await Task.Delay(10);
        SeedCalls++;
    }
}

[ExoService("lifecycle_seed_error_probe", Version = "1.0.0")]
public class LifecycleSeedErrorProbe
{
    [ExoSeed]
    public void Seed() =>
        throw new ExoActionException("seed_failed", "database seed failed");
}

/// <summary>
/// The optional startup hook. The host asks only extensions that declared the `lifecycle`
/// capability; this side runs OnExtensionStart once per process and answers explicitly.
/// </summary>
public class LifecycleTests
{
    private const string Hello =
        "{\"type\":\"hello\",\"protocol\":1,\"host\":\"exoforge\",\"capabilities\":[\"action_result\",\"host_call\",\"host_log\",\"lifecycle_result\"]}";

    [Fact]
    public void Startup_hook_runs_once_and_reports_ok()
    {
        var plugin = new LifecycleProbe();
        var output = new MemoryStream();

        PluginHost.RunInstance(
            plugin,
            Lines(Hello,
                "{\"type\":\"lifecycle\",\"id\":1}",
                "{\"type\":\"lifecycle\",\"id\":2}"),
            output,
            null);

        Assert.Equal(1, plugin.Calls);

        string written = Encoding.UTF8.GetString(output.ToArray());
        Assert.Contains("\"type\":\"lifecycle_result\",\"id\":1,\"status\":\"ok\"", written);
        Assert.Contains("\"type\":\"lifecycle_result\",\"id\":2,\"status\":\"ok\"", written);
    }

    [Fact]
    public async Task Async_startup_hook_is_awaited()
    {
        var plugin = new LifecycleAsyncProbe();
        var output = new MemoryStream();

        PluginHost.RunInstance(
            plugin,
            Lines(Hello, "{\"type\":\"lifecycle\",\"id\":1}"),
            output,
            null);

        Assert.Equal(1, plugin.Calls);
        Assert.Contains(
            "\"type\":\"lifecycle_result\",\"id\":1,\"status\":\"ok\"",
            Encoding.UTF8.GetString(output.ToArray()));

        await Task.CompletedTask;
    }

    [Fact]
    public void Startup_hook_failure_reports_structured_error()
    {
        var plugin = new LifecycleErrorProbe();
        var output = new MemoryStream();

        PluginHost.RunInstance(
            plugin,
            Lines(Hello, "{\"type\":\"lifecycle\",\"id\":1}"),
            output,
            null);

        string written = Encoding.UTF8.GetString(output.ToArray());
        Assert.Contains("\"type\":\"lifecycle_result\",\"id\":1,\"status\":\"error\"", written);
        Assert.Contains("\"code\":\"seed_failed\"", written);
        Assert.Contains("seed data could not be written", written);
    }

    [Fact]
    public void An_extension_without_the_hook_still_reports_ok()
    {
        var plugin = new LifecycleNoneProbe();
        var output = new MemoryStream();

        PluginHost.RunInstance(
            plugin,
            Lines(Hello, "{\"type\":\"lifecycle\",\"id\":1}"),
            output,
            null);

        Assert.Contains(
            "\"type\":\"lifecycle_result\",\"id\":1,\"status\":\"ok\"",
            Encoding.UTF8.GetString(output.ToArray()));
    }

    [Fact]
    public void Seed_hook_runs_after_startup_hook_and_reports_ok()
    {
        var plugin = new LifecycleSeedProbe();
        var output = new MemoryStream();

        PluginHost.RunInstance(
            plugin,
            Lines(Hello, "{\"type\":\"lifecycle\",\"id\":1}"),
            output,
            null);

        Assert.Equal(1, plugin.StartupCalls);
        Assert.Equal(1, plugin.SeedCalls);
        Assert.True(plugin.SeedRanAfterStartup);

        string written = Encoding.UTF8.GetString(output.ToArray());
        Assert.Contains("\"type\":\"lifecycle_result\",\"id\":1,\"status\":\"ok\"", written);
    }

    [Fact]
    public void Seed_hook_runs_once_per_start()
    {
        var plugin = new LifecycleSeedProbe();
        var output = new MemoryStream();

        PluginHost.RunInstance(
            plugin,
            Lines(Hello,
                "{\"type\":\"lifecycle\",\"id\":1}",
                "{\"type\":\"lifecycle\",\"id\":2}"),
            output,
            null);

        Assert.Equal(1, plugin.SeedCalls);

        string written = Encoding.UTF8.GetString(output.ToArray());
        Assert.Contains("\"type\":\"lifecycle_result\",\"id\":1,\"status\":\"ok\"", written);
        Assert.Contains("\"type\":\"lifecycle_result\",\"id\":2,\"status\":\"ok\"", written);
    }

    [Fact]
    public async Task Async_seed_hook_is_awaited()
    {
        var plugin = new LifecycleAsyncSeedProbe();
        var output = new MemoryStream();

        PluginHost.RunInstance(
            plugin,
            Lines(Hello, "{\"type\":\"lifecycle\",\"id\":1}"),
            output,
            null);

        Assert.Equal(1, plugin.SeedCalls);
        Assert.Contains(
            "\"type\":\"lifecycle_result\",\"id\":1,\"status\":\"ok\"",
            Encoding.UTF8.GetString(output.ToArray()));

        await Task.CompletedTask;
    }

    [Fact]
    public void Seed_hook_failure_reports_structured_error()
    {
        var plugin = new LifecycleSeedErrorProbe();
        var output = new MemoryStream();

        PluginHost.RunInstance(
            plugin,
            Lines(Hello, "{\"type\":\"lifecycle\",\"id\":1}"),
            output,
            null);

        string written = Encoding.UTF8.GetString(output.ToArray());
        Assert.Contains("\"type\":\"lifecycle_result\",\"id\":1,\"status\":\"error\"", written);
        Assert.Contains("\"code\":\"seed_failed\"", written);
        Assert.Contains("database seed failed", written);
    }

    private static StringReader Lines(params string[] lines) =>
        new(string.Join("\n", lines) + "\n");
}
