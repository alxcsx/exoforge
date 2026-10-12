using System;
using Exoforge.Client;
using Exoforge.Management;
using UnityEditor;

namespace Exoforge.Unity.Editor
{
    /// <summary>
    /// Context passed to custom plugin editor extensions when rendering their custom editor GUI.
    /// </summary>
    public sealed class ExoforgePluginContext
    {
        public string PluginId { get; }
        public ExoClient? Client { get; }
        public bool IsConnected => Client != null && Client.IsConnected;
        public string ActiveHttpUrl { get; }
        public ExoWorkspace? Workspace { get; }
        public Action Repaint { get; }
        public Action<string, MessageType> ShowStatus { get; }

        public ExoforgePluginContext(
            string pluginId,
            ExoClient? client,
            string activeHttpUrl,
            ExoWorkspace? workspace,
            Action repaint,
            Action<string, MessageType> showStatus)
        {
            PluginId = pluginId;
            Client = client;
            ActiveHttpUrl = activeHttpUrl;
            Workspace = workspace;
            Repaint = repaint;
            ShowStatus = showStatus;
        }
    }

    /// <summary>
    /// Interface for engine-specific editor UI extensions provided by plugins or companion packages.
    /// Any class implementing this interface will automatically hook into the Exoforge Plugins window.
    /// </summary>
    public interface IExoforgePluginCustomEditor
    {
        /// <summary>
        /// The plugin identifier this editor extension attaches to (e.g., "unity_addressables").
        /// </summary>
        string PluginId { get; }

        /// <summary>
        /// Display title for the custom editor section/tab.
        /// </summary>
        string DisplayName { get; }

        /// <summary>
        /// Order priority when multiple extensions exist. Lower numbers appear first.
        /// </summary>
        int Priority => 0;

        /// <summary>
        /// Renders custom IMGUI / EditorGUI controls for this plugin.
        /// </summary>
        void OnGUI(ExoforgePluginContext context);
    }
}
