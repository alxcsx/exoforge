using System;
using Exoforge.Management;
using UnityEditor;
using UnityEngine;

namespace Exoforge.Unity.Editor
{
    /// <summary>
    /// Places the project-root <c>exo</c> wrapper. The CLI is a development tool, not AI tooling,
    /// so unlike the agent skills this needs no opt-in; the wrapper is gitignored and path-resolving.
    /// </summary>
    public static class ExoforgeCliTools
    {
        [InitializeOnLoadMethod]
        private static void EnsureWrapper()
        {
            try
            {
                ExoCliInstaller.Install(ExoforgeEditorConfig.ProjectRoot);
            }
            catch (Exception ex)
            {
                Debug.LogWarning($"[Exoforge] Could not place the exo wrapper: {ex.Message}");
            }
        }

        [MenuItem("Exoforge/CLI/Install exo wrapper", false, 41)]
        public static void InstallWrapper()
        {
            var result = ExoCliInstaller.Install(ExoforgeEditorConfig.ProjectRoot);
            Debug.Log($"[Exoforge] exo wrapper in {result.ProjectRoot}: {result.UpdatedFiles.Count} file(s) written.");
        }
    }
}
