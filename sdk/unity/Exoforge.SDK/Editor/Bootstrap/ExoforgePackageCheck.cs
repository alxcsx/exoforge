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
        SanitizeStaleGeneratedStubs();
        // Deferred: the package manager is not necessarily ready during static construction.
        EditorApplication.delayCall += Check;
    }

    private static void SanitizeStaleGeneratedStubs()
    {
        try
        {
            string generatedPath = Path.Combine(Application.dataPath, "Exoforge", "Generated", "ExoforgeServices.g.cs");
            if (File.Exists(generatedPath))
            {
                string text = File.ReadAllText(generatedPath);
                if (text.Contains("global::Exoforge.Client.Unity.ExoforgeSDK.Client"))
                {
                    var lines = text.Split(new[] { "\r\n", "\r", "\n" }, System.StringSplitOptions.None);
                    var filtered = new List<string>();
                    bool insideBadBlock = false;
                    foreach (var line in lines)
                    {
                        if (line.Contains("#if UNITY_2018_1_OR_NEWER || UNITY_5_3_OR_NEWER"))
                        {
                            insideBadBlock = true;
                            continue;
                        }
                        if (insideBadBlock)
                        {
                            if (line.Contains("#endif"))
                            {
                                insideBadBlock = false;
                            }
                            continue;
                        }
                        filtered.Add(line);
                    }
                    string fixedText = string.Join("\n", filtered);
                    File.WriteAllText(generatedPath, fixedText, new System.Text.UTF8Encoding(false));
                    Debug.Log("[Exoforge] Automatically sanitized stale cross-assembly reference in Assets/Exoforge/Generated/ExoforgeServices.g.cs");
                }
            }
        }
        catch { }
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
