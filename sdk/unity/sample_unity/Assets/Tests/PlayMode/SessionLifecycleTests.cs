using System;
using System.Collections;
using System.Text.RegularExpressions;
using Exoforge.Client;
using Exoforge.Client.Unity;
using NUnit.Framework;
using UnityEditor;
using UnityEngine;
using UnityEngine.TestTools;

/// <summary>
/// Session lifecycle for <see cref="ExoforgeManager"/> and <see cref="ExoTokenStore"/>.
///
/// Play mode, not edit mode: <c>Awake</c> does not run in the editor, so the behaviour is inert
/// there and none of this is observable. <see cref="ExoforgeSampleCheck"/> covers the parts that
/// work headlessly; this covers the parts that need a running player loop.
///
/// Run with: <c>just sample-play-tests</c>.
/// </summary>
public class SessionLifecycleTests
{
    private GameObject _host;

    [TearDown]
    public void TearDown()
    {
        ExoTokenStore.UseStudioSession = false;

        if (_host != null)
        {
            UnityEngine.Object.DestroyImmediate(_host);
            _host = null;
        }
    }

    /// <summary>
    /// Creates a behaviour without letting <c>Awake</c> connect: an inactive GameObject defers
    /// Awake until it is activated, so the fields can be set first.
    /// </summary>
    private ExoforgeManager NewBehaviour(string? wsUrl)
    {
        _host = new GameObject("ExoforgeTestHost");
        _host.SetActive(false);

        var behaviour = _host.AddComponent<ExoforgeManager>();

        var so = new SerializedObject(behaviour);
        so.FindProperty("connectOnAwake").boolValue = false;
        so.FindProperty("wsUrlOverride").stringValue = wsUrl ?? "";
        so.ApplyModifiedPropertiesWithoutUndo();

        _host.SetActive(true);
        return behaviour;
    }

    // ---- 2.1 ---------------------------------------------------------------------------

    [UnityTest]
    public IEnumerator A_failed_connection_can_be_retried()
    {
        // Port 1 has nothing listening, so the connect fails immediately.
        var behaviour = NewBehaviour("ws://127.0.0.1:1/ws");
        yield return null;

        // ConnectAsync reports the failure, which is right — the test has to say it expected it.
        LogAssert.Expect(LogType.Error, new Regex(@"\[Exoforge\] Connection error: .*"));

        var first = behaviour.GetClientAsync();
        yield return WaitForCompletion(first);

        Assert.IsTrue(first.IsFaulted, "connecting to a dead port should fail");

        ExoClient? clientAfterFailure = behaviour.Client;
        Assert.IsNotNull(clientAfterFailure);

        // The second call has to attempt a fresh connection rather than await the finished task.
        // Clearing _pendingConnect is what makes this true; without it, this call re-throws the
        // first failure and the game can never connect.
        LogAssert.Expect(LogType.Error, new Regex(@"\[Exoforge\] Connection error: .*"));

        var second = behaviour.GetClientAsync();
        yield return WaitForCompletion(second);

        Assert.IsTrue(second.IsFaulted);

        // The Expect above is what proves the retry: without a fresh attempt there would be no second
        // "Connection error" to match. The client itself is deliberately kept, because
        // ExoforgeSDK.Client hands it out before anything connects, so replacing it would invalidate
        // the reference game code is holding.
        Assert.AreSame(clientAfterFailure, behaviour.Client,
            "a failed connection should not swap the client out from under its holders");
    }

    // ---- 3.4 ---------------------------------------------------------------------------

    [UnityTest]
    public IEnumerator A_failed_connect_starts_retrying_with_backoff()
    {
        var behaviour = NewBehaviour("ws://127.0.0.1:1/ws");
        yield return null;

        // The connect failure is reported, and the retry loop announces its first attempt.
        LogAssert.Expect(LogType.Error, new Regex(@"\[Exoforge\] Connection error: .*"));
        LogAssert.Expect(LogType.Warning, new Regex(@"\[Exoforge\] Not connected\. Retrying in .*"));

        var call = behaviour.GetClientAsync();
        yield return WaitForCompletion(call);

        Assert.IsTrue(call.IsFaulted);

        // Let the loop announce itself, then stop expecting the failures it keeps producing —
        // retrying is the point, and each attempt logs.
        yield return WaitForSeconds(0.5f);
        LogAssert.ignoreFailingMessages = true;

        UnityEngine.Object.Destroy(_host);
        _host = null;
        yield return null;

        LogAssert.ignoreFailingMessages = false;
    }

    // ---- 2.2 ---------------------------------------------------------------------------

    [UnityTest]
    public IEnumerator Instance_is_cleared_when_the_behaviour_is_destroyed()
    {
        var behaviour = NewBehaviour("ws://127.0.0.1:1/ws");
        yield return null;

        Assert.AreSame(behaviour, ExoforgeManager.Current);

        // The teardown disconnects, and ConnectAsync may have logged a failure if it got that far.
        LogAssert.ignoreFailingMessages = true;
        UnityEngine.Object.Destroy(_host);
        _host = null;
        yield return null;

        Assert.IsNull(ExoforgeManager.Current,
            "a destroyed behaviour was still reachable as Current");

        Assert.Throws<InvalidOperationException>(() =>
        {
            var _ = ExoforgeManager.Instance;
        }, "Instance should report that no behaviour is in the scene, not hand back a destroyed one");

        LogAssert.ignoreFailingMessages = false;
    }

    // ---- 2.4 ---------------------------------------------------------------------------

    [Test]
    public void A_name_does_not_survive_a_different_account()
    {
        ExoTokenStore.Clear();

        ExoTokenStore.SaveSession("token-a", "player_a", new[] { "player" }, "Alice");
        Assert.AreEqual("Alice", ExoTokenStore.PlayerName);

        // Reconnecting as someone else, with no name supplied.
        ExoTokenStore.SaveSession("token-b", "player_b", new[] { "player" });
        Assert.AreEqual("", ExoTokenStore.PlayerName,
            "the previous account's name survived into a different account");

        ExoTokenStore.Clear();
    }

    [Test]
    public void Reconnecting_as_the_same_player_keeps_the_name()
    {
        ExoTokenStore.Clear();

        ExoTokenStore.SaveSession("token-a", "player_a", new[] { "player" }, "Alice");

        // A reconnect with a stored token passes no name; the same player keeps theirs.
        ExoTokenStore.SaveSession("token-c", "player_a", new[] { "player" });
        Assert.AreEqual("Alice", ExoTokenStore.PlayerName);

        ExoTokenStore.Clear();
    }

    // ---- helpers -----------------------------------------------------------------------

    private static IEnumerator WaitForSeconds(float seconds)
    {
        float deadline = Time.realtimeSinceStartup + seconds;

        while (Time.realtimeSinceStartup < deadline)
        {
            yield return null;
        }
    }

    private static IEnumerator WaitForCompletion<T>(System.Threading.Tasks.Task<T> task)
    {
        float deadline = Time.realtimeSinceStartup + 15f;

        while (!task.IsCompleted && Time.realtimeSinceStartup < deadline)
        {
            yield return null;
        }

        Assert.IsTrue(task.IsCompleted, "the operation did not finish within 15s");
    }
}
