using Exoforge.Client.Unity;
using Exoforge.Unity.Editor;
using SnakeGame;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

/// <summary>
/// Builds the sample scene from code, so the scene is a build artifact rather than hand-edited YAML.
///
/// Idempotent: run it as often as you like. It is meant to be driven from the Unity CLI —
///
/// <code>
/// Unity -batchmode -quit -projectPath sdk/unity/sample_unity \
///       -executeMethod ExoforgeSampleSetup.SetUp
/// </code>
///
/// Produces:
/// <list type="bullet">
/// <item><c>Exoforge</c> — the SDK prefab (exactly one), carrying the runtime host.</item>
/// <item><c>Player</c> — <see cref="SnakePlayerController"/>: sign in, prompt for a name, then enable gameplay.</item>
/// <item><c>Gameplay</c> — <see cref="SnakeGameController"/>: the game. Starts inactive.</item>
/// <item><c>Hud</c> — <see cref="SnakeGameView"/> + <see cref="SnakeLeaderboard"/>: board, prompt, ranking.</item>
/// </list>
/// </summary>
public static class ExoforgeSampleSetup
{
    private const string ScenePath = "Assets/Scenes/SampleScene.unity";

    public static void SetUp()
    {
        EditorSceneManager.OpenScene(ScenePath, OpenSceneMode.Single);

        ExoforgeRuntimeConfigGenerator.Generate();

        // The runtime host: one prefab instance, never two. (Re-running an earlier setup used to
        // stack them, because the guard only checked a scene that was still loading.)
        var host = EnsureSingleHost();

        // Gameplay: the game itself, switched on once the player is signed in and named.
        var gameplayGo = EnsureObject<SnakeGameController>("Gameplay");
        var game = gameplayGo.GetComponent<SnakeGameController>();

        // The board is drawn with sprites, so it lives with the game rather than with the HUD.
        var board = gameplayGo.GetComponent<SnakeBoardView>() ?? gameplayGo.AddComponent<SnakeBoardView>();
        Wire(board, "game", game);

        gameplayGo.SetActive(false);

        // Player: session owner. Enables Gameplay when ready.
        var playerGo = EnsureObject<SnakePlayerController>("Player");
        var player = playerGo.GetComponent<SnakePlayerController>();
        WireArray(player, "enableOnReady", new Object[] { gameplayGo });

        // Hud: everything on screen. Stays active so the name prompt works before gameplay starts.
        var hudGo = EnsureObject<SnakeGameView>("Hud");
        var view = hudGo.GetComponent<SnakeGameView>();
        var ranking = hudGo.GetComponent<SnakeLeaderboard>() ?? hudGo.AddComponent<SnakeLeaderboard>();

        Wire(view, "game", game);
        Wire(view, "player", player);
        Wire(view, "leaderboard", ranking);

        Wire(ranking, "game", game);
        Wire(ranking, "player", player);

        RemoveStaleObjects();
        FrameCamera();

        var scene = EditorSceneManager.GetActiveScene();
        EditorSceneManager.MarkSceneDirty(scene);
        EditorSceneManager.SaveScene(scene);

        Debug.Log($"[ExoforgeSample] Scene built: host={host.name}, gameplay={gameplayGo.name} (inactive), " +
                  $"player={playerGo.name}, hud={hudGo.name}.");
    }

    /// <summary>Ensures exactly one Exoforge host, keeping whichever instance already exists.</summary>
    private static GameObject EnsureSingleHost()
    {
        var hosts = Object.FindObjectsByType<ExoforgeManager>(FindObjectsInactive.Include);
        GameObject? keeper = null;

        foreach (var candidate in hosts)
        {
            if (keeper == null)
            {
                keeper = candidate.gameObject;
                continue;
            }

            Debug.LogWarning($"[ExoforgeSample] Removing duplicate Exoforge host '{candidate.gameObject.name}'.");
            Object.DestroyImmediate(candidate.gameObject);
        }

        if (keeper != null)
        {
            return keeper;
        }

        ExoforgeSceneSetup.AddToScene();

        var added = Object.FindAnyObjectByType<ExoforgeManager>(FindObjectsInactive.Include);
        return added != null ? added.gameObject : new GameObject("Exoforge");
    }

    /// <summary>Finds an existing object carrying <typeparamref name="T"/> (active or not), else creates one.</summary>
    private static GameObject EnsureObject<T>(string name) where T : Component
    {
        var existing = Object.FindAnyObjectByType<T>(FindObjectsInactive.Include);
        if (existing != null)
        {
            existing.gameObject.name = name;
            return existing.gameObject;
        }

        var created = new GameObject(name);
        created.AddComponent<T>();
        return created;
    }

    private static void RemoveStaleObjects()
    {
        foreach (var stale in Object.FindObjectsByType<GameObject>(FindObjectsInactive.Include))
        {
            if (stale.name is "PlayerOnboarding" or "Onboarding")
            {
                Object.DestroyImmediate(stale);
            }
        }
    }

    /// <summary>
    /// Frames the board. One world unit per cell, centred on the origin, so the orthographic size
    /// that fits the grid is half its height.
    /// </summary>
    private static void FrameCamera()
    {
        var camera = Camera.main;
        if (camera == null) return;

        var game = Object.FindAnyObjectByType<SnakeGameController>(FindObjectsInactive.Include);
        if (game == null) return;

        camera.orthographic = true;
        camera.clearFlags = CameraClearFlags.SolidColor;
        camera.backgroundColor = new Color(0.04f, 0.05f, 0.08f);
        camera.transform.position = new Vector3(0f, 0f, -10f);

        float halfHeight = game.GridHeight / 2f + 1f;
        float halfWidth = (game.GridWidth / 2f + 1f) * ((float)Screen.width / Mathf.Max(Screen.height, 1));

        camera.orthographicSize = Mathf.Max(halfHeight, halfWidth);
    }

    private static void Wire(Component target, string field, Object? value)
    {
        var so = new SerializedObject(target);
        var property = so.FindProperty(field);

        if (property == null)
        {
            Debug.LogError($"[ExoforgeSample] {target.GetType().Name} has no field '{field}'.");
            return;
        }

        property.objectReferenceValue = value;
        so.ApplyModifiedPropertiesWithoutUndo();
    }

    private static void WireArray(Component target, string field, Object[] values)
    {
        var so = new SerializedObject(target);
        var property = so.FindProperty(field);

        if (property == null)
        {
            Debug.LogError($"[ExoforgeSample] {target.GetType().Name} has no field '{field}'.");
            return;
        }

        property.arraySize = values.Length;

        for (int i = 0; i < values.Length; i++)
        {
            property.GetArrayElementAtIndex(i).objectReferenceValue = values[i];
        }

        so.ApplyModifiedPropertiesWithoutUndo();
    }
}
