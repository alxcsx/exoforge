using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Exoforge.Management;
using UnityEditor;
using UnityEngine;

namespace Exoforge.Unity.Editor
{
    /// <summary>
    /// Unity Editor integration for installing and checking AI agent skills, the agent guide,
    /// and the embedded Exoforge CLI.
    /// </summary>
    public static class ExoforgeAgentTools
    {
        [MenuItem("Exoforge/Agents/Install Agent Skills & CLI...", false, 40)]
        public static void InstallAgentSkillsAndCli()
        {
            string projectRoot = ExoforgeEditorConfig.ProjectRoot;
            string? packageRoot = ExoforgeEditorConfig.PackageRoot;

            try
            {
                EditorUtility.DisplayProgressBar("Exoforge Agents", "Installing agent skills and CLI wrappers...", 0.5f);

                AgentInstallResult result = ExoAgentInstaller.Install(projectRoot, "all", packageRoot);

                string skillsSummary = result.InstalledSkills != null && result.InstalledSkills.Count > 0
                    ? string.Join(", ", result.InstalledSkills)
                    : "None";

                int filesCount = result.UpdatedFiles != null ? result.UpdatedFiles.Count : 0;

                string message = $"Successfully installed Exoforge agent tooling into:\n{result.ProjectRoot}\n\n" +
                                 $"Installed Skills ({result.InstalledSkills?.Count ?? 0}):\n{skillsSummary}\n\n" +
                                 $"Updated / Created Files ({filesCount}):\n" +
                                 (result.UpdatedFiles != null && result.UpdatedFiles.Count > 0
                                     ? string.Join("\n", result.UpdatedFiles.Take(8).Select(f => "• " + Path.GetFileName(f))) +
                                       (result.UpdatedFiles.Count > 8 ? $"\n... and {result.UpdatedFiles.Count - 8} more" : "")
                                     : "• (No file changes)") + "\n\n" +
                                 $"CLI Available: {(result.CliAvailable ? "Yes" : "No")}\n" +
                                 "Configured paths: .agents/skills/, .claude/skills/, .gemini/skills/, AGENTS.md, ./exo";

                Debug.Log($"[Exoforge] Agent tooling installation complete. {filesCount} files updated in {result.ProjectRoot}");

                EditorUtility.DisplayDialog("Exoforge Agent Setup", message, "OK");
            }
            catch (Exception ex)
            {
                Debug.LogError($"[Exoforge] Failed to install agent skills and CLI: {ex.Message}\n{ex.StackTrace}");
                EditorUtility.DisplayDialog("Exoforge Agent Error", $"Failed to install agent tooling:\n\n{ex.Message}", "OK");
            }
            finally
            {
                EditorUtility.ClearProgressBar();
            }
        }

        [MenuItem("Exoforge/Agents/Check Agent Setup", false, 41)]
        public static void CheckAgentSetup()
        {
            string projectRoot = ExoforgeEditorConfig.ProjectRoot;
            string? packageRoot = ExoforgeEditorConfig.PackageRoot ?? ExoAgentInstaller.FindPackageRoot(projectRoot);

            var checks = new List<string>();
            bool allGood = true;

            // 1. Check CLI in package
            string packageCliPath = !string.IsNullOrEmpty(packageRoot)
                ? Path.Combine(packageRoot, "Editor", "Cli~", "exo.dll")
                : "";
            bool hasPackageCli = !string.IsNullOrEmpty(packageCliPath) && File.Exists(packageCliPath);
            checks.Add(hasPackageCli
                ? $"[✓] Embedded CLI binary: {packageCliPath}"
                : "[✗] Embedded CLI binary missing (expected at Editor/Cli~/exo.dll)");
            if (!hasPackageCli) allGood = false;

            // 2. Check CLI in project root
            string projectCliScript = Path.Combine(projectRoot, "exo");
            string projectCliPs = Path.Combine(projectRoot, "exo.ps1");
            string projectCliCmd = Path.Combine(projectRoot, "exo.cmd");
            bool hasProjectCli = File.Exists(projectCliScript) || File.Exists(projectCliPs) || File.Exists(projectCliCmd);
            checks.Add(hasProjectCli
                ? $"[✓] Project root CLI script: {(File.Exists(projectCliScript) ? "exo " : "")}{(File.Exists(projectCliPs) ? "exo.ps1 " : "")}{(File.Exists(projectCliCmd) ? "exo.cmd" : "")}".Trim()
                : "[!] Project root CLI wrapper not installed (run 'Install Agent Skills & CLI...')");

            // 3. Check Package Source Skills
            string packageSkillsDir = !string.IsNullOrEmpty(packageRoot)
                ? Path.Combine(packageRoot, "Agents~", "skills")
                : "";
            bool hasPackageSkills = !string.IsNullOrEmpty(packageSkillsDir) && Directory.Exists(packageSkillsDir);
            int packageSkillCount = hasPackageSkills
                ? Directory.GetDirectories(packageSkillsDir).Length
                : 0;
            checks.Add(hasPackageSkills && packageSkillCount > 0
                ? $"[✓] Bundled package skills: {packageSkillCount} found in {packageSkillsDir}"
                : "[✗] Bundled package skills missing (expected in Agents~/skills/)");
            if (!hasPackageSkills || packageSkillCount == 0) allGood = false;

            // 4. Check Project Installed Skills
            string agentsSkillsDir = Path.Combine(projectRoot, ".agents", "skills");
            string claudeSkillsDir = Path.Combine(projectRoot, ".claude", "skills");
            string geminiSkillsDir = Path.Combine(projectRoot, ".gemini", "skills");
            int installedSkillsCount = 0;
            if (Directory.Exists(agentsSkillsDir))
                installedSkillsCount = Math.Max(installedSkillsCount, Directory.GetDirectories(agentsSkillsDir).Length);
            if (Directory.Exists(claudeSkillsDir))
                installedSkillsCount = Math.Max(installedSkillsCount, Directory.GetDirectories(claudeSkillsDir).Length);
            if (Directory.Exists(geminiSkillsDir))
                installedSkillsCount = Math.Max(installedSkillsCount, Directory.GetDirectories(geminiSkillsDir).Length);

            checks.Add(installedSkillsCount > 0
                ? $"[✓] Project skills installed: {installedSkillsCount} skills found (.agents / .claude / .gemini)"
                : "[!] Project skills not yet installed into project root (.agents/skills/)");

            // 5. Check Project AGENTS.md
            string agentsMdPath = Path.Combine(projectRoot, "AGENTS.md");
            bool hasAgentsMd = File.Exists(agentsMdPath);
            checks.Add(hasAgentsMd
                ? $"[✓] Project AGENTS.md: Present at {agentsMdPath}"
                : $"[!] Project AGENTS.md: Missing from {projectRoot}");

            // Output to Unity Console
            string header = allGood
                ? "[Exoforge] Agent Setup Verification: OK"
                : "[Exoforge] Agent Setup Verification: ATTENTION REQUIRED";

            string fullReport = $"{header}\nProject Root: {projectRoot}\nPackage Root: {packageRoot ?? "(Not found)"}\n\n" +
                                string.Join("\n", checks);

            if (allGood)
            {
                Debug.Log(fullReport);
            }
            else
            {
                Debug.LogWarning(fullReport);
            }

            // Display Dialog Summary
            string dialogSummary = $"Exoforge Agent Setup Status: {(allGood ? "Ready" : "Incomplete")}\n\n" +
                                   $"• Embedded CLI: {(hasPackageCli ? "Found" : "Missing")}\n" +
                                   $"• Project Wrapper: {(hasProjectCli ? "Found" : "Not Installed")}\n" +
                                   $"• Bundled Skills: {packageSkillCount} in package\n" +
                                   $"• Installed Skills: {installedSkillsCount} in project\n" +
                                   $"• Project AGENTS.md: {(hasAgentsMd ? "Present" : "Missing")}\n\n" +
                                   "Detailed report logged to Unity Console.";

            EditorUtility.DisplayDialog("Exoforge Agent Setup Check", dialogSummary, "OK");
        }
    }
}
