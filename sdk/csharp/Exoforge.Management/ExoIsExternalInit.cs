using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

namespace Exoforge.Management;

/// <summary>
/// The one-line <c>IsExternalInit</c> polyfill a Unity project needs before its scripts can declare
/// a <c>record</c> or an <c>init</c> setter. Unity's profile does not ship the type, so the compiler
/// fails with CS0518. The type is internal, which makes it per assembly: an asmdef that declares
/// records needs a copy in its own folder, not just in the project.
/// </summary>
public static class ExoIsExternalInit
{
    public const string FileName = "IsExternalInit.cs";

    /// <summary>Project-root-relative folder the Studio writes to when none is chosen.</summary>
    public const string DefaultDirectory = "Assets/Exoforge";

    public const string Source =
        "#if !NET5_0_OR_GREATER\n" +
        "namespace System.Runtime.CompilerServices\n" +
        "{\n" +
        "    internal static class IsExternalInit { }\n" +
        "}\n" +
        "#endif\n";

    private static readonly Regex NamespacePattern =
        new(@"\bnamespace\s+System\.Runtime\.CompilerServices\b", RegexOptions.Compiled);

    private static readonly Regex DeclarationPattern =
        new(@"\b(?:class|record|struct)\s+IsExternalInit\b", RegexOptions.Compiled);

    /// <summary>The assets folder of the Unity project rooted at <paramref name="projectRoot"/>.</summary>
    public static string AssetsPath(string projectRoot) => Path.Combine(Path.GetFullPath(projectRoot), "Assets");

    /// <summary>Absolute folder to write into: <paramref name="directory"/> (absolute or project-relative), else the default.</summary>
    public static string ResolveDirectory(string projectRoot, string? directory = null)
    {
        if (string.IsNullOrWhiteSpace(directory)) directory = DefaultDirectory;
        return Path.IsPathRooted(directory)
            ? Path.GetFullPath(directory)
            : Path.GetFullPath(Path.Combine(Path.GetFullPath(projectRoot), directory!.Replace('\\', '/')));
    }

    /// <summary>
    /// The first file anywhere under <c>Assets/</c> that declares the type — the project-wide answer
    /// the Studio shows. Null when the project has none.
    /// </summary>
    public static string? FindInProject(string projectRoot)
        => ScanAll(AssetsPath(projectRoot));

    /// <summary>
    /// The file that already declares the type in the same assembly as <paramref name="directory"/>.
    /// An assembly is the nearest ancestor folder holding an <c>.asmdef</c>, or <c>Assets/</c> when
    /// there is none; nested asmdef folders are other assemblies and are not scanned. Null when this
    /// assembly has none.
    /// </summary>
    public static string? FindInAssembly(string projectRoot, string? directory = null)
        => ScanAssembly(AssemblyRoot(AssetsPath(projectRoot), ResolveDirectory(projectRoot, directory)));

    /// <summary>
    /// Writes <see cref="FileName"/> into <paramref name="directory"/> unless that assembly already
    /// declares the type. <paramref name="path"/> is the file that exists afterwards — the newly
    /// written one, or the declaration that made this a no-op. Returns whether a file was written.
    /// </summary>
    public static bool Ensure(string projectRoot, string? directory, out string path)
    {
        string dir = ResolveDirectory(projectRoot, directory);
        path = Path.Combine(dir, FileName);

        if (File.Exists(path)) return false;

        string? existing = FindInAssembly(projectRoot, dir);
        if (existing != null)
        {
            path = existing;
            return false;
        }

        Directory.CreateDirectory(dir);
        File.WriteAllText(path, Source, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
        return true;
    }

    private static string AssemblyRoot(string assets, string directory)
    {
        string current = Path.GetFullPath(directory);
        while (current.Length >= assets.Length && current.StartsWith(assets, StringComparison.Ordinal))
        {
            if (HasAsmdef(current)) return current;
            string? parent = Path.GetDirectoryName(current);
            if (parent == null || parent == current) break;
            current = parent;
        }
        return assets;
    }

    private static bool HasAsmdef(string directory)
        => Directory.Exists(directory) && Directory.EnumerateFiles(directory, "*.asmdef").Any();

    /// <summary>Every assembly under <paramref name="directory"/>, nested asmdef folders included.</summary>
    private static string? ScanAll(string directory)
    {
        if (!Directory.Exists(directory)) return null;

        foreach (string file in Directory.EnumerateFiles(directory, "*.cs"))
        {
            if (Declares(file)) return file;
        }
        foreach (string child in Directory.EnumerateDirectories(directory))
        {
            string? hit = ScanAll(child);
            if (hit != null) return hit;
        }
        return null;
    }

    /// <summary>One assembly: its own files, descending only where no nested asmdef starts a new one.</summary>
    private static string? ScanAssembly(string directory)
    {
        if (!Directory.Exists(directory)) return null;

        foreach (string file in Directory.EnumerateFiles(directory, "*.cs"))
        {
            if (Declares(file)) return file;
        }
        foreach (string child in Directory.EnumerateDirectories(directory))
        {
            if (HasAsmdef(child)) continue;
            string? hit = ScanAssembly(child);
            if (hit != null) return hit;
        }
        return null;
    }

    private static bool Declares(string file)
    {
        string text;
        try
        {
            text = File.ReadAllText(file);
        }
        catch (IOException)
        {
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }

        return NamespacePattern.IsMatch(text) && DeclarationPattern.IsMatch(text);
    }
}
