#nullable enable
using System;
using UnityEditor;
using UnityEngine;
using UnityEngine.UIElements;

namespace Exoforge.Unity.Editor
{
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

        private static string? NullIfEmpty(string value) => string.IsNullOrEmpty(value) ? null : value;
    }
}
