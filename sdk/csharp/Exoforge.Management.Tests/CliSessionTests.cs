using System.Text.Json;
using Exoforge.Client;
using Xunit;

namespace Exoforge.Management.Tests;

/// <summary>
/// What `exo connect --save` leaves behind: a device session, not a long-lived service credential.
///
/// A saved session is the pair a client holds - an access token that lasts an hour and a refresh
/// token beside it - and the CLI renews the pair when the hour is up, writing the rotation back.
/// </summary>
public class CliSessionTests : IDisposable
{
    private readonly string _tempDir;

    public CliSessionTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), $"exo_cli_session_test_{Guid.NewGuid():N}");
        Directory.CreateDirectory(_tempDir);
    }

    public void Dispose()
    {
        try
        {
            if (Directory.Exists(_tempDir))
            {
                Directory.Delete(_tempDir, true);
            }
        }
        catch
        {
            // Ignore cleanup errors
        }
    }

    [Fact]
    public async Task Two_connects_leave_one_cli_session_and_no_service_token()
    {
        await using var cluster = StubCluster.Start();
        var workspace = ExoWorkspace.Initialize(_tempDir, "SessionTest");
        var deployer = new ExoDeployer(workspace);

        for (int i = 0; i < 2; i++)
        {
            var result = await deployer.ConnectAndVerifyAsync(
                environmentName: "local",
                wsUrlOverride: cluster.WsUri.ToString(),
                httpUrlOverride: cluster.HttpUri.ToString(),
                email: "admin",
                password: StubCluster.Password,
                save: true);

            Assert.True(result.Authenticated);
        }

        // No long-lived credential was minted: the saved session is the login pair.
        Assert.Equal(0, cluster.IssueTokenCalls);
        Assert.Equal(2, cluster.LoginCalls);

        // The second connect replaced the first through the device-replace rule rather than adding
        // another pair: two logins, two token rows, one live session.
        Assert.Equal(1, cluster.LiveSessionCount);
        Assert.Equal(2, cluster.TokenRowCount);

        string deviceId = ExoDeployer.CliDeviceId("local");
        Assert.All(cluster.LoginPayloads, payload =>
            Assert.Equal(deviceId, payload.GetProperty("device_id").GetString()));

        var (access, refresh) = cluster.LiveSession;
        var env = workspace.GetActiveEnvironment("local");
        Assert.Equal(access, env.Token);
        Assert.Equal(refresh, env.RefreshToken);

        // Written to exoforge.json, so the next process finds it without logging in again.
        var reloaded = ExoWorkspace.Load(workspace.RootPath).GetActiveEnvironment("local");
        Assert.Equal(access, reloaded.Token);
        Assert.Equal(refresh, reloaded.RefreshToken);
    }

    [Fact]
    public async Task The_cli_refreshes_the_saved_pair_and_persists_the_rotation()
    {
        await using var cluster = StubCluster.Start();
        var workspace = ExoWorkspace.Initialize(_tempDir, "SessionTest");
        var deployer = new ExoDeployer(workspace);

        await deployer.ConnectAndVerifyAsync(
            environmentName: "local",
            wsUrlOverride: cluster.WsUri.ToString(),
            httpUrlOverride: cluster.HttpUri.ToString(),
            email: "admin",
            password: StubCluster.Password,
            save: true);

        cluster.ExpireAccessTokens();

        JsonElement status = await deployer.CallActionAsync("extension_manager", "get_system_info");

        Assert.Equal("stub", status.GetProperty("cluster").GetString());
        Assert.Equal(1, cluster.RefreshCalls);
        Assert.Equal(0, cluster.ReplayedRefreshTokens);
        Assert.Equal(1, cluster.LoginCalls);

        var (access, refresh) = cluster.LiveSession;
        var env = workspace.GetActiveEnvironment("local");
        Assert.Equal(access, env.Token);
        Assert.Equal(refresh, env.RefreshToken);

        // The rotated pair is on disk, which is what the next command runs with: no new login and
        // no second rotation.
        var reloaded = ExoWorkspace.Load(workspace.RootPath).GetActiveEnvironment("local");
        Assert.Equal(access, reloaded.Token);
        Assert.Equal(refresh, reloaded.RefreshToken);

        await deployer.CallActionAsync("extension_manager", "get_system_info");

        Assert.Equal(1, cluster.RefreshCalls);
        Assert.Equal(1, cluster.LoginCalls);

        // A call that expires after the connection is up goes through the client's own refresh
        // gate: one rotation, the call retried once, the rotated pair saved.
        using var client = await deployer.CreateConnectedClientAsync("local");
        cluster.ExpireAccessTokens();

        JsonElement retried = await client.SendActionAsync<JsonElement>(
            "extension_manager", "get_system_info", null, ExoTransportPreference.Http);

        Assert.Equal("stub", retried.GetProperty("cluster").GetString());
        Assert.Equal(2, cluster.RefreshCalls);
        Assert.Equal(0, cluster.ReplayedRefreshTokens);
        Assert.Equal(cluster.LiveSession.Refresh, workspace.GetActiveEnvironment("local").RefreshToken);
    }
}
