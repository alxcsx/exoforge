using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Text.Json.Nodes;
using Xunit;

namespace Exoforge.Plugin.SDK.Tests;

/// <summary>
/// The deployment guards and the runtime contract.
///
/// A plugin published with trimming or AOT builds and then serialises records as empty objects -
/// silently, and only once deployed, which is the worst shape a failure can take. The guards make
/// that a build error. The other half is the runtime coupling: a plugin built for an older runtime
/// runs on a newer image, and one that demands a runtime the image does not carry must fail with a
/// message that names it rather than start and misbehave.
/// </summary>
public class DeploymentGuardTests
{
    [Theory]
    [InlineData("PublishAot", "EXOFORGE001")]
    [InlineData("PublishTrimmed", "EXOFORGE002")]
    public async Task A_plugin_cannot_build_with_a_property_that_removes_reflection_metadata(
        string property,
        string errorCode)
    {
        var (exitCode, output) =
          await RunDotnetAsync($"build \"{FixtureProject}\" -p:{property}=true -v q --nologo");

        Assert.NotEqual(0, exitCode);
        Assert.Contains(errorCode, output);
    }

    [Fact]
    public async Task The_published_plugin_states_its_runtime_and_refuses_a_missing_one()
    {
        string outputDir = Path.Combine(Path.GetTempPath(), $"exo_runtime_contract_{Guid.NewGuid():N}");

        try
        {
            var (exitCode, log) = await RunDotnetAsync(
                $"publish \"{FixtureProject}\" -c Release -r {RuntimeInformation.RuntimeIdentifier} " +
                $"-p:PublishSingleFile=false -o \"{outputDir}\" -v q --nologo");

            Assert.True(exitCode == 0, log);

            string configPath = Path.Combine(outputDir, "guard_probe.runtimeconfig.json");
            string config = File.ReadAllText(configPath);
            string demanded;

            using (var document = JsonDocument.Parse(config))
            {
                JsonElement options = document.RootElement.GetProperty("runtimeOptions");
                JsonElement framework = options.GetProperty("framework");

                // LatestMajor is what lets a plugin built against the SDK's framework run on a newer
                // image; the version is the floor, and below it the apphost refuses to start.
                Assert.Equal("LatestMajor", options.GetProperty("rollForward").GetString());
                Assert.Equal("Microsoft.NETCore.App", framework.GetProperty("name").GetString());

                string tfm = options.GetProperty("tfm").GetString()!;
                demanded = framework.GetProperty("version").GetString()!;
                Assert.StartsWith($"net{demanded.Split('.')[0]}.", tfm);
            }

            // Demand a runtime no image has. It must refuse with the framework and the version,
            // not start into a plugin whose home runtime is missing.
            JsonNode root = JsonNode.Parse(config)!;
            root["runtimeOptions"]!["framework"]!["version"] = "99.0.0";
            File.WriteAllText(configPath, root.ToJsonString());

            var start = new ProcessStartInfo(Executable(outputDir))
            {
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                RedirectStandardInput = true,
                UseShellExecute = false,
            };

            using var process = Process.Start(start)!;
            process.StandardInput.Close();
            Task<string> stdout = process.StandardOutput.ReadToEndAsync();
            Task<string> stderr = process.StandardError.ReadToEndAsync();

            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(30));

            try
            {
                await process.WaitForExitAsync(timeout.Token);
            }
            catch (OperationCanceledException)
            {
                process.Kill(entireProcessTree: true);
                throw new TimeoutException("The published plugin did not exit, so it did not refuse the missing runtime.");
            }

            await Task.WhenAll(stdout, stderr);
            string message = stderr.Result + stdout.Result;

            Assert.NotEqual(0, process.ExitCode);
            Assert.Contains("Microsoft.NETCore.App", message);
            Assert.Contains("99.0.0", message);
        }
        finally
        {
            if (Directory.Exists(outputDir))
            {
                Directory.Delete(outputDir, true);
            }
        }
    }

    private static string Executable(string outputDir) =>
        Path.Combine(outputDir, OperatingSystem.IsWindows() ? "guard_probe.exe" : "guard_probe");

    private static string FixtureProject => Path.GetFullPath(Path.Combine(
        AppContext.BaseDirectory, "..", "..", "..", "fixtures", "guard_probe", "guard_probe.csproj"));

    private static async Task<(int ExitCode, string Output)> RunDotnetAsync(string arguments)
    {
        var start = new ProcessStartInfo("dotnet", arguments)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };

        using var process = Process.Start(start)!;

        // Both streams are drained while the build runs. ReadToEnd on one and then the other is the
        // classic deadlock: a build that fills the second pipe blocks, and the first never reaches
        // EOF, so the test hangs with a build that already finished its work.
        Task<string> stdout = process.StandardOutput.ReadToEndAsync();
        Task<string> stderr = process.StandardError.ReadToEndAsync();

        // Async wait, not a blocking WaitForExit (M33 Fix 12): the xunit worker thread parks while
        // the build runs, starving the pool the stream reads and the other tests need.
        using var timeout = new CancellationTokenSource(TimeSpan.FromMinutes(3));

        try
        {
            await process.WaitForExitAsync(timeout.Token);
        }
        catch (OperationCanceledException)
        {
            process.Kill(entireProcessTree: true);
            throw new TimeoutException($"dotnet {arguments} did not finish within three minutes.");
        }

        await Task.WhenAll(stdout, stderr);
        return (process.ExitCode, stdout.Result + stderr.Result);
    }
}
