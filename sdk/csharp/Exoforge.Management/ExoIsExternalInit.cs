using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;

[assembly: InternalsVisibleTo("Exoforge.Management.Tests")]

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

    private static readonly Regex RecordOrInitPattern =
        new(@"\b(?:record\s+(?:(?:class|struct)\s+)?[A-Za-z_@][A-Za-z0-9_]*|init\s*(?:;|=>|\{))", RegexOptions.Compiled);

    private static StringComparison PathComparison =>
        RuntimeInformation.IsOSPlatform(OSPlatform.Windows)
            ? StringComparison.OrdinalIgnoreCase
            : StringComparison.Ordinal;

    /// <summary>The assets folder of the Unity project rooted at <paramref name="projectRoot"/>.</summary>
    public static string AssetsPath(string projectRoot) => Path.Combine(Path.GetFullPath(projectRoot), "Assets");

    /// <summary>Absolute folder to write into: <paramref name="directory"/> (absolute or project-relative), else the default.</summary>
    public static string ResolveDirectory(string projectRoot, string? directory = null)
    {
        if (string.IsNullOrWhiteSpace(directory)) directory = DefaultDirectory;
        string assetsRoot = TrimSep(Path.GetFullPath(AssetsPath(projectRoot)));
        string resolved = Path.IsPathRooted(directory)
            ? Path.GetFullPath(directory)
            : Path.GetFullPath(Path.Combine(Path.GetFullPath(projectRoot), directory!.Replace('\\', '/')));
        resolved = TrimSep(resolved);

        if (!IsPathUnderRoot(resolved, assetsRoot, PathComparison))
            throw new ArgumentException($"Target directory '{directory}' must be inside '{assetsRoot}'.", nameof(directory));

        return resolved;
    }

    private static string TrimSep(string path) =>
        path.Length > 1 ? path.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) : path;

    internal static bool IsPathUnderRoot(string path, string root, StringComparison comparison)
    {
        string normPath = TrimSep(path);
        string normRoot = TrimSep(root);
        if (string.Equals(normPath, normRoot, comparison)) return true;
        return normPath.StartsWith(normRoot + Path.DirectorySeparatorChar, comparison)
            || normPath.StartsWith(normRoot + Path.AltDirectorySeparatorChar, comparison);
    }

    /// <summary>
    /// The first file anywhere under <c>Assets/</c> that declares the type — the project-wide answer
    /// the Studio shows. Null when the project has none.
    /// </summary>
    public static string? FindInProject(string projectRoot)
        => ScanAll(AssetsPath(projectRoot));
    /// <summary>
    /// Every assembly directory (relative to <paramref name="projectRoot"/>) under <c>Assets/</c> that
    /// contains an <c>.asmdef</c>, including nested ones.
    /// </summary>
    public static IEnumerable<string> EnumerateAssemblies(string projectRoot)
    {
        string assets = AssetsPath(projectRoot);
        if (!Directory.Exists(assets)) yield break;
        foreach (string asmdef in Directory.EnumerateFiles(assets, "*.asmdef", SearchOption.AllDirectories))
        {
            yield return Path.GetRelativePath(projectRoot, Path.GetDirectoryName(asmdef)!).Replace('\\', '/');
        }
    }

    /// <summary>
    /// Whether any C# file in <paramref name="assemblyDir"/> (relative to <paramref name="projectRoot"/>)
    /// declares a <c>record</c> or an <c>init</c> accessor, so the polyfill is actually needed.
    /// </summary>
    public static bool DeclaresRecordOrInit(string projectRoot, string assemblyDir)
    {
        string root = ResolveDirectory(projectRoot, assemblyDir);
        if (!Directory.Exists(root)) return false;
        foreach (string file in Directory.EnumerateFiles(root, "*.cs"))
        {
            string text;
            try { text = File.ReadAllText(file); } catch { continue; }
            if (ContainsRecordOrInit(text)) return true;
        }
        foreach (string child in Directory.EnumerateDirectories(root))
        {
            if (HasAsmdef(child)) continue;
            string rel = Path.GetRelativePath(projectRoot, child).Replace('\\', '/');
            if (DeclaresRecordOrInit(projectRoot, rel)) return true;
        }
        return false;
    }

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
        string current = TrimSep(Path.GetFullPath(directory));
        string normAssets = TrimSep(Path.GetFullPath(assets));
        while (IsPathUnderRoot(current, normAssets, PathComparison))
        {
            if (HasAsmdef(current)) return current;
            if (string.Equals(current, normAssets, PathComparison)) break;
            string? parent = Path.GetDirectoryName(current);
            if (parent == null || parent == current) break;
            current = parent;
        }
        return normAssets;
    }

    internal static bool ContainsRecordOrInit(string source)
    {
        string stripped = StripCommentsAndLiterals(source);
        return RecordOrInitPattern.IsMatch(stripped);
    }

    /// <summary>Replaces C# comments and string/char literals (including verbatim and raw strings) with spaces.</summary>
    internal static string StripCommentsAndLiterals(string text)
    {
        var sb = new StringBuilder(text.Length);
        int i = 0;
        int n = text.Length;

        while (i < n)
        {
            char c = text[i];

            // Line comment
            if (c == '/' && i + 1 < n && text[i + 1] == '/')
            {
                i += 2;
                while (i < n && text[i] != '\n') i++;
                sb.Append(' ');
                continue;
            }

            // Block comment
            if (c == '/' && i + 1 < n && text[i + 1] == '*')
            {
                i += 2;
                while (i + 1 < n && !(text[i] == '*' && text[i + 1] == '/')) i++;
                i = i + 1 < n ? i + 2 : n;
                sb.Append(' ');
                continue;
            }

            // Raw string literal: one or more '$' followed by 3+ '"', or 3+ '"' directly
            if (c == '$' || c == '"')
            {
                int quoteStart = i;
                while (quoteStart < n && text[quoteStart] == '$') quoteStart++;
                int quoteCount = 0;
                while (quoteStart + quoteCount < n && text[quoteStart + quoteCount] == '"') quoteCount++;

                if (quoteCount >= 3)
                {
                    int j = quoteStart + quoteCount;
                    while (j < n)
                    {
                        if (text[j] == '"')
                        {
                            int closeCount = 0;
                            while (j + closeCount < n && text[j + closeCount] == '"') closeCount++;
                            if (closeCount >= quoteCount)
                            {
                                j += closeCount;
                                break;
                            }
                            j += closeCount;
                        }
                        else
                        {
                            j++;
                        }
                    }
                    i = j;
                    sb.Append(' ');
                    continue;
                }
            }

            // Verbatim string: @"...", $@"...", @$"..."
            if ((c == '@' && i + 1 < n && text[i + 1] == '"') ||
                (c == '@' && i + 2 < n && text[i + 1] == '$' && text[i + 2] == '"') ||
                (c == '$' && i + 2 < n && text[i + 1] == '@' && text[i + 2] == '"'))
            {
                i = text[i + 1] == '"' ? i + 2 : i + 3;
                while (i < n)
                {
                    if (text[i] == '"')
                    {
                        if (i + 1 < n && text[i + 1] == '"') { i += 2; continue; }
                        i++;
                        break;
                    }
                    i++;
                }
                sb.Append(' ');
                continue;
            }

            // Regular / interpolated string
            if (c == '"' || (c == '$' && i + 1 < n && text[i + 1] == '"'))
            {
                i += c == '$' ? 2 : 1;
                while (i < n)
                {
                    if (text[i] == '\\') { i += 2; continue; }
                    if (text[i] == '"') { i++; break; }
                    i++;
                }
                sb.Append(' ');
                continue;
            }

            // Char literal
            if (c == '\'')
            {
                i++;
                while (i < n)
                {
                    if (text[i] == '\\') { i += 2; continue; }
                    if (text[i] == '\'') { i++; break; }
                    i++;
                }
                sb.Append(' ');
                continue;
            }

            sb.Append(c);
            i++;
        }

        return sb.ToString();
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
