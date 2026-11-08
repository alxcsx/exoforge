using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using UnityEditor;
using UnityEngine;

namespace Exoforge.Unity.Editor
{
    /// <summary>
    /// Configures Unity project generation and solution files for JetBrains Rider and external IDEs.
    ///
    /// Addresses Rider autocomplete and compiler check issues:
    /// 1. Ensures Unity's <c>unity_project_generation_flag</c> has <c>LocalTarBall</c> (128) and local package
    ///    flags enabled so Unity generates full <c>.csproj</c> projects for tarball-imported packages.
    /// 2. Ensures <c>nuget.config</c> is configured in the workspace pointing to the bundled <c>NuGet~</c> feed,
    ///    allowing Rider to restore <c>Exoforge.Plugin.SDK</c> for backend C# extensions.
    /// 3. Injects backend C# extensions from <c>Exoforge/extensions/*/*.csproj</c> into the Unity <c>.sln</c>
    ///    under an "Exoforge Extensions" solution folder so developers have code completion, navigation,
    ///    and compiler checks for both client and backend code in the same IDE window.
    /// 4. Ensures <c>Exoforge.Client.dll</c> and <c>Exoforge.Management.dll</c> assembly references are
    ///    present with valid HintPaths in consuming project files.
    /// </summary>
    [InitializeOnLoad]
    public class ExoforgeIdeProjectGenerator : AssetPostprocessor
    {
        private const string ProjectGenerationFlagKey = "unity_project_generation_flag";

        // Unity ProjectGenerationFlag mask:
        // None = 0, Embedded = 1, Local = 2, Registry = 4, Git = 8, BuiltIn = 16, Unknown = 32, PlayerAssemblies = 64, LocalTarBall = 128
        private const int RequiredFlags = 1 | 2 | 4 | 8 | 16 | 128; // 159

        private const string FolderGuid = "{E0F0E0F0-E0F0-E0F0-E0F0-E0F0E0F0E0F0}";
        private const string FolderTypeGuid = "{2150E333-8FDC-42A3-9474-1A3956D46DE8}";
        private const string CSharpProjectTypeGuid = "{9A19103F-16F7-4668-BE54-9A1E7A4F7556}";

        static ExoforgeIdeProjectGenerator()
        {
            EditorApplication.delayCall += () =>
            {
                EnsureIdeConfiguration(forceRegenerate: false);
            };
        }

        /// <summary>
        /// Validates and ensures IDE project generation flags, workspace nuget feeds, and project files.
        /// </summary>
        public static bool EnsureIdeConfiguration(bool forceRegenerate = false)
        {
            bool changed = EnsureProjectGenerationFlags();
            changed |= EnsureWorkspaceNugetConfig();

            if (forceRegenerate || changed)
            {
                RegenerateProjectFiles();
            }

            return changed;
        }

        /// <summary>
        /// Ensures Unity EditorPrefs includes LocalTarBall and local package generation flags.
        /// </summary>
        public static bool EnsureProjectGenerationFlags()
        {
            int current = EditorPrefs.GetInt(ProjectGenerationFlagKey, 3);
            if ((current & 128) == 0 || (current & 8) == 0 || (current & 4) == 0)
            {
                int updated = current | RequiredFlags;
                EditorPrefs.SetInt(ProjectGenerationFlagKey, updated);
                Debug.Log($"[Exoforge] Configured Unity IDE project generation flags (from {current} to {updated}) to enable .csproj generation for package tarballs and external sources.");
                return true;
            }

            return false;
        }

        /// <summary>
        /// Ensures nuget.config exists in the Exoforge workspace pointing to the local package feed.
        /// </summary>
        public static bool EnsureWorkspaceNugetConfig()
        {
            try
            {
                string? feedPath = ExoforgeEditorConfig.BundledFeedPath;
                if (string.IsNullOrEmpty(feedPath) || !Directory.Exists(feedPath))
                {
                    return false;
                }

                string wsPath = ExoforgeEditorConfig.GetAbsoluteWorkspacePath();
                if (!Directory.Exists(wsPath))
                {
                    Directory.CreateDirectory(wsPath);
                }

                string nugetPath = Path.Combine(wsPath, "nuget.config");
                string expectedFeed = feedPath!.Replace('\\', '/');
                string expectedContent =
                    "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n" +
                    "<configuration>\n" +
                    "  <!-- Local packages feed for Exoforge extensions -->\n" +
                    "  <packageSources>\n" +
                    $"    <add key=\"exoforge\" value=\"{expectedFeed}\" />\n" +
                    "  </packageSources>\n" +
                    "</configuration>\n";

                if (!File.Exists(nugetPath) || !File.ReadAllText(nugetPath).Contains(expectedFeed))
                {
                    File.WriteAllText(nugetPath, expectedContent);
                    return true;
                }
            }
            catch (Exception ex)
            {
                Debug.LogWarning($"[Exoforge] Failed to configure workspace nuget.config: {ex.Message}");
            }

            return false;
        }

        /// <summary>
        /// Triggers solution and project file regeneration in Unity.
        /// </summary>
        public static void RegenerateProjectFiles()
        {
            try
            {
                var syncVsType = typeof(EditorApplication).Assembly.GetType("UnityEditor.SyncVS");
                var syncMethod = syncVsType?.GetMethod("SyncSolution",
                    System.Reflection.BindingFlags.Public |
                    System.Reflection.BindingFlags.NonPublic |
                    System.Reflection.BindingFlags.Static);
                if (syncMethod != null)
                {
                    syncMethod.Invoke(null, null);
                    return;
                }
            }
            catch { }

            try
            {
                UnityEditor.Compilation.CompilationPipeline.RequestScriptCompilation();
            }
            catch { }
        }

        private static string OnGeneratedSlnSolution(string path, string content)
        {
            try
            {
                string wsPath = ExoforgeEditorConfig.GetAbsoluteWorkspacePath();
                string extDir = Path.Combine(wsPath, "extensions");
                if (!Directory.Exists(extDir)) return content;

                var csprojFiles = Directory.GetFiles(extDir, "*.csproj", SearchOption.AllDirectories);
                if (csprojFiles.Length == 0) return content;

                string projectRoot = ExoforgeEditorConfig.ProjectRoot;
                var sbProjects = new StringBuilder();
                var sbConfigs = new StringBuilder();
                var sbNested = new StringBuilder();

                bool hasFolder = content.Contains(FolderGuid);
                if (!hasFolder)
                {
                    sbProjects.AppendLine($"Project(\"{FolderTypeGuid}\") = \"Exoforge Extensions\", \"Exoforge Extensions\", \"{FolderGuid}\"");
                    sbProjects.AppendLine("EndProject");
                }

                bool anyAdded = false;
                foreach (var csproj in csprojFiles)
                {
                    string fileName = Path.GetFileName(csproj);
                    if (content.Contains(fileName)) continue;

                    string projName = Path.GetFileNameWithoutExtension(csproj);
                    string relPath = MakeRelativePath(projectRoot, csproj).Replace('/', '\\');
                    string projGuid = ComputeDeterministicGuid(relPath).ToString("B").ToUpperInvariant();

                    sbProjects.AppendLine($"Project(\"{CSharpProjectTypeGuid}\") = \"{projName}\", \"{relPath}\", \"{projGuid}\"");
                    sbProjects.AppendLine("EndProject");

                    sbConfigs.AppendLine($"\t\t{projGuid}.Debug|Any CPU.ActiveCfg = Debug|Any CPU");
                    sbConfigs.AppendLine($"\t\t{projGuid}.Debug|Any CPU.Build.0 = Debug|Any CPU");
                    sbConfigs.AppendLine($"\t\t{projGuid}.Release|Any CPU.ActiveCfg = Release|Any CPU");
                    sbConfigs.AppendLine($"\t\t{projGuid}.Release|Any CPU.Build.0 = Release|Any CPU");

                    sbNested.AppendLine($"\t\t{projGuid} = {FolderGuid}");
                    anyAdded = true;
                }

                if (!anyAdded && hasFolder) return content;

                // Inject projects right before the Global section
                int globalIdx = content.IndexOf("Global\n", StringComparison.Ordinal);
                if (globalIdx < 0) globalIdx = content.IndexOf("Global\r\n", StringComparison.Ordinal);
                if (globalIdx > 0 && sbProjects.Length > 0)
                {
                    content = content.Insert(globalIdx, sbProjects.ToString());
                }

                // Inject project configuration mappings
                int projCfgIdx = content.IndexOf("GlobalSection(ProjectConfigurationPlatforms) = postSolution", StringComparison.Ordinal);
                if (projCfgIdx > 0 && sbConfigs.Length > 0)
                {
                    int nextLine = content.IndexOf('\n', projCfgIdx);
                    if (nextLine > 0)
                    {
                        content = content.Insert(nextLine + 1, sbConfigs.ToString());
                    }
                }

                // Inject nested project folder associations
                if (sbNested.Length > 0)
                {
                    int nestedIdx = content.IndexOf("GlobalSection(NestedProjects) = preSolution", StringComparison.Ordinal);
                    if (nestedIdx > 0)
                    {
                        int nextLine = content.IndexOf('\n', nestedIdx);
                        if (nextLine > 0)
                        {
                            content = content.Insert(nextLine + 1, sbNested.ToString());
                        }
                    }
                    else
                    {
                        int endGlobalIdx = content.LastIndexOf("\nEndGlobal", StringComparison.Ordinal);
                        if (endGlobalIdx < 0) endGlobalIdx = content.LastIndexOf("\r\nEndGlobal", StringComparison.Ordinal);
                        if (endGlobalIdx >= 0)
                        {
                            int insertAt = content.IndexOf("EndGlobal", endGlobalIdx, StringComparison.Ordinal);
                            if (insertAt >= 0)
                            {
                                string nestedBlock =
                                    "\tGlobalSection(NestedProjects) = preSolution\n" +
                                    sbNested.ToString() +
                                    "\tEndGlobalSection\n";
                                content = content.Insert(insertAt, nestedBlock);
                            }
                        }
                    }
                }

                return content;
            }
            catch (Exception ex)
            {
                Debug.LogWarning($"[Exoforge] Failed to post-process .sln solution: {ex.Message}");
                return content;
            }
        }

        private static string OnGeneratedCSProject(string path, string content)
        {
            try
            {
                string? pkgRoot = ExoforgeEditorConfig.PackageRoot;
                if (string.IsNullOrEmpty(pkgRoot)) return content;

                string fileName = Path.GetFileName(path);

                // Inject Exoforge.Client reference if missing from consuming game / generated projects
                if (!content.Contains("Exoforge.Client"))
                {
                    string clientDll = Path.Combine(pkgRoot!, "Runtime", "Plugins", "Exoforge.Client.dll");
                    if (File.Exists(clientDll))
                    {
                        string normPath = Path.GetFullPath(clientDll).Replace('\\', '/');
                        string refXml =
                            $"    <Reference Include=\"Exoforge.Client\">\n" +
                            $"      <HintPath>{normPath}</HintPath>\n" +
                            $"    </Reference>\n";

                        int endItemGrp = content.IndexOf("</ItemGroup>", StringComparison.Ordinal);
                        if (endItemGrp > 0)
                        {
                            content = content.Insert(endItemGrp, refXml);
                        }
                    }
                }

                // For editor projects, inject Exoforge.Management reference if missing
                if (fileName.Contains("Editor") && !content.Contains("Exoforge.Management"))
                {
                    string mgmtDll = Path.Combine(pkgRoot!, "Editor", "Plugins", "Exoforge.Management.dll");
                    if (File.Exists(mgmtDll))
                    {
                        string normPath = Path.GetFullPath(mgmtDll).Replace('\\', '/');
                        string refXml =
                            $"    <Reference Include=\"Exoforge.Management\">\n" +
                            $"      <HintPath>{normPath}</HintPath>\n" +
                            $"    </Reference>\n";

                        int endItemGrp = content.IndexOf("</ItemGroup>", StringComparison.Ordinal);
                        if (endItemGrp > 0)
                        {
                            content = content.Insert(endItemGrp, refXml);
                        }
                    }
                }

                return content;
            }
            catch
            {
                return content;
            }
        }

        [MenuItem("Exoforge/IDE & Solution/Regenerate C# Projects for Rider", false, 30)]
        public static void MenuRegenerateProjects()
        {
            EnsureIdeConfiguration(forceRegenerate: true);
            EditorUtility.DisplayDialog(
                "Exoforge IDE Integration",
                "C# project and solution files have been synchronized for JetBrains Rider.\n\n" +
                "• LocalTarBall and package sources enabled in project generation.\n" +
                "• Workspace nuget.config configured for Exoforge.Plugin.SDK.\n" +
                "• Backend extensions and library references verified.",
                "OK");
        }

        [MenuItem("Exoforge/IDE & Solution/Configure Rider Project Generation Flags", false, 31)]
        public static void MenuConfigureFlags()
        {
            bool updated = EnsureProjectGenerationFlags();
            if (updated)
            {
                RegenerateProjectFiles();
                EditorUtility.DisplayDialog(
                    "Exoforge IDE Integration",
                    "Project generation flags updated to include LocalTarBall (128).\nSolution regenerated.",
                    "OK");
            }
            else
            {
                EditorUtility.DisplayDialog(
                    "Exoforge IDE Integration",
                    "Project generation flags are already configured correctly with LocalTarBall support.",
                    "OK");
            }
        }

        private static Guid ComputeDeterministicGuid(string input)
        {
            using var md5 = MD5.Create();
            byte[] hash = md5.ComputeHash(Encoding.UTF8.GetBytes(input));
            return new Guid(hash);
        }

        private static string MakeRelativePath(string fromPath, string toPath)
        {
            if (string.IsNullOrEmpty(fromPath)) return toPath;
            var fromUri = new Uri(AppendSlash(Path.GetFullPath(fromPath)));
            var toUri = new Uri(Path.GetFullPath(toPath));
            var relUri = fromUri.MakeRelativeUri(toUri);
            return Uri.UnescapeDataString(relUri.ToString());
        }

        private static string AppendSlash(string path) =>
            path.EndsWith(Path.DirectorySeparatorChar.ToString()) ? path : path + Path.DirectorySeparatorChar;
    }
}
