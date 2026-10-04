#if UNITY_EDITOR
using Exoforge.Client.Unity;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

namespace Exoforge.Unity.Editor;

/// <summary>
/// Adds the standard Exoforge prefab to the active scene. The prefab carries the
/// <see cref="ExoforgeBehaviour"/> that bootstraps and owns the client, so scenes never
/// need to configure cluster URLs or tokens by hand.
/// </summary>
public static class ExoforgeSceneSetup
{
    private const string PrefabName = "Exoforge";
    private const string PrefabAssetName = "Exoforge.prefab";

    [MenuItem("Tools/Exoforge/Add Exoforge to Scene", false, 104)]
    public static void AddToScene()
    {
        var prefab = FindPrefab();
        if (prefab == null)
        {
            Debug.LogError("[Exoforge] Exoforge prefab not found in the SDK package.");
            return;
        }

        if (Object.FindAnyObjectByType<ExoforgeBehaviour>() != null)
        {
            Debug.Log("[Exoforge] Scene already contains an ExoforgeBehaviour.");
            return;
        }

        var instance = (GameObject)PrefabUtility.InstantiatePrefab(prefab);
        instance.name = PrefabName;
        Undo.RegisterCreatedObjectUndo(instance, "Add Exoforge");
        EditorSceneManager.MarkSceneDirty(instance.scene);
        Selection.activeGameObject = instance;
        Debug.Log("[Exoforge] Added the Exoforge prefab to the active scene.");
    }

    /// <summary>Locates the SDK-shipped Exoforge prefab regardless of package install path.</summary>
    public static GameObject? FindPrefab()
    {
        foreach (var guid in AssetDatabase.FindAssets($"{PrefabName} t:Prefab"))
        {
            var path = AssetDatabase.GUIDToAssetPath(guid);
            if (path.EndsWith(PrefabAssetName))
            {
                return AssetDatabase.LoadAssetAtPath<GameObject>(path);
            }
        }

        return null;
    }
}
#endif
