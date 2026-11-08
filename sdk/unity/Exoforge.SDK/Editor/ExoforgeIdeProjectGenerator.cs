using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using Exoforge.Management;
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
                    "  <!-- Package feeds for Exoforge extensions: official nuget.org for runtime packs + local feed -->\n" +
                    "  <packageSources>\n" +
                    "    <add key=\"nuget.org\" value=\"https://api.nuget.org/v3/index.json\" protocolVersion=\"3\" />\n" +
                    $"    <add key=\"exoforge\" value=\"{expectedFeed}\" />\n" +
                    "  </packageSources>\n" +
                    "</configuration>\n";

                bool changed = false;
                if (!File.Exists(nugetPath) || !File.ReadAllText(nugetPath).Contains(expectedFeed) || !File.ReadAllText(nugetPath).Contains("https://api.nuget.org/v3/index.json"))
                {
                    File.WriteAllText(nugetPath, expectedContent);
                    changed = true;
                }

                string extDir = Path.Combine(wsPath, "extensions");
                if (Directory.Exists(extDir))
                {
                    var extensionProjects = new List<(string Name, string RelativeCsprojPath)>();

                    foreach (string dir in Directory.GetDirectories(extDir))
                    {
                        string extNuget = Path.Combine(dir, "nuget.config");
                        if (!File.Exists(extNuget) || !File.ReadAllText(extNuget).Contains(expectedFeed) || !File.ReadAllText(extNuget).Contains("https://api.nuget.org/v3/index.json"))
                        {
                            File.WriteAllText(extNuget, expectedContent);
                            changed = true;
                        }

                        string extName = Path.GetFileName(dir);
                        string extSln = Path.Combine(dir, $"{extName}.sln");
                        string extSlnx = Path.Combine(dir, $"{extName}.slnx");
                        string extCsproj = Path.Combine(dir, "src", $"{extName}.csproj");

                        // Prefer standard .sln format for wider compatibility; clean up legacy .slnx
                        if (File.Exists(extSlnx))
                        {
                            try { File.Delete(extSlnx); changed = true; } catch { }
                            string slnxMeta = extSlnx + ".meta";
                            if (File.Exists(slnxMeta))
                            {
                                try { File.Delete(slnxMeta); } catch { }
                            }
                        }

                        if (File.Exists(extCsproj))
                        {
                            if (!File.Exists(extSln))
                            {
                                File.WriteAllText(extSln, ExoScaffolder.GenerateSln(extName));
                                changed = true;
                            }

                            extensionProjects.Add((extName, Path.Combine(extName, "src", $"{extName}.csproj")));
                        }
                    }

                    // Maintain an independent master solution for backend extensions:
                    // Exoforge/extensions/Exoforge.Extensions.sln
                    // Opening this solution in Rider or VS Code gives full .NET 9+ / .NET 10 SDK support
                    // completely decoupled from Unity's Mono / MSBuild toolset.
                    if (extensionProjects.Count > 0)
                    {
                        string masterSln = Path.Combine(extDir, "Exoforge.Extensions.sln");
                        string masterContent = GenerateMasterExtensionsSln(extensionProjects);
                        if (!File.Exists(masterSln) || File.ReadAllText(masterSln) != masterContent)
                        {
                            File.WriteAllText(masterSln, masterContent);
                            changed = true;
                        }
                    }
                }

                return changed;
            }
            catch (Exception ex)
            {
                Debug.LogWarning($"[Exoforge] Failed to configure workspace nuget.config & solutions: {ex.Message}");
            }

            return false;
        }

        /// <summary>
        /// Generates a standalone Visual Studio solution (.sln) combining all backend extensions.
        /// When opened in Rider/VS, this solution runs under the modern .NET SDK (net9.0/net10.0)
        /// without any Unity-imposed language or toolchain constraints.
        /// </summary>
        public static string GenerateMasterExtensionsSln(IEnumerable<(string Name, string RelativeCsprojPath)> projects)
        {
            var sb = new StringBuilder();
            sb.AppendLine("Microsoft Visual Studio Solution File, Format Version 12.00");
            sb.AppendLine("# Visual Studio Version 17");
            sb.AppendLine("VisualStudioVersion = 17.0.31903.59");
            sb.AppendLine("MinimumVisualStudioVersion = 10.0.40219.1");

            var configs = new List<(string Guid, string Name)>();
            foreach (var (name, relPath) in projects)
            {
                string guid = ComputeDeterministicGuid(relPath).ToString("B").ToUpperInvariant();
                configs.Add((guid, name));
                string normRel = relPath.Replace('/', '\\');
                sb.AppendLine($"Project(\"{{9A19103F-16F7-4668-BE54-9A1E7A4F7556}}\") = \"{name}\", \"{normRel}\", \"{guid}\"");
                sb.AppendLine("EndProject");
            }

            sb.AppendLine("Global");
            sb.AppendLine("\tGlobalSection(SolutionConfigurationPlatforms) = preSolution");
            sb.AppendLine("\t\tDebug|Any CPU = Debug|Any CPU");
            sb.AppendLine("\t\tRelease|Any CPU = Release|Any CPU");
            sb.AppendLine("\tEndGlobalSection");
            sb.AppendLine("\tGlobalSection(ProjectConfigurationPlatforms) = postSolution");
            foreach (var (guid, _) in configs)
            {
                sb.AppendLine($"\t\t{guid}.Debug|Any CPU.ActiveCfg = Debug|Any CPU");
                sb.AppendLine($"\t\t{guid}.Debug|Any CPU.Build.0 = Debug|Any CPU");
                sb.AppendLine($"\t\t{guid}.Release|Any CPU.ActiveCfg = Release|Any CPU");
                sb.AppendLine($"\t\t{guid}.Release|Any CPU.Build.0 = Release|Any CPU");
            }
            sb.AppendLine("\tEndGlobalSection");
            sb.AppendLine("\tGlobalSection(SolutionProperties) = preSolution");
            sb.AppendLine("\t\tHideSolutionNode = FALSE");
            sb.AppendLine("\tEndGlobalSection");
            sb.AppendLine("EndGlobal");
            return sb.ToString();
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
            // Do NOT inject backend extensions into the Unity .sln solution.
            // When backend projects are embedded inside Unity's solution, Rider's Unity plugin
            // treats them as Unity projects and enforces Unity's Mono/MSBuild toolset,
            // which rejects modern .NET 9+ / .NET 10 language features and SDKs.
            if (!content.Contains(FolderGuid) && !content.Contains("Exoforge Extensions"))
            {
                return content;
            }

            try
            {
                return StripExoforgeExtensionsFromSln(content);
            }
            catch (Exception ex)
            {
                Debug.LogWarning($"[Exoforge] Failed to clean Unity .sln solution: {ex.Message}");
                return content;
            }
        }

        internal static string StripExoforgeExtensionsFromSln(string content)
        {
            var lines = content.Split(new[] { "\r\n", "\n" }, StringSplitOptions.None);
            var result = new List<string>(lines.Length);
            bool inExoProject = false;

            foreach (string line in lines)
            {
                if (line.StartsWith("Project(") &&
                    (line.Contains(FolderGuid) ||
                     line.Contains("Exoforge Extensions") ||
                     (line.Contains("Exoforge") && line.Contains(".csproj"))))
                {
                    inExoProject = true;
                    continue;
                }

                if (inExoProject)
                {
                    if (line.Trim() == "EndProject")
                    {
                        inExoProject = false;
                    }
                    continue;
                }

                if (line.Contains(FolderGuid)) continue;
                if (line.Contains("Exoforge Extensions")) continue;

                result.Add(line);
            }

            return string.Join("\n", result);
        }

        private static string OnGeneratedCSProject(string path, string content)
        {
            try
            {
                string? pkgRoot = ExoforgeEditorConfig.PackageRoot;
                if (string.IsNullOrEmpty(pkgRoot)) return content;

                string fileName = Path.GetFileName(path);
                string projectRoot = Path.GetFullPath(Path.Combine(Application.dataPath, ".."));

                // 1. Inject Exoforge.Client reference if missing from consuming game / generated projects
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

                // 2. Inject Exoforge.Generated project reference if missing from game projects
                string genCsproj = Path.Combine(projectRoot, "Exoforge.Generated.csproj");
                if (!fileName.StartsWith("Exoforge.", StringComparison.OrdinalIgnoreCase) &&
                    File.Exists(genCsproj) &&
                    !content.Contains("Exoforge.Generated"))
                {
                    string genGuid = ComputeDeterministicGuid("Exoforge.Generated.csproj").ToString("B").ToUpperInvariant();
                    string projRef =
                        $"    <ProjectReference Include=\"Exoforge.Generated.csproj\">\n" +
                        $"      <Project>{genGuid}</Project>\n" +
                        $"      <Name>Exoforge.Generated</Name>\n" +
                        $"    </ProjectReference>\n";

                    int endItemGrp = content.IndexOf("</ItemGroup>", StringComparison.Ordinal);
                    if (endItemGrp > 0)
                    {
                        content = content.Insert(endItemGrp, projRef);
                    }
                }

                // 3. For Exoforge.Generated.csproj itself, ensure Exoforge.Client and System.Text.Json are referenced
                if (fileName.Equals("Exoforge.Generated.csproj", StringComparison.OrdinalIgnoreCase))
                {
                    var sbMissing = new StringBuilder();
                    string clientDll = Path.Combine(pkgRoot!, "Runtime", "Plugins", "Exoforge.Client.dll");
                    string jsonDll = Path.Combine(pkgRoot!, "Runtime", "Plugins", "System.Text.Json.dll");

                    if (!content.Contains("Exoforge.Client") && File.Exists(clientDll))
                    {
                        string normClient = Path.GetFullPath(clientDll).Replace('\\', '/');
                        sbMissing.AppendLine($"    <Reference Include=\"Exoforge.Client\">\n      <HintPath>{normClient}</HintPath>\n    </Reference>");
                    }
                    if (!content.Contains("System.Text.Json") && File.Exists(jsonDll))
                    {
                        string normJson = Path.GetFullPath(jsonDll).Replace('\\', '/');
                        sbMissing.AppendLine($"    <Reference Include=\"System.Text.Json\">\n      <HintPath>{normJson}</HintPath>\n    </Reference>");
                    }

                    if (sbMissing.Length > 0)
                    {
                        int endItemGrp = content.IndexOf("</ItemGroup>", StringComparison.Ordinal);
                        if (endItemGrp > 0)
                        {
                            content = content.Insert(endItemGrp, sbMissing.ToString());
                        }
                    }
                }

                // 4. For editor projects, inject Exoforge.Management reference if missing
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

        [MenuItem("Exoforge/IDE & Solution/Open Backend Extensions in Rider or IDE ↗", false, 32)]
        public static void MenuOpenExtensionsSolution()
        {
            string wsPath = ExoforgeEditorConfig.GetAbsoluteWorkspacePath();
            string extDir = Path.Combine(wsPath, "extensions");
            string masterSln = Path.Combine(extDir, "Exoforge.Extensions.sln");

            EnsureWorkspaceNugetConfig();

            if (File.Exists(masterSln))
            {
                EditorUtility.OpenWithDefaultApp(masterSln);
                return;
            }

            var slnFiles = Directory.Exists(extDir) ? Directory.GetFiles(extDir, "*.sln", SearchOption.AllDirectories) : Array.Empty<string>();
            if (slnFiles.Length > 0)
            {
                EditorUtility.OpenWithDefaultApp(slnFiles[0]);
                return;
            }

            EditorUtility.DisplayDialog("Exoforge Extensions", "No C# backend extensions found in " + extDir, "OK");
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
