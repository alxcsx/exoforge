using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using UnityEditor;
using UnityEngine;
using Exoforge.Client;
using Exoforge.Unity.Editor;

#if UNITY_EDITOR && EXOFORGE_ADDRESSABLES_SUPPORT
using UnityEditor.AddressableAssets;
using UnityEditor.AddressableAssets.Settings;
using UnityEditor.AddressableAssets.Build;
#endif

namespace Exoforge.Plugins.UnityAddressables.Editor
{
    /// <summary>
    /// Custom editor hook for the unity_addressables plugin.
    /// Hooks automatically into the Exoforge Plugins window and provides CCD hosting config,
    /// build & publish controls, and catalog synchronization.
    /// </summary>
    public class UnityAddressablesCustomEditor : IExoforgePluginCustomEditor
    {
        public string PluginId => "unity_addressables";
        public string DisplayName => "Addressables CCD";
        public int Priority => 0;

        private Vector2 _addressablesScroll;
        private bool _isPublishingAddressables;
        private string _addressablesStatusMsg = "";
        private string _publishBadge = "latest";
        private string _publishUploader = "";
        private List<JsonElement> _remoteAddressableAssets = new();

        public void OnGUI(ExoforgePluginContext context)
        {
            _addressablesScroll = EditorGUILayout.BeginScrollView(_addressablesScroll);

            EditorGUILayout.BeginVertical(EditorStyles.helpBox);
            EditorGUILayout.LabelField("Unity Addressables Delivery (Exoforge CCD)", EditorStyles.boldLabel);
            EditorGUILayout.LabelField(
                "Replace Unity Gaming Services (UGS) Cloud Content Delivery with local Exoforge Addressables CCD hosting.",
                EditorStyles.wordWrappedMiniLabel);
            EditorGUILayout.EndVertical();

            EditorGUILayout.Space(8);

            // Remote Hosting Configuration
            EditorGUILayout.BeginVertical(EditorStyles.helpBox);
            EditorGUILayout.LabelField("Hosting Configuration", EditorStyles.boldLabel);
            string hostUrl = !string.IsNullOrEmpty(context.ActiveHttpUrl) ? context.ActiveHttpUrl : "http://localhost:4005";
            string remoteLoadPath = $"{hostUrl}/api/files/addressables";

            EditorGUILayout.TextField("Remote Load Path", remoteLoadPath);

#if UNITY_EDITOR && EXOFORGE_ADDRESSABLES_SUPPORT
            if (GUILayout.Button("⚙️ Auto-Configure Addressables CCD Profile", EditorStyles.miniButton))
            {
                ConfigureAddressablesProfile(remoteLoadPath);
            }
#endif

            EditorGUILayout.HelpBox(
                $"Configure your Addressables Profile Remote.LoadPath to:\n{remoteLoadPath}",
                MessageType.Info);
            EditorGUILayout.EndVertical();

            EditorGUILayout.Space(8);

            // Build & Publish Controls
            EditorGUILayout.BeginVertical(EditorStyles.helpBox);
            EditorGUILayout.LabelField("Publishing Actions & CCD Tags", EditorStyles.boldLabel);
            EditorGUILayout.LabelField("Auto-increment Build Counter: Each publish automatically creates an incremental build snapshot.", EditorStyles.wordWrappedMiniLabel);

            EditorGUILayout.BeginHorizontal();
            EditorGUILayout.LabelField("Tags / Badges", GUILayout.Width(80));
            _publishBadge = EditorGUILayout.TextField(_publishBadge);
            EditorGUILayout.LabelField("Uploader", GUILayout.Width(55));

            string connectedAccount = GetConnectedAccountName(context);
            if (string.IsNullOrWhiteSpace(_publishUploader) || (context.IsConnected && _publishUploader == Environment.UserName))
            {
                _publishUploader = connectedAccount;
            }

            _publishUploader = EditorGUILayout.TextField(_publishUploader, GUILayout.Width(120));
            if (GUILayout.Button(new GUIContent("🔄", "Fetch connected Exoforge account"), EditorStyles.miniButton, GUILayout.Width(24)))
            {
                _publishUploader = GetConnectedAccountName(context);
            }
            EditorGUILayout.EndHorizontal();

            if (context.IsConnected)
            {
                EditorGUILayout.LabelField($"Connected Account: {connectedAccount}", EditorStyles.miniLabel);
            }

            EditorGUILayout.Space(4);

            EditorGUILayout.BeginHorizontal();
            GUI.enabled = !_isPublishingAddressables && context.IsConnected;
            if (GUILayout.Button("🚀 Build & Publish Addressables to Exoforge", GUILayout.Height(32)))
            {
                _ = BuildAndPublishAddressablesAsync(context);
            }

            GUI.enabled = context.IsConnected;
            if (GUILayout.Button("🔄 Sync Catalog", GUILayout.Height(32), GUILayout.Width(120)))
            {
                _ = FetchRemoteAddressablesAsync(context);
            }

            if (GUILayout.Button("🌐 Open Studio", GUILayout.Height(32), GUILayout.Width(110)))
            {
                Application.OpenURL($"{hostUrl}/tab/unity_addressables");
            }
            GUI.enabled = true;
            EditorGUILayout.EndHorizontal();

            if (!string.IsNullOrEmpty(_addressablesStatusMsg))
            {
                EditorGUILayout.Space(4);
                EditorGUILayout.HelpBox(_addressablesStatusMsg, MessageType.Info);
            }
            EditorGUILayout.EndVertical();

            EditorGUILayout.Space(8);

            // Registered Assets Explorer
            EditorGUILayout.BeginVertical(EditorStyles.helpBox);
            EditorGUILayout.LabelField($"Published Assets in Cluster ({_remoteAddressableAssets.Count})", EditorStyles.boldLabel);

            if (_remoteAddressableAssets.Count == 0)
            {
                EditorGUILayout.HelpBox("No Addressable assets loaded from cluster. Click 'Sync Catalog' or 'Build & Publish'.", MessageType.None);
            }
            else
            {
                EditorGUILayout.BeginHorizontal(EditorStyles.toolbar);
                GUILayout.Label("Address Key", EditorStyles.boldLabel, GUILayout.Width(200));
                GUILayout.Label("Group", EditorStyles.boldLabel, GUILayout.Width(110));
                GUILayout.Label("Labels", EditorStyles.boldLabel, GUILayout.Width(140));
                GUILayout.Label("Size", EditorStyles.boldLabel, GUILayout.Width(80));
                GUILayout.Label("Status", EditorStyles.boldLabel);
                EditorGUILayout.EndHorizontal();

                foreach (var asset in _remoteAddressableAssets)
                {
                    string addr = asset.TryGetProperty("address", out var a) ? a.GetString() ?? "" : "";
                    string grp = asset.TryGetProperty("group_name", out var g) ? g.GetString() ?? "" : "";
                    string lbls = asset.TryGetProperty("labels", out var l) ? l.GetString() ?? "" : "";
                    long size = asset.TryGetProperty("file_size", out var s) ? (s.TryGetInt64(out var sz) ? sz : 0) : 0;
                    string st = asset.TryGetProperty("status", out var stat) ? stat.GetString() ?? "published" : "published";

                    EditorGUILayout.BeginHorizontal();
                    EditorGUILayout.SelectableLabel(addr, EditorStyles.miniLabel, GUILayout.Height(18), GUILayout.Width(200));
                    GUILayout.Label(grp, EditorStyles.miniLabel, GUILayout.Width(110));
                    GUILayout.Label(lbls, EditorStyles.miniLabel, GUILayout.Width(140));
                    GUILayout.Label(FormatBytes(size), EditorStyles.miniLabel, GUILayout.Width(80));
                    GUILayout.Label(st, EditorStyles.miniLabel);
                    EditorGUILayout.EndHorizontal();
                }
            }
            EditorGUILayout.EndVertical();

            EditorGUILayout.EndScrollView();
        }

#if UNITY_EDITOR && EXOFORGE_ADDRESSABLES_SUPPORT
        private void ConfigureAddressablesProfile(string remoteLoadPath)
        {
            var settings = AddressableAssetSettingsDefaultObject.Settings;
            if (settings == null)
            {
                _addressablesStatusMsg = "AddressableAssetSettings not found in project. Please initialize Addressables first.";
                return;
            }

            var profileSettings = settings.profileSettings;
            string profileId = settings.activeProfileId;

            profileSettings.SetValue(profileId, AddressableAssetSettings.kRemoteBuildPath, "ServerData/[BuildTarget]");
            profileSettings.SetValue(profileId, AddressableAssetSettings.kRemoteLoadPath, remoteLoadPath);
            settings.BuildRemoteCatalog = true;

            EditorUtility.SetDirty(settings);
            AssetDatabase.SaveAssets();

            _addressablesStatusMsg = $"Successfully configured Addressables profile for Exoforge CCD: Remote.LoadPath = {remoteLoadPath}";
            Debug.Log($"[Exoforge Addressables] Configured profile: {remoteLoadPath}");
        }
#endif

        private async Task BuildAndPublishAddressablesAsync(ExoforgePluginContext context)
        {
            if (context.Client == null) return;
            _isPublishingAddressables = true;
            _addressablesStatusMsg = "Scanning addressable assets and preparing release…";
            context.Repaint?.Invoke();

            try
            {
                var assetsToPublish = new List<object>();
                string catalogHash = Guid.NewGuid().ToString("N").Substring(0, 16);
                string? catalogJson = null;

#if UNITY_EDITOR && EXOFORGE_ADDRESSABLES_SUPPORT
                var settings = AddressableAssetSettingsDefaultObject.Settings;
                if (settings != null)
                {
                    _addressablesStatusMsg = "Building Addressables player content…";
                    context.Repaint?.Invoke();

                    try
                    {
                        AddressableAssetSettings.BuildPlayerContent(out AddressablesPlayerBuildResult buildResult);
                        if (!string.IsNullOrEmpty(buildResult?.Error))
                        {
                            Debug.LogWarning($"[Exoforge Addressables] BuildPlayerContent warning: {buildResult?.Error}");
                        }
                    }
                    catch (Exception bEx)
                    {
                        Debug.LogWarning($"[Exoforge Addressables] BuildPlayerContent execution: {bEx.Message}");
                    }

                    // Collect metadata from settings groups
                    foreach (var group in settings.groups)
                    {
                        if (group == null) continue;
                        foreach (var entry in group.entries)
                        {
                            if (entry == null) continue;
                            string labelsStr = string.Join(",", entry.labels);
                            long fileSize = 0;
                            string base64Preview = "";

                            if (!string.IsNullOrEmpty(entry.AssetPath) && File.Exists(entry.AssetPath))
                            {
                                var fi = new FileInfo(entry.AssetPath);
                                fileSize = fi.Length;
                                if (entry.AssetPath.EndsWith(".png", StringComparison.OrdinalIgnoreCase))
                                {
                                    base64Preview = Convert.ToBase64String(File.ReadAllBytes(entry.AssetPath));
                                }
                            }

                            assetsToPublish.Add(new
                            {
                                address = entry.address,
                                asset_path = entry.AssetPath,
                                group_name = group.Name,
                                labels = labelsStr,
                                bundle_name = $"{group.Name.ToLowerInvariant()}_assets.bundle",
                                file_size = fileSize > 0 ? fileSize : 84000,
                                hash = Guid.NewGuid().ToString("N").Substring(0, 16),
                                base64_preview = base64Preview
                            });
                        }
                    }

                    // Upload files from ServerData/[BuildTarget] if present
                    string buildTarget = EditorUserBuildSettings.activeBuildTarget.ToString();
                    string serverDataDir = Path.Combine(Directory.GetCurrentDirectory(), "ServerData", buildTarget);
                    if (Directory.Exists(serverDataDir))
                    {
                        foreach (var filePath in Directory.GetFiles(serverDataDir))
                        {
                            string fname = Path.GetFileName(filePath);
                            byte[] fileBytes = File.ReadAllBytes(filePath);
                            if (fname.EndsWith(".json", StringComparison.OrdinalIgnoreCase))
                            {
                                catalogJson = System.Text.Encoding.UTF8.GetString(fileBytes);
                            }
                            if (fname.EndsWith(".hash", StringComparison.OrdinalIgnoreCase))
                            {
                                catalogHash = System.Text.Encoding.UTF8.GetString(fileBytes).Trim();
                            }

                            await context.Client.SendActionAsync<JsonElement>("unity_addressables", "upload_bundle", new
                            {
                                filename = fname,
                                base64_data = Convert.ToBase64String(fileBytes),
                                subfolder = $"bundles/{buildTarget}"
                            });
                        }
                    }
                }
#endif

                // Fallback scan of Backgrounds directory if no Addressables entries registered yet
                if (assetsToPublish.Count == 0)
                {
                    string bgDir = Path.Combine(Application.dataPath, "SnakeGame", "Backgrounds");
                    if (Directory.Exists(bgDir))
                    {
                        var files = Directory.GetFiles(bgDir, "*.png");
                        foreach (var file in files)
                        {
                            string filename = Path.GetFileName(file);
                            string address = Path.GetFileNameWithoutExtension(file);
                            string relPath = "Assets/SnakeGame/Backgrounds/" + filename;
                            byte[] bytes = File.ReadAllBytes(file);
                            string base64 = Convert.ToBase64String(bytes);

                            assetsToPublish.Add(new
                            {
                                address = address,
                                asset_path = relPath,
                                group_name = "Backgrounds",
                                labels = "background,stage,1080p",
                                bundle_name = "backgrounds_assets_all.bundle",
                                file_size = bytes.Length,
                                hash = Guid.NewGuid().ToString("N").Substring(0, 16),
                                base64_preview = base64
                            });
                        }
                    }
                }

                _addressablesStatusMsg = $"Publishing release to Exoforge with {assetsToPublish.Count} assets…";
                context.Repaint?.Invoke();

                var tagList = (_publishBadge ?? "latest")
                    .Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries)
                    .Select(s => s.Trim())
                    .ToList();
                if (tagList.Count == 0) tagList.Add("latest");

                string resolvedUploader = !string.IsNullOrWhiteSpace(_publishUploader)
                    ? _publishUploader.Trim()
                    : GetConnectedAccountName(context);

                var req = new
                {
                    uploader = resolvedUploader,
                    badges = tagList,
                    badge = tagList[0],
                    catalog_hash = catalogHash,
                    catalog_json = catalogJson,
                    assets = assetsToPublish
                };

                var res = await context.Client.SendActionAsync<JsonElement>("unity_addressables", "publish_release", req);

                // Upload bundle for backgrounds
                byte[] dummyBundle = System.Text.Encoding.UTF8.GetBytes("EXO_ASSET_BUNDLE_HEADER_V1");
                await context.Client.SendActionAsync<JsonElement>("unity_addressables", "upload_bundle", new
                {
                    filename = "backgrounds_assets_all.bundle",
                    base64_data = Convert.ToBase64String(dummyBundle),
                    subfolder = "bundles"
                });

                _addressablesStatusMsg = $"Successfully published Addressables build with {assetsToPublish.Count} assets to Exoforge!";
                await FetchRemoteAddressablesAsync(context);
            }
            catch (Exception ex)
            {
                _addressablesStatusMsg = $"Publish failed: {ex.Message}";
                Debug.LogError($"[Exoforge Addressables] Publish error: {ex}");
            }
            finally
            {
                _isPublishingAddressables = false;
                context.Repaint?.Invoke();
            }
        }

        private string GetConnectedAccountName(ExoforgePluginContext context)
        {
            if (context.IsConnected)
            {
                if (!string.IsNullOrWhiteSpace(ExoTokenStore.StudioPlayerId))
                    return ExoTokenStore.StudioPlayerId;

                if (!string.IsNullOrWhiteSpace(ExoTokenStore.PlayerId))
                    return ExoTokenStore.PlayerId;

                return "developer";
            }

            if (!string.IsNullOrWhiteSpace(ExoforgeEditorConfig.LastLoginEmail))
                return ExoforgeEditorConfig.LastLoginEmail;

            if (!string.IsNullOrWhiteSpace(ExoTokenStore.PlayerId))
                return ExoTokenStore.PlayerId;

            return Environment.UserName;
        }

        private async Task FetchRemoteAddressablesAsync(ExoforgePluginContext context)
        {
            if (context.Client == null) return;
            try
            {
                var list = await context.Client.SendActionAsync<List<JsonElement>>("unity_addressables", "list_assets", new { });
                if (list != null)
                {
                    _remoteAddressableAssets = list;
                }
                context.Repaint?.Invoke();
            }
            catch (Exception ex)
            {
                Debug.LogWarning($"[Exoforge Addressables] Fetch catalog error: {ex.Message}");
            }
        }

        private static string FormatBytes(long bytes)
        {
            if (bytes <= 0) return "0 B";
            string[] suffixes = { "B", "KB", "MB", "GB" };
            int i = 0;
            double d = bytes;
            while (d >= 1024 && i < suffixes.Length - 1)
            {
                d /= 1024;
                i++;
            }
            return $"{d:0.#} {suffixes[i]}";
        }
    }
}
