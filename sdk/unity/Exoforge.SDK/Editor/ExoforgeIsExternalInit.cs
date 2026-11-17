using System.IO;
using Exoforge.Management;
using UnityEditor;
using UnityEngine;

namespace Exoforge.Unity.Editor;

/// <summary>
/// Project-side half of <see cref="ExoIsExternalInit"/>: finds the Unity project root, writes the
/// polyfill and reimports it. The Studio and the setup wizard both go through here.
/// </summary>
public static class ExoforgeIsExternalInit
{
    public const string DefaultDirectory = ExoIsExternalInit.DefaultDirectory;

    public static string ProjectRoot => Path.GetFullPath(Path.Combine(Application.dataPath, ".."));

    /// <summary>The file declaring the type anywhere in <c>Assets/</c>, or null when the project has none.</summary>
    public static string? PresentPath => ExoIsExternalInit.FindInProject(ProjectRoot);

    public static string Relative(string path) => Path.GetRelativePath(ProjectRoot, path).Replace('\\', '/');

    /// <summary>Writes the file into <paramref name="directory"/> unless that assembly declares the type already.</summary>
    public static bool Ensure(string? directory, out string path)
    {
        bool created = ExoIsExternalInit.Ensure(ProjectRoot, directory, out path);
        if (created) AssetDatabase.Refresh();
        return created;
    }
}
