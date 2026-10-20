using System;
using System.IO;
using Exoforge.Management;
using UnityEditor;
using UnityEngine;
using UnityEngine.UIElements;

namespace Exoforge.Unity.Editor
{
    /// <summary>
    /// Streamlined, modern modal popup for adding a new cluster environment to exoforge.json.
    /// </summary>
    public sealed class ExoforgeEnvironmentModal : EditorWindow
    {
        private string _envName = "";
        private string _wsUrl = "ws://localhost:4000/ws";
        private string _httpUrl = "http://localhost:4001";
        private string _token = "dev:developer";
        private Action? _onCreated;

        private Label? _statusLabel;
        private Button? _createBtn;

        public static void Open(Action? onCreated = null)
        {
            EditorApplication.delayCall += () =>
            {
                var window = CreateInstance<ExoforgeEnvironmentModal>();
                window.titleContent = new GUIContent("New Environment");
                window._onCreated = onCreated;

                const float width = 450;
                const float height = 310;
                window.minSize = new Vector2(width, height);
                window.maxSize = new Vector2(width, height);

                var main = EditorGUIUtility.GetMainWindowPosition();
                var pos = window.position;
                pos.x = main.x + (main.width - width) * 0.5f;
                pos.y = main.y + (main.height - height) * 0.5f;
                pos.width = width;
                pos.height = height;
                window.position = pos;

                window.ShowUtility();
                window.Focus();
            };
        }

        private void CreateGUI()
        {
            var root = rootVisualElement;
            root.style.backgroundColor = ExoforgeUIStyle.BgWindow;
            root.style.paddingLeft = 18;
            root.style.paddingRight = 18;
            root.style.paddingTop = 16;
            root.style.paddingBottom = 16;
            root.style.flexDirection = FlexDirection.Column;

            // 1. Header with Badge & Title
            var header = new VisualElement();
            header.style.flexDirection = FlexDirection.Row;
            header.style.alignItems = Align.Center;
            header.style.marginBottom = 12;

            var iconBadge = new VisualElement();
            iconBadge.style.width = 36;
            iconBadge.style.height = 36;
            iconBadge.style.backgroundColor = ExoforgeUIStyle.BrandPurpleGlow;
            iconBadge.style.borderTopLeftRadius = 8;
            iconBadge.style.borderTopRightRadius = 8;
            iconBadge.style.borderBottomLeftRadius = 8;
            iconBadge.style.borderBottomRightRadius = 8;
            iconBadge.style.alignItems = Align.Center;
            iconBadge.style.justifyContent = Justify.Center;
            iconBadge.style.marginRight = 12;

            var iconLabel = new Label("🌐");
            iconLabel.style.fontSize = 20;
            iconBadge.Add(iconLabel);
            header.Add(iconBadge);

            var titleCol = new VisualElement();
            var title = new Label("Add Environment");
            title.style.fontSize = 15;
            title.style.unityFontStyleAndWeight = FontStyle.Bold;
            title.style.color = ExoforgeUIStyle.TextPrimary;
            titleCol.Add(title);

            var subtitle = new Label("Add a target cluster environment to your workspace (exoforge.json).");
            subtitle.style.fontSize = 11;
            subtitle.style.color = ExoforgeUIStyle.TextSecondary;
            titleCol.Add(subtitle);

            header.Add(titleCol);
            root.Add(header);

            // Divider
            var div = ExoforgeUIStyle.CreateDivider(4);
            div.style.marginBottom = 12;
            root.Add(div);

            // 2. Input Fields
            var nameField = new TextField("Environment Name");
            nameField.style.marginBottom = 6;
            nameField.RegisterValueChangedCallback(evt =>
            {
                _envName = evt.newValue ?? "";
                ValidateInputs();
            });
            root.Add(nameField);

            var wsField = new TextField("WebSocket URL") { value = _wsUrl };
            wsField.style.marginBottom = 6;
            wsField.RegisterValueChangedCallback(evt =>
            {
                _wsUrl = evt.newValue ?? "";
                ValidateInputs();
            });
            root.Add(wsField);

            var httpField = new TextField("HTTP REST URL") { value = _httpUrl };
            httpField.style.marginBottom = 6;
            httpField.RegisterValueChangedCallback(evt =>
            {
                _httpUrl = evt.newValue ?? "";
                ValidateInputs();
            });
            root.Add(httpField);

            var tokenField = new TextField("Bearer Token") { value = _token };
            tokenField.style.marginBottom = 8;
            tokenField.RegisterValueChangedCallback(evt =>
            {
                _token = evt.newValue ?? "";
                ValidateInputs();
            });
            root.Add(tokenField);

            // 3. Status / Validation Label
            _statusLabel = new Label("");
            _statusLabel.style.fontSize = 11;
            _statusLabel.style.color = ExoforgeUIStyle.AccentRed;
            _statusLabel.style.marginBottom = 10;
            _statusLabel.style.marginLeft = 120;
            root.Add(_statusLabel);

            var spacer = new VisualElement();
            spacer.style.flexGrow = 1;
            root.Add(spacer);

            // 4. Action Buttons (Cancel / Create)
            var buttonRow = new VisualElement();
            buttonRow.style.flexDirection = FlexDirection.Row;
            buttonRow.style.justifyContent = Justify.FlexEnd;
            buttonRow.style.alignItems = Align.Center;

            var cancelBtn = ExoforgeUIStyle.CreateModernButton("Cancel", () => Close(), height: 28);
            cancelBtn.style.marginRight = 8;
            buttonRow.Add(cancelBtn);

            _createBtn = ExoforgeUIStyle.CreateModernButton(
                "➕ Create Environment",
                ExecuteCreate,
                bg: ExoforgeUIStyle.BrandPurple,
                textCol: Color.white,
                height: 28);
            _createBtn.SetEnabled(false);
            buttonRow.Add(_createBtn);

            root.Add(buttonRow);

            nameField.Focus();
        }

        private void ValidateInputs()
        {
            string clean = _envName.Trim();
            if (string.IsNullOrEmpty(clean))
            {
                _statusLabel?.SetText("");
                _createBtn?.SetEnabled(false);
                return;
            }

            if (clean.IndexOfAny(new[] { ' ', '/', '\\', ':', '*', '?', '"', '<', '>', '|' }) >= 0)
            {
                _statusLabel?.SetText("Name must not contain spaces or special characters.");
                _createBtn?.SetEnabled(false);
                return;
            }

            if (string.IsNullOrWhiteSpace(_wsUrl))
            {
                _statusLabel?.SetText("WebSocket URL is required.");
                _createBtn?.SetEnabled(false);
                return;
            }

            _statusLabel?.SetText("");
            _createBtn?.SetEnabled(true);
        }

        private void ExecuteCreate()
        {
            string cleanName = _envName.Trim().ToLowerInvariant();
            if (string.IsNullOrEmpty(cleanName)) return;

            try
            {
                var ws = ExoforgeControlCenter.Instance?.Workspace
                    ?? ExoWorkspace.Load(ExoforgeEditorConfig.GetAbsoluteWorkspacePath());

                if (ws == null || !ExoWorkspace.Exists(ws.RootPath))
                {
                    _statusLabel?.SetText("Workspace not initialized. Initialize workspace first.");
                    return;
                }

                if (ws.Config.Environments.ContainsKey(cleanName))
                {
                    bool overwrite = EditorUtility.DisplayDialog(
                        "Environment Exists",
                        $"Environment '{cleanName}' already exists in exoforge.json.\n\nDo you want to overwrite its endpoints?",
                        "Overwrite", "Cancel");

                    if (!overwrite) return;
                }

                string wsUrl = _wsUrl.Trim();
                string? httpUrl = string.IsNullOrWhiteSpace(_httpUrl) ? null : _httpUrl.Trim();
                string token = _token.Trim();

                ws.Config.Environments[cleanName] = new ExoEnvironmentConfig
                {
                    WsUrl = wsUrl,
                    HttpUrl = httpUrl,
                    Token = token
                };

                ws.Save();
                ExoforgeRuntimeConfigGenerator.Generate();

                var newEnv = new ExoforgeControlCenter.EnvOption(cleanName, wsUrl, token, httpUrl);
                ExoforgeControlCenter.ApplyEnvironment(newEnv);
                ExoforgeControlCenter.Instance?.ShowStatus($"✓ Created environment '{cleanName}' and saved to exoforge.json.", MessageType.Info);

                _onCreated?.Invoke();
                Close();
            }
            catch (Exception ex)
            {
                _statusLabel?.SetText($"Error: {ex.Message}");
            }
        }
    }
}
