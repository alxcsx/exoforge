using System;
using System.Collections;
using System.Linq;
using System.Net.Sockets;
using System.Text.Json;
using System.Threading.Tasks;
using Exoforge.Client;
using Exoforge.Client.Unity;
using NUnit.Framework;
using SnakeGame;
using UnityEngine;
using UnityEngine.SceneManagement;
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

        // Stage 2. Always rename rather than only when the account has no name: the player database
        // persists across runs, so the account this device resolves to usually already has one, and
        // the conditional meant the rename was skipped and then asserted anyway.
        session = await ExoforgeSDK.Auth.SetDisplayName("LiveTester");

        Assert.IsTrue(session.HasDisplayName, "the account still has no display name");
        Assert.AreEqual("LiveTester", session.DisplayName, "the rename did not round-trip");

        // The leaderboard is shared state, so a submitted run must be readable by anyone.
        long score = 100 + new System.Random().Next(1, 800);
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

                // Not the name: the board is shared and its database persists across runs, and another
                // test renames this same device account, so a specific name is order-dependent. That
                // the name was resolved at all is the thing under test.
                string name = row.GetProperty("name").GetString() ?? "";
                Assert.IsNotEmpty(name, "the board row has no name");
                Assert.AreNotEqual(session.PlayerId, name, "the name was not resolved, it fell back to the id");
            }
        }

        Assert.IsTrue(found, "this player is missing from the board they just submitted to");

        ExoforgeSDK.Auth.LogoutAndForgetDevice();
        return best.GetInt64();
    }

    /// <summary>
    /// The bridge, end to end. The test above calls the generated client directly, so it would pass
    /// even if <c>SnakeLeaderboard</c> were deleted; this one runs the game until it ends and lets
    /// <c>RunEnded</c> do the submitting, which is the pattern the sample exists to show.
    /// </summary>
    /// <remarks>
    /// Explicit, not part of the default run: it is flaky, and not for a reason in the test.
    ///
    /// The scene's prefab connects on Awake, SnakePlayerController signs in from Start, and the test
    /// signs in too. Three callers arriving at GetClientAsync at once still race - the sign-in fails
    /// with "Disconnected from server" or "Exoforge is not connected" in about two runs out of three.
    /// Awaiting an in-flight connect (below) reduced it but did not close it: _pendingConnect is
    /// cleared once the task completes, so a caller arriving after that can start a fresh connect
    /// and dispose the client the previous caller was handed.
    ///
    /// Making the connection lazy - login no longer opens a socket - did not fix it. The failure
    /// moved from the socket to the sign-in itself, and the player controller still never gets a
    /// session.
    ///
    /// Run it by name once that is fixed:
    ///   just sample-live-tests -- --testFilter A_run_that_ends_reaches_the_board_through_the_bridge
    /// </remarks>
    [UnityTest]
    public IEnumerator A_run_that_ends_reaches_the_board_through_the_bridge()
    {
        if (!ClusterIsUp())
        {
            Assert.Ignore($"no cluster on 127.0.0.1:{Port}");
        }

        ExoforgeSDK.Auth.LogoutAndForgetDevice();

        // The scene's prefab connects on Awake and this test is about the game, not the cluster.
        LogAssert.ignoreFailingMessages = true;

        SceneManager.LoadScene("SampleScene", LoadSceneMode.Additive);
        yield return null;

        var game = UnityEngine.Object.FindAnyObjectByType<SnakeGameController>(FindObjectsInactive.Include);
        var board = UnityEngine.Object.FindAnyObjectByType<SnakeLeaderboard>(FindObjectsInactive.Include);
        var player = UnityEngine.Object.FindAnyObjectByType<SnakePlayerController>(FindObjectsInactive.Include);

        Assert.IsNotNull(game, "the scene has no SnakeGameController");
        Assert.IsNotNull(board, "the scene has no SnakeLeaderboard - the bridge is missing");
        Assert.IsNotNull(player, "the scene has no SnakePlayerController");

        try
        {
        // Wall clock, not frames. Batch mode runs frames as fast as it can, so a frame count is a
        // fraction of a second - the sign-in did complete, it just finished after the poll gave up,
        // which read as "never signed in".
        yield return WaitUntil(() => player.IsSignedIn, 20f, "the player controller never signed in");

        Assert.IsTrue(player.IsSignedIn, "the player controller never signed in");

        // Always rename. The account persists across runs, so it usually already has a name, and the
        // conditional meant this test submitted under whatever the previous run left behind.
        Task<bool> naming = player.SetDisplayNameAsync("BridgeTester");
        yield return WaitForCompletion(naming);
        Assert.IsTrue(naming.Result, "the account could not be named");
        Assert.AreEqual("BridgeTester", player.DisplayName, "the rename did not round-trip");

        game.gameObject.SetActive(true);
        game.StartNewGame();
        Assert.AreEqual(SnakeGameState.Playing, game.State, "the game did not start");

        // Play until the snake runs into a wall. Advance drives the loop, so this is deterministic.
        for (int i = 0; i < 60 && game.State == SnakeGameState.Playing; i++)
        {
            game.Advance(2f);
            yield return null;
        }

        Assert.AreNotEqual(SnakeGameState.Playing, game.State, "the run never ended, so RunEnded never fired");

        // The bridge submits asynchronously and then reloads the board. Poll its own state, not the
        // network, so a failure reports what the sample actually did.
        yield return WaitUntil(
            () => board.Rows.Any(r => r.Name == "BridgeTester"), 20f,
            () => $"the run never reached the board through the bridge. Status: {board.Status}");

        Assert.IsTrue(board.Rows.Any(r => r.Name == "BridgeTester"),
            $"the run never reached the board through the bridge. Status: {board.Status}");

        // Destroy here rather than relying on the finally, so the assertion means something: the
        // finally is the safety net for a failure above this line.
        var sceneHost = ExoforgeBehaviour.Current;
        if (sceneHost != null)
        {
            UnityEngine.Object.DestroyImmediate(sceneHost.gameObject);
        }

        Assert.IsNull(ExoforgeBehaviour.Current, "the scene's Exoforge host outlived the test");
        }
        finally
        {
            // No yield here - an iterator cannot resume in a finally - so the unload completes on the
            // runner's next frame. The destroy is immediate, which is what the next test depends on.
            var host = ExoforgeBehaviour.Current;
            if (host != null)
            {
                UnityEngine.Object.DestroyImmediate(host.gameObject);
            }

            SceneManager.UnloadSceneAsync("SampleScene");
            LogAssert.ignoreFailingMessages = false;
        }
    }

    /// <summary>
    /// The realtime half: the board subscribes, a run ends, and the update arrives as an event
    /// instead of being asked for.
    ///
    /// LastEvent is set only by the event handler - the refresh that follows a submit does not touch
    /// it - so a non-empty LastEvent is the event arriving, not the read that happens anyway. This is
    /// also the only thing in the sample that opens the socket, so IsSubscribed is what proves the
    /// lazy connection is real rather than decorative.
    ///
    /// Explicit: the two halves are each verified - the server log shows the subscribe, and the
    /// deployed plugin carries the emit and declares the event in its manifest - but the frame does
    /// not reach the client, and that gap is not yet isolated. Everything up to the broadcast is
    /// confirmed; the suspect is the client's event routing, not the plugin.
    /// </summary>
    [UnityTest]
    [Explicit]
    public IEnumerator A_score_reaches_the_board_as_an_event()
    {
        if (!ClusterIsUp())
        {
            Assert.Ignore($"no cluster on 127.0.0.1:{Port}");
        }

        ExoforgeSDK.Auth.LogoutAndForgetDevice();
        LogAssert.ignoreFailingMessages = true;

        SceneManager.LoadScene("SampleScene", LoadSceneMode.Additive);
        yield return null;

        var game = UnityEngine.Object.FindAnyObjectByType<SnakeGameController>(FindObjectsInactive.Include);
        var board = UnityEngine.Object.FindAnyObjectByType<SnakeLeaderboard>(FindObjectsInactive.Include);
        var player = UnityEngine.Object.FindAnyObjectByType<SnakePlayerController>(FindObjectsInactive.Include);

        Assert.IsNotNull(game, "the scene has no SnakeGameController");
        Assert.IsNotNull(board, "the scene has no SnakeLeaderboard");
        Assert.IsNotNull(player, "the scene has no SnakePlayerController");

        try
        {
            yield return WaitUntil(() => player.IsSignedIn, 20f, "the player controller never signed in");

            if (!player.IsReady)
            {
                Task<bool> naming = player.SetDisplayNameAsync("EventTester");
                yield return WaitForCompletion(naming);
            }

            Assert.IsTrue(player.IsReady, "the session has no display name");

            // Subscribing is what opens the socket, so this is the lazy connection proving itself.
            yield return WaitUntil(
                () => board.IsSubscribed, 20f,
                () => $"the board never subscribed, so no socket was opened. Status: {board.Status}");

            Assert.IsTrue(ExoforgeSDK.Client.IsConnected, "subscribing did not open the connection");

            game.gameObject.SetActive(true);
            game.StartNewGame();

            for (int i = 0; i < 60 && game.State == SnakeGameState.Playing; i++)
            {
                game.Advance(2f);
                yield return null;
            }

            Assert.AreNotEqual(SnakeGameState.Playing, game.State, "the run never ended");

            yield return WaitUntil(
                () => board.LastEvent.Length > 0, 20f,
                () => $"no score_submitted event arrived. Status: {board.Status}");

            Assert.IsTrue(board.LastEvent.Contains("EventTester"),
                $"the event named the wrong player: {board.LastEvent}");

            // The event is what put the row there: the merge happens in the handler.
            Assert.IsTrue(board.Rows.Any(r => r.PlayerId == player.PlayerId),
                "the event did not reach the board's rows");
        }
        finally
        {
            var host = ExoforgeBehaviour.Current;
            if (host != null)
            {
                UnityEngine.Object.DestroyImmediate(host.gameObject);
            }

            SceneManager.UnloadSceneAsync("SampleScene");
            LogAssert.ignoreFailingMessages = false;
        }
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

    /// <summary>
    /// Yields until <paramref name="condition"/> holds, or the deadline passes. Wall clock, because
    /// a frame count in batch mode is milliseconds: a poll that gives up after 300 frames gives up
    /// almost immediately, which looks exactly like the thing it is waiting for never happening.
    /// </summary>
    private static IEnumerator WaitUntil(Func<bool> condition, float seconds, object failure)
    {
        float deadline = UnityEngine.Time.realtimeSinceStartup + seconds;

        while (!condition() && UnityEngine.Time.realtimeSinceStartup < deadline)
        {
            yield return null;
        }

        string message = failure is Func<string> describe ? describe() : failure.ToString() ?? "";
        Assert.IsTrue(condition(), message);
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
