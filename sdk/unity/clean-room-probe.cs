using System;
using System.IO;
using Exoforge.Management;
using Exoforge.Unity.Editor;
using UnityEditor;
using UnityEngine;

/// <summary>
/// The clean-room check: a new Unity project with the SDK installed from a tarball and no Exoforge
/// checkout anywhere near it.
///
/// Exercises exactly what a game developer does first — install the package, scaffold a plugin,
/// build it — and asserts the artifacts exist. Copied into a throwaway project by
/// <c>just clean-room-sdk</c>; not part of the shipped package.
///
/// The one thing the project cannot supply itself is <c>Exoforge.Plugin.SDK</c>, which is an
/// explicit external dependency: the check points a NuGet feed at a local pack of it, which is the
/// same shape as consuming it from nuget.org.
/// </summary>
public static class CleanRoomProbe
{
    private const string PluginName = "clean_room_plugin";

    public static void Run()
    {
        int failures = 0;

        void Check(bool condition, string message)
        {
            if (condition) return;
            failures++;
            Debug.LogError("[clean-room] FAILED: " + message);
        }

        string projectRoot = Path.GetFullPath(Path.Combine(Application.dataPath, ".."));
        Debug.Log("[clean-room] project     = " + projectRoot);
        Debug.Log("[clean-room] package     = " + ExoforgeEditorConfig.PackageRoot);
        Debug.Log("[clean-room] manifestgen = " + ExoforgeEditorConfig.ManifestGenPath);

        // 1. The package resolved from the tarball, with nothing outside it.
        Check(ExoforgeEditorConfig.PackageRoot != null, "the SDK package was not found");
        Check(ExoforgeEditorConfig.ManifestGenPath != null, "the SDK shipped without its manifest generator");

        // 2. The workspace can be created from nothing.
        var ws = ExoWorkspace.Initialize(Path.Combine(projectRoot, "Exoforge"));
        Check(File.Exists(ws.ConfigPath), "workspace config missing at " + ws.ConfigPath);
        Debug.Log("[clean-room] workspace   = " + ws.RootPath);

        // 3. A plugin can be scaffolded, and it references the published SDK explicitly.
        string pluginDir = ExoScaffolder.ScaffoldPlugin(ws.PluginsPath, PluginName);
        string csproj = Path.Combine(pluginDir, "src", PluginName + ".csproj");
        Check(File.ReadAllText(csproj).Contains("Exoforge.Plugin.SDK"),
            "the scaffolded project does not reference the SDK");

        // 4. It builds — given the SDK package on a feed, which is the external dependency.
        string? feed = Environment.GetEnvironmentVariable("EXOFORGE_TEST_FEED");

        if (!string.IsNullOrEmpty(feed))
        {
            string config =
                "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n" +
                "<configuration>\n" +
                "  <packageSources>\n" +
                "    <add key=\"exoforge\" value=\"" + feed + "\" />\n" +
                "  </packageSources>\n" +
                "</configuration>\n";

            File.WriteAllText(Path.Combine(ws.RootPath, "nuget.config"), config);
        }

        var build = new ExoDeployer(ws).BuildPlugin(
            PluginName, null, ExoforgeEditorConfig.DotnetPath,
            line => Debug.Log("[clean-room-build] " + line), ExoforgeEditorConfig.ManifestGenPath);

        Check(File.Exists(build.BinaryPath), "no binary at " + build.BinaryPath);
        Check(File.Exists(build.ManifestPath), "no manifest at " + build.ManifestPath);

        if (File.Exists(build.ManifestPath))
        {
            Check(File.ReadAllText(build.ManifestPath).Contains("id: :" + PluginName),
                "the manifest does not describe the plugin");
        }

        Debug.Log(failures == 0
            ? "[clean-room] OK: a new project installed the package and built a plugin"
            : "[clean-room] " + failures + " check(s) failed");

        EditorApplication.Exit(failures == 0 ? 0 : 1);
    }
}
