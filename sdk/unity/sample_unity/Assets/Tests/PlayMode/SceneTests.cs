using System.Collections;
using Exoforge.Client.Unity;
using NUnit.Framework;
using SnakeGame;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;

/// <summary>
/// The sample scene, loaded and played.
///
/// The other play-mode tests build their own objects; this one loads what a person pressing Play
/// actually gets — the wiring, the components, and the board. It drives the game through
/// <see cref="SnakeGameController.Advance"/> rather than waiting on frames, so it is the same run
/// every time.
/// </summary>
public class SceneTests
{
    private const string SceneName = "SampleScene";

    [UnityTest]
    public IEnumerator The_scene_plays_and_ends_a_run()
    {
        // The scene's Exoforge prefab connects on Awake, and this test is about the game, not the
        // cluster: with nothing listening it logs an error and retries. Expected, so not a failure.
        LogAssert.ignoreFailingMessages = true;

        SceneManager.LoadScene(SceneName, LoadSceneMode.Additive);
        yield return null;

        var game = Find<SnakeGameController>();
        var board = Find<SnakeBoardView>();

        Assert.IsNotNull(game, $"the scene has no {nameof(SnakeGameController)}");
        Assert.IsNotNull(board, $"the scene has no {nameof(SnakeBoardView)}");
        Assert.IsNotNull(Find<SnakePlayerController>(), "the scene has no session owner");

        // Gameplay ships inactive and is switched on once the player is signed in and named; that is
        // what the player controller does, so do the same.
        Assert.IsFalse(game!.gameObject.activeSelf, "gameplay should start inactive");
        game.gameObject.SetActive(true);
        yield return null;

        game.StartNewGame();
        Assert.AreEqual(SnakeGameState.Playing, game.State, "the game did not start");

        // The board repaints in LateUpdate, so give it a frame before looking at the squares.
        yield return null;

        // The board draws one square per cell, and the head square is the head colour.
        var squares = board!.GetComponentsInChildren<SpriteRenderer>();
        Assert.AreEqual(game.GridWidth * game.GridHeight, squares.Length,
            "the board did not draw one square per cell");

        var headSquare = squares[game.Head.y * game.GridWidth + game.Head.x];
        Assert.AreEqual((Color32)board.CellColour(game.Head), (Color32)headSquare.color,
            "the head square does not match what the board says that cell looks like");

        // It moves.
        var before = game.Head;
        game.Advance(1f);
        Assert.AreNotEqual(before, game.Head, "the snake did not move");

        // And it ends, once, at a wall.
        int ended = 0;
        game.RunEnded += (_, _) => ended++;

        for (int i = 0; i < 500 && game.State == SnakeGameState.Playing; i++)
        {
            game.Advance(1f);
        }

        Assert.AreEqual(SnakeGameState.Dead, game.State, "the snake never hit a wall");
        Assert.AreEqual(1, ended, "RunEnded should fire exactly once per run");

        // The scene's Exoforge prefab calls DontDestroyOnLoad, so it outlives the unload. Leaving it
        // makes this test poison the next one: a second behaviour is destroyed by the
        // duplicate-instance guard and never becomes Current.
        var host = ExoforgeManager.Current;
        if (host != null)
        {
            Object.DestroyImmediate(host.gameObject);
        }

        SceneManager.UnloadSceneAsync(SceneName);
        yield return null;

        LogAssert.ignoreFailingMessages = false;
        Assert.IsNull(ExoforgeManager.Current, "the scene's Exoforge host outlived the test");
    }

    private static T? Find<T>() where T : Component =>
        Object.FindAnyObjectByType<T>(FindObjectsInactive.Include);
}
