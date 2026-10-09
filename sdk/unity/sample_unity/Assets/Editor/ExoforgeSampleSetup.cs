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
    private const string OfflineScenePath = "Assets/Scenes/SnakeGame_Offline.unity";
    private const string ExoforgeScenePath = "Assets/Scenes/SnakeGame_Exoforge.unity";

    public static void SetUp()
    {
        SetUpOffline();
        SetUpExoforge();
        // Also update the legacy SampleScene for compatibility with existing tests
        SetUpExoforgeScene(ScenePath);
        UpdateEditorBuildSettings();
    }

    public static void SetUpOffline()
    {
        SetUpOfflineScene(OfflineScenePath);
    }

    public static void SetUpExoforge()
    {
        SetUpExoforgeScene(ExoforgeScenePath);
    }

    private static void SetUpOfflineScene(string path)
    {
        var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);

        // Camera & Light
        CreateCamera();
        CreateLight();

        // Gameplay: always active in offline scene
        var gameplayGo = new GameObject("Gameplay");
        var game = gameplayGo.AddComponent<SnakeGameController>();
        var board = gameplayGo.AddComponent<SnakeBoardView>();
        Wire(board, "game", game);
        gameplayGo.SetActive(true);

        // Hud: view only, no leaderboard
        var hudGo = new GameObject("Hud");
        var view = hudGo.AddComponent<SnakeGameView>();
        Wire(view, "game", game);

        FrameCamera();

        EditorSceneManager.SaveScene(scene, path);
        Debug.Log($"[ExoforgeSample] Offline scene built: {path}");
    }

    private static void SetUpExoforgeScene(string path)
    {
        var scene = System.IO.File.Exists(path)
            ? EditorSceneManager.OpenScene(path, OpenSceneMode.Single)
            : EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);

        ExoforgeRuntimeConfigGenerator.Generate();

        CreateCamera();
        CreateLight();

        // The runtime host
        var host = EnsureSingleHost();

        // Gameplay: game + board + remote config
        var gameplayGo = EnsureObject<SnakeGameController>("Gameplay");
        var game = gameplayGo.GetComponent<SnakeGameController>();
        var board = gameplayGo.GetComponent<SnakeBoardView>() ?? gameplayGo.AddComponent<SnakeBoardView>();
        var remoteConfig = gameplayGo.GetComponent<SnakeRemoteConfig>() ?? gameplayGo.AddComponent<SnakeRemoteConfig>();

        Wire(board, "game", game);
        Wire(remoteConfig, "game", game);
        Wire(remoteConfig, "boardView", board);

        gameplayGo.SetActive(false);

        // Player: session owner. Enables Gameplay when ready.
        var playerGo = EnsureObject<SnakePlayerController>("Player");
        var player = playerGo.GetComponent<SnakePlayerController>();
        WireArray(player, "enableOnReady", new Object[] { gameplayGo });

        // Hud: view + leaderboard
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

        EditorSceneManager.MarkSceneDirty(scene);
        EditorSceneManager.SaveScene(scene, path);

        Debug.Log($"[ExoforgeSample] Exoforge scene built: {path} with host={host.name}, remoteConfig={remoteConfig.name}.");
    }

    private static void UpdateEditorBuildSettings()
    {
        var scenes = new EditorBuildSettingsScene[]
        {
            new EditorBuildSettingsScene(OfflineScenePath, true),
            new EditorBuildSettingsScene(ExoforgeScenePath, true),
            new EditorBuildSettingsScene(ScenePath, true)
        };
        EditorBuildSettings.scenes = scenes;
    }

    private static void CreateCamera()
    {
        var cam = Camera.main;
        if (cam == null)
        {
            var camGo = new GameObject("Main Camera");
            camGo.tag = "MainCamera";
            cam = camGo.AddComponent<Camera>();
            camGo.AddComponent<AudioListener>();
        }
    }

    private static void CreateLight()
    {
        var lights = Object.FindObjectsByType<Light>(FindObjectsInactive.Include);
        if (lights.Length == 0)
        {
            var lightGo = new GameObject("Directional Light");
            var l = lightGo.AddComponent<Light>();
            l.type = LightType.Directional;
            l.intensity = 1f;
        }
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
