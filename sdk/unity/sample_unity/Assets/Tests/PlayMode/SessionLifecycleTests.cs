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
/// Session lifecycle for <see cref="ExoforgeBehaviour"/> and <see cref="ExoTokenStore"/>.
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
    private ExoforgeBehaviour NewBehaviour(string? wsUrl)
    {
        _host = new GameObject("ExoforgeTestHost");
        _host.SetActive(false);

        var behaviour = _host.AddComponent<ExoforgeBehaviour>();

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
        Assert.AreNotSame(clientAfterFailure, behaviour.Client,
            "the second attempt reused the failed client — it did not retry");
    }

    // ---- 2.2 ---------------------------------------------------------------------------

    [UnityTest]
    public IEnumerator Instance_is_cleared_when_the_behaviour_is_destroyed()
    {
        var behaviour = NewBehaviour("ws://127.0.0.1:1/ws");
        yield return null;

        Assert.AreSame(behaviour, ExoforgeBehaviour.Current);

        // The teardown disconnects, and ConnectAsync may have logged a failure if it got that far.
        LogAssert.ignoreFailingMessages = true;
        UnityEngine.Object.Destroy(_host);
        _host = null;
        yield return null;

        Assert.IsNull(ExoforgeBehaviour.Current,
            "a destroyed behaviour was still reachable as Current");

        Assert.Throws<InvalidOperationException>(() =>
        {
            var _ = ExoforgeBehaviour.Instance;
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
