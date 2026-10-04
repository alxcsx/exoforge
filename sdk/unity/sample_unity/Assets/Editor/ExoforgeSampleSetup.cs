using Exoforge.Unity.Editor;
using SnakeGame;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

/// <summary>
/// One-shot sample bootstrap: generates the runtime config from exoforge.json, adds the
/// standard Exoforge prefab, and drops the SnakeGameController into the sample scene.
/// Run via Unity CLI: -executeMethod ExoforgeSampleSetup.SetUp
/// </summary>
public static class ExoforgeSampleSetup
{
    private const string ScenePath = "Assets/Scenes/SampleScene.unity";

    public static void SetUp()
    {
        EditorSceneManager.OpenScene(ScenePath, OpenSceneMode.Single);

        ExoforgeRuntimeConfigGenerator.Generate();
        ExoforgeSceneSetup.AddToScene();

        var scene = EditorSceneManager.GetActiveScene();

        // Remove the superseded onboarding object if an earlier setup created one.
        foreach (var stale in Object.FindObjectsByType<GameObject>(FindObjectsInactive.Include, FindObjectsSortMode.None))
        {
            if (stale.name == "PlayerOnboarding")
            {
                Object.DestroyImmediate(stale);
            }
        }

        // Gameplay root: starts inactive and is enabled once onboarding has a session.
        var existing = Object.FindAnyObjectByType<SnakeGameController>(FindObjectsInactive.Include);
        GameObject gameplayGo;
        if (existing != null)
        {
            gameplayGo = existing.gameObject;
            gameplayGo.name = "Gameplay";
        }
        else
        {
            gameplayGo = new GameObject("Gameplay");
            gameplayGo.AddComponent<SnakeGameController>();
        }

        gameplayGo.SetActive(false);

        // Player session: authenticates, registers an anonymous player, assigns the display name.
        if (Object.FindAnyObjectByType<SnakePlayerController>(FindObjectsInactive.Include) == null)
        {
            var playerGo = new GameObject("Player");
            var player = playerGo.AddComponent<SnakePlayerController>();

            var so = new SerializedObject(player);
            var targets = so.FindProperty("enableOnReady");
            targets.arraySize = 1;
            targets.GetArrayElementAtIndex(0).objectReferenceValue = gameplayGo;
            so.ApplyModifiedProperties();
        }

        EditorSceneManager.MarkSceneDirty(scene);
        EditorSceneManager.SaveScene(scene);
        Debug.Log("[ExoforgeSample] Setup complete.");
    }
}
