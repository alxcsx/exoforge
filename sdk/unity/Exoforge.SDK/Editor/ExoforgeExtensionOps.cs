#nullable enable
using System;
using UnityEditor;
using UnityEngine;
using UnityEngine.UIElements;

namespace Exoforge.Unity.Editor
{
    /// <summary>How a status message should look and be logged. One scale for every window, so a success never looks like a warning.</summary>
    public enum StatusSeverity { Success, Info, Warning, Error }

    /// <summary>
    /// What the two extension windows have in common: which runtime to build for, what a failed build or deploy
    /// looks like to the developer, and the check before anything goes to a server that is not this machine.
    /// One place, because each window once carried its own copy and they disagreed (one built for the host
    /// whenever it was offline, and a later deploy uploaded that build).
    /// </summary>
    public static class ExoforgeExtensionOps
    {
        /// <summary>
        /// The runtime identifier to build for. An explicit choice wins; otherwise a build that will be deployed
        /// targets the server's runtime (the one it reports, else the standard Linux one), and a build that will
        /// not be deployed targets this machine.
        /// </summary>
        public static string ResolveRid(string? overrideRid, string? configuredRid, bool forServer, string? serverReportedRid)
        {
            static string? Explicit(string? rid) =>
                string.IsNullOrWhiteSpace(rid) || string.Equals(rid!.Trim(), "auto", StringComparison.OrdinalIgnoreCase) ? null : rid!.Trim();

            string? chosen = Explicit(overrideRid) ?? Explicit(configuredRid);
            if (chosen != null) return chosen;

            if (forServer)
            {
                return string.IsNullOrWhiteSpace(serverReportedRid) ? ExoforgeDotnetValidator.StandardServerRid : serverReportedRid!;
            }

            return Exoforge.Management.ExoDeployer.HostRuntimeIdentifier();
        }

        public static string BuildFailureKey(string extension) => $"Exoforge_BuildFailed_{extension}";

        public static string DeployFailureKey(string extension) => $"Exoforge_DeployFailed_{extension}";

        /// <summary>The last build log, kept across a domain reload so the reason a build failed is still there afterwards.</summary>
        public const string LastBuildLogKey = "Exoforge_LastBuildLog";

        public static void RecordBuildLog(string log) => SessionState.SetString(LastBuildLogKey, log ?? "");

        public static string LastBuildLog() => SessionState.GetString(LastBuildLogKey, "");

        public static string? BuildFailure(string extension) => NullIfEmpty(SessionState.GetString(BuildFailureKey(extension), ""));

        public static string? DeployFailure(string extension) => NullIfEmpty(SessionState.GetString(DeployFailureKey(extension), ""));

        public static void RecordBuildFailure(string extension, string details) => SessionState.SetString(BuildFailureKey(extension), details);

        public static void ClearBuildFailure(string extension) => SessionState.EraseString(BuildFailureKey(extension));

        public static void RecordDeployFailure(string extension, string message) => SessionState.SetString(DeployFailureKey(extension), message);

        public static void ClearDeployFailure(string extension) => SessionState.EraseString(DeployFailureKey(extension));

        /// <summary>A deploy error in words a developer can act on. The server's own messages already say what to build.</summary>
        public static string DescribeDeployError(Exception ex)
        {
            string message = ex.Message;
            if (message.Contains(":eacces"))
            {
                return $"{message} (the server refused to write the extension's files; the previous process may still be releasing them, so try again).";
            }

            if (message.Contains("wrong_binary_format"))
            {
                return "The server runs a different operating system than this build was made for. Set the build target to Auto (or the server's runtime) and deploy again.";
            }

            if (message.Contains("token_expired") || message.Contains("unauthorized") || message.Contains("invalid_token"))
            {
                return "The server did not accept your session. Sign in again with the Account button, then deploy.";
            }

            return message;
        }

        /// <summary>
        /// Whether this endpoint is the developer's own machine. A deploy anywhere else changes something other people
        /// may be using, so it is confirmed; a local one is not, because it is what happens a hundred times a day.
        /// </summary>
        public static bool IsLocalEndpoint(string? wsUrl)
        {
            if (string.IsNullOrWhiteSpace(wsUrl) || !Uri.TryCreate(wsUrl, UriKind.Absolute, out var uri)) return true;
            string host = uri.Host.ToLowerInvariant();
            return host is "localhost" or "127.0.0.1" or "::1" or "[::1]" || host.EndsWith(".localhost", StringComparison.Ordinal);
        }

        /// <summary>True when the deploy may go ahead: the server is local, or the developer confirmed it by name.</summary>
        public static bool ConfirmDeploy(string environmentName, string? wsUrl, int extensionCount)
        {
            if (IsLocalEndpoint(wsUrl)) return true;

            return EditorUtility.DisplayDialog(
                "Deploy to a remote server?",
                $"You are about to deploy {extensionCount} extension{(extensionCount == 1 ? "" : "s")} to '{environmentName}' ({wsUrl}).\n\n" +
                "Each one replaces the running version for everyone using that server.",
                "Deploy", "Cancel");
        }

        /// <summary>
        /// The environment chip says where a click lands. A remote server is marked in words and in amber, so the
        /// developer who switched to production for a look does not deploy there by habit.
        /// </summary>
        public static void StyleEnvLabel(Label label, string environmentName, string? wsUrl)
        {
            bool local = IsLocalEndpoint(wsUrl);
            label.text = local ? environmentName : $"{environmentName} · REMOTE";
            label.style.color = local ? new StyleColor(ExoforgeUIStyle.TextHeaderPrimary) : new StyleColor(new Color(1f, 0.72f, 0.25f));
            label.tooltip = string.IsNullOrEmpty(wsUrl) ? "No endpoint" : (local ? $"This machine: {wsUrl}" : $"A server that is not this machine: {wsUrl}");
        }

        // ---- status severity (shared by both windows' ShowStatus and banners) ------------------

        /// <summary>How long a success banner stays before it clears itself.</summary>
        public const double SuccessAutoClearSeconds = 6;

        public static string StatusIcon(StatusSeverity severity) => severity switch
        {
            StatusSeverity.Success => "✓",
            StatusSeverity.Warning => "⚠",
            StatusSeverity.Error => "✕",
            _ => "ℹ",
        };

        public static Color StatusColor(StatusSeverity severity) => severity switch
        {
            StatusSeverity.Success => ExoforgeUIStyle.AccentGreen,
            StatusSeverity.Warning => ExoforgeUIStyle.AccentOrange,
            StatusSeverity.Error => ExoforgeUIStyle.AccentRed,
            _ => ExoforgeUIStyle.AccentBlue,
        };

        public static Color StatusBackground(StatusSeverity severity) => severity switch
        {
            StatusSeverity.Success => ExoforgeUIStyle.AccentGreenBg,
            StatusSeverity.Warning => ExoforgeUIStyle.AccentOrangeBg,
            StatusSeverity.Error => ExoforgeUIStyle.AccentRedBg,
            _ => ExoforgeUIStyle.AccentBlueBg,
        };

        public static MessageType ToMessageType(StatusSeverity severity) => severity switch
        {
            StatusSeverity.Warning => MessageType.Warning,
            StatusSeverity.Error => MessageType.Error,
            _ => MessageType.Info,
        };

        /// <summary>Drops an icon the text carries (✓ ⚠ ✗ ✕ ❌ ℹ): the banner draws its own, so two would show.</summary>
        public static string StripStatusIcon(string message)
        {
            if (string.IsNullOrEmpty(message)) return "";
            string text = message.TrimStart();
            while (text.Length > 0 && (text[0] is '✓' or '✔' or '⚠' or '✗' or '✕' or '❌' or 'ℹ' or '\uFE0F' or ' '))
            {
                text = text.Substring(1);
            }

            return text.Length == 0 ? message : text;
        }

        /// <summary>
        /// The severity of a message. An explicit warning or error is kept; an informational one is read from its words
        /// (a leading ✓ or "saved"/"created"/… is a success, "failed"/"error" a failure, "cannot"/"cancelled"/"out of date"/
        /// "no … found" a warning, anything else, such as "Building…", plain information).
        /// </summary>
        public static StatusSeverity ClassifyStatus(string message, MessageType type = MessageType.Info)
        {
            if (type == MessageType.Error) return StatusSeverity.Error;
            if (type == MessageType.Warning) return StatusSeverity.Warning;

            string raw = (message ?? "").TrimStart();
            if (raw.StartsWith("✓", StringComparison.Ordinal) || raw.StartsWith("✔", StringComparison.Ordinal)) return StatusSeverity.Success;

            string text = raw.ToLowerInvariant();
            if (text.Contains("failed") || text.Contains("error")) return StatusSeverity.Error;
            if (text.Contains("cannot") || text.Contains("can't") || text.Contains("cancelled") || text.Contains("out of date") || text.Contains("out of sync")
                || (text.StartsWith("no ", StringComparison.Ordinal) && text.Contains("found"))) return StatusSeverity.Warning;
            if (text.EndsWith("…", StringComparison.Ordinal) || text.EndsWith("...", StringComparison.Ordinal) || text.Contains("… (")) return StatusSeverity.Info;
            foreach (string word in new[] { "successfully", "saved", "updated", "created", "deleted", "cleared", "scaffolded" })
            {
                if (text.Contains(word)) return StatusSeverity.Success;
            }

            return StatusSeverity.Info;
        }

        /// <summary>Logs a status at the matching Unity log level.</summary>
        public static void LogStatus(string message, StatusSeverity severity)
        {
            string line = $"[Exoforge] {message}";
            switch (severity)
            {
                case StatusSeverity.Error: Debug.LogError(line); break;
                case StatusSeverity.Warning: Debug.LogWarning(line); break;
                default: Debug.Log(line); break;
            }
        }

        /// <summary>A status banner: tinted background, the severity's icon and colour, the message, and a dismiss button.</summary>
        public static VisualElement BuildStatusBanner(string message, StatusSeverity severity, Action onDismiss)
        {
            var color = StatusColor(severity);
            var banner = new VisualElement();
            banner.style.backgroundColor = StatusBackground(severity);
            banner.style.borderLeftWidth = 3;
            banner.style.borderLeftColor = color;
            banner.style.paddingLeft = 12;
            banner.style.paddingRight = 12;
            banner.style.paddingTop = 6;
            banner.style.paddingBottom = 6;
            banner.style.flexDirection = FlexDirection.Row;
            banner.style.alignItems = Align.Center;

            var icon = new Label(StatusIcon(severity));
            icon.style.color = color;
            icon.style.unityFontStyleAndWeight = FontStyle.Bold;
            icon.style.fontSize = 13;
            icon.style.marginRight = 8;
            banner.Add(icon);

            var text = new Label(message);
            text.style.color = ExoforgeUIStyle.TextPrimary;
            text.style.fontSize = 11;
            text.style.flexGrow = 1;
            text.style.flexShrink = 1;
            text.style.whiteSpace = WhiteSpace.Normal;
            banner.Add(text);

            var dismiss = new Button(onDismiss) { text = "✕" };
            dismiss.style.borderTopWidth = 0;
            dismiss.style.borderBottomWidth = 0;
            dismiss.style.borderLeftWidth = 0;
            dismiss.style.borderRightWidth = 0;
            dismiss.style.backgroundColor = Color.clear;
            dismiss.style.color = ExoforgeUIStyle.TextSecondary;
            banner.Add(dismiss);
            return banner;
        }

        /// <summary>An IMGUI box with the severity's icon and colour (a HelpBox has no success look).</summary>
        public static void DrawStatusBox(string message, StatusSeverity severity)
        {
            var previous = GUI.backgroundColor;
            GUI.backgroundColor = StatusColor(severity);
            EditorGUILayout.BeginHorizontal(EditorStyles.helpBox);
            GUI.backgroundColor = previous;

            var iconStyle = new GUIStyle(EditorStyles.boldLabel) { fontSize = 14, alignment = TextAnchor.UpperCenter };
            iconStyle.normal.textColor = StatusColor(severity);
            GUILayout.Label(StatusIcon(severity), iconStyle, GUILayout.Width(20));
            GUILayout.Label(message, EditorStyles.wordWrappedLabel);
            EditorGUILayout.EndHorizontal();
        }

        /// <summary>Whether exoforge.json's <c>excluded_extensions</c> leaves this extension out of builds, deploys and stub generation.</summary>
        public static bool IsExcluded(Exoforge.Management.ExoWorkspace? workspace, string extension) =>
            workspace != null && workspace.IsExcluded(extension);

        /// <summary>Marks an extension excluded or included again, saving exoforge.json.</summary>
        public static void SetExcluded(Exoforge.Management.ExoWorkspace workspace, string extension, bool excluded) =>
            workspace.SetExcluded(new[] { extension }, excluded);

        /// <summary>Included extensions that need an excluded one. A deploy is blocked while this is not empty.</summary>
        public static System.Collections.Generic.IReadOnlyList<Exoforge.Management.ExclusionProblem> ExclusionProblems(Exoforge.Management.ExoWorkspace? workspace) =>
            workspace == null
                ? System.Array.Empty<Exoforge.Management.ExclusionProblem>()
                : workspace.FindExclusionProblems();

        /// <summary>
        /// A banner naming each missing provider with a button that includes it; null when nothing is missing.
        /// <paramref name="onChanged"/> runs after a click so the caller can redraw.
        /// </summary>
        public static VisualElement? BuildExclusionBanner(Exoforge.Management.ExoWorkspace? workspace, Action onChanged)
        {
            var problems = ExclusionProblems(workspace);
            if (workspace == null || problems.Count == 0) return null;

            var banner = new VisualElement();
            banner.style.backgroundColor = new Color(0.25f, 0.18f, 0.08f);
            banner.style.borderTopLeftRadius = 8;
            banner.style.borderTopRightRadius = 8;
            banner.style.borderBottomLeftRadius = 8;
            banner.style.borderBottomRightRadius = 8;
            banner.style.paddingLeft = 12;
            banner.style.paddingRight = 12;
            banner.style.paddingTop = 8;
            banner.style.paddingBottom = 8;
            banner.style.marginBottom = 10;

            var title = new Label("Deploy is blocked: an included extension needs one that is excluded.");
            title.style.unityFontStyleAndWeight = FontStyle.Bold;
            title.style.color = new Color(1f, 0.72f, 0.25f);
            title.style.whiteSpace = WhiteSpace.Normal;
            title.style.marginBottom = 4;
            banner.Add(title);

            foreach (var problem in problems)
            {
                var row = new VisualElement();
                row.style.flexDirection = FlexDirection.Row;
                row.style.alignItems = Align.Center;
                row.style.marginTop = 2;

                var text = new Label(problem.Message);
                text.style.flexGrow = 1;
                text.style.whiteSpace = WhiteSpace.Normal;
                row.Add(text);

                string needs = problem.Needs;
                var button = new Button(() =>
                {
                    SetExcluded(workspace, needs, false);
                    onChanged();
                }) { text = $"Include {needs}" };
                row.Add(button);
                banner.Add(row);
            }

            return banner;
        }

        private static string? NullIfEmpty(string value) => string.IsNullOrEmpty(value) ? null : value;
    }
}
