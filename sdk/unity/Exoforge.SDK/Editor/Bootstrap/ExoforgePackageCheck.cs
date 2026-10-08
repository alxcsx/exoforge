using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEngine;

namespace Exoforge.Unity.Editor
{
/// <summary>
/// Checks the SDK's compiled libraries are present, before anything that needs them runs.
///
/// Deliberately its own assembly with no references: every other editor script references
/// <c>ExoClient</c> and <c>ExoManagement</c>, so a missing DLL means <c>Exoforge.SDK.Editor</c> does
/// not compile — and the Exoforge menus never appear. Nothing in that assembly could report it, so
/// the check lives here, where it compiles either way.
/// </summary>
[InitializeOnLoad]
public static class ExoforgePackageCheck
{
    private const string ClientDll = "Runtime/Plugins/Exoforge.Client.dll";
    private const string ManagementDll = "Editor/Plugins/Exoforge.Management.dll";
    private const string WarnedKey = "Exoforge_PackageWarned";

    static ExoforgePackageCheck()
    {
        // Deferred: the package manager is not necessarily ready during static construction.
        EditorApplication.delayCall += Check;
    }

    private static void Check()
    {
        string? root = PackageRoot();
        if (root == null) return;

        var missing = new List<string>();

        foreach (string relative in new[] { ClientDll, ManagementDll })
        {
            if (!File.Exists(Path.Combine(root, relative))) missing.Add(relative);
        }

        if (missing.Count == 0) return;

        string message =
            "The Exoforge SDK is missing its compiled libraries:\n\n  " + string.Join("\n  ", missing) + "\n\n" +
            "Reinstall the package by dropping the com.exoforge.sdk folder into Packages/, or use " +
            "Package Manager ▸ Add package from tarball.\n\n" +
            "Working from the Exoforge repository instead? Run `just build-unity-sdk` to produce them.";

        Debug.LogError($"[Exoforge] {message}");

        // Once per editor session: a domain reload per script edit would otherwise mean a dialog per
        // script edit.
        if (SessionState.GetBool(WarnedKey, false)) return;
        SessionState.SetBool(WarnedKey, true);

        EditorUtility.DisplayDialog("Exoforge SDK is incomplete", message, "OK");
    }

    /// <summary>The package root, resolved through the package manager rather than guessed at.</summary>
    private static string? PackageRoot() =>
        UnityEditor.PackageManager.PackageInfo.FindForAssembly(typeof(ExoforgePackageCheck).Assembly)?.resolvedPath;
}
}
