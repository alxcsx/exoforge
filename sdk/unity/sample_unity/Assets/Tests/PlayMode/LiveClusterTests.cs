using System;
using System.Collections;
using System.Net.Sockets;
using System.Text.Json;
using System.Threading.Tasks;
using Exoforge.Client;
using Exoforge.Client.Unity;
using NUnit.Framework;
using UnityEngine.TestTools;

/// <summary>
/// The engine-side path against a real cluster: the same calls the sample makes, in the same order,
/// through the same generated client.
///
/// Play mode, because that is the only place <c>ExoforgeSDK</c> works — <c>Awake</c> does not run in
/// the editor. Skipped rather than failed when no cluster is running, so it stays honest about what
/// it did not check.
///
/// Run with <c>just sample-live-tests</c>, which starts the backend and deploys the plugin first.
/// </summary>
public class LiveClusterTests
{
    private const int Port = 4000;

    [UnityTest]
    public IEnumerator A_player_signs_in_and_uses_the_shared_leaderboard()
    {
        if (!ClusterIsUp())
        {
            Assert.Ignore($"no cluster on 127.0.0.1:{Port}");
        }

        // Start from a fresh account every run. Without this the test inherits the device identity and
        // token of whatever ran before it, which is a different scenario than the one it means to
        // check - and one that hides a real sign-in failure behind a stale credential.
        ExoforgeSDK.Auth.LogoutAndForgetDevice();

        // Unity's test runner cannot await, so the work runs as a task and the test pumps it.
        Task<long> work = RunAsync();
        yield return WaitForCompletion(work);

        if (work.IsFaulted)
        {
            throw work.Exception!.InnerException ?? work.Exception!;
        }

        // Tear down the host ExoforgeSDK created on demand. Leaving it alive makes this test poison
        // the next one: a second behaviour is destroyed by the duplicate-instance guard, so the
        // lifecycle test would never see its own become Current.
        var host = ExoforgeBehaviour.Current;
        if (host != null)
        {
            UnityEngine.Object.DestroyImmediate(host.gameObject);
        }

        Assert.IsNull(ExoforgeBehaviour.Current, "the host outlived the test");
        Assert.GreaterOrEqual(work.Result, 100, "the server reported a best score below the run");
    }

    /// <summary>Sign in, name the account, submit a run, and read it back from the shared board.</summary>
    private static async Task<long> RunAsync()
    {
        // Stage 1 — enter or register the account, keyed by the device.
        ExoSession session = await ExoforgeSDK.Auth.LoginAnonymously();

        Assert.IsNotEmpty(session.PlayerId, "the session has no player id");
        Assert.IsNotEmpty(session.Token, "the session has no token");
        Assert.IsTrue(ExoforgeSDK.Client.IsConnected, "the SDK is not connected");

        // Stage 2 — a fresh account has no display name; name it, as the prompt does.
        if (!session.HasDisplayName)
        {
            session = await ExoforgeSDK.Auth.SetDisplayName("LiveTester");
        }

        Assert.IsTrue(session.HasDisplayName, "the account still has no display name");
        Assert.AreEqual("LiveTester", session.DisplayName);

        // The leaderboard is shared state, so a submitted run must be readable by anyone.
        long score = 100 + new Random().Next(1, 800);
        var board = ExoforgeSDK.Client.SnakeLeaderboard();

        JsonElement best = await board.SubmitScoreAsync(session.DisplayName, session.PlayerId, score, 7);

        Assert.AreEqual(JsonValueKind.Number, best.ValueKind, "submit_score did not return the best score");
        Assert.GreaterOrEqual(best.GetInt64(), score, "the server reported a best below the run just sent");

        JsonElement ranking = await board.GetLeaderboardAsync(10);
        Assert.AreEqual(JsonValueKind.Array, ranking.ValueKind, "get_leaderboard did not return an array");

        bool found = false;

        foreach (var row in ranking.EnumerateArray())
        {
            if (row.TryGetProperty("player_id", out var id) && id.GetString() == session.PlayerId)
            {
                found = true;
                Assert.AreEqual("LiveTester", row.GetProperty("name").GetString(),
                    "the shared board has the wrong name for this player");
            }
        }

        Assert.IsTrue(found, "this player is missing from the board they just submitted to");

        ExoforgeSDK.Auth.LogoutAndForgetDevice();
        return best.GetInt64();
    }

    private static bool ClusterIsUp()
    {
        try
        {
            using var probe = new TcpClient();
            return probe.ConnectAsync("127.0.0.1", Port).Wait(TimeSpan.FromSeconds(2)) && probe.Connected;
        }
        catch
        {
            return false;
        }
    }

    private static IEnumerator WaitForCompletion<T>(Task<T> task)
    {
        float deadline = UnityEngine.Time.realtimeSinceStartup + 30f;

        while (!task.IsCompleted && UnityEngine.Time.realtimeSinceStartup < deadline)
        {
            yield return null;
        }

        Assert.IsTrue(task.IsCompleted, "the live round trip did not finish within 30s");
    }
}
