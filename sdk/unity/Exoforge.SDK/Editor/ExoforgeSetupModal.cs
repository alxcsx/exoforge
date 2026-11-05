using System;
using System.IO;
using Exoforge.Management;
using UnityEditor;
using UnityEngine;
using UnityEngine.UIElements;

namespace Exoforge.Unity.Editor
{
    /// <summary>
    /// First-installation setup modal: prompts the user for their cluster Base URL,
    /// automatically deriving WebSocket and HTTP endpoints, and saving the environment.
    /// </summary>
    public sealed class ExoforgeSetupModal : EditorWindow
    {
        private string _baseUrl = "localhost";
        private string _envName = "local";
        private string _wsUrl = "ws://localhost:4000/ws";
        private string _httpUrl = "http://localhost:4001";
        private Action? _onCompleted;

        private Label? _previewWs;
        private Label? _previewHttp;
        private Label? _statusLabel;
        private Button? _continueBtn;

        public static void Open(Action? onCompleted = null)
        {
            EditorApplication.delayCall += () =>
            {
                var existing = Resources.FindObjectsOfTypeAll<ExoforgeSetupModal>();
                if (existing.Length > 0)
                {
                    if (onCompleted != null) existing[0]._onCompleted += onCompleted;
                    existing[0].Focus();
                    return;
                }

                var window = CreateInstance<ExoforgeSetupModal>();
                window.titleContent = new GUIContent("Exoforge Setup");
                window._onCompleted = onCompleted;

                const float width = 480;
                const float height = 360;
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

            // 1. Header
            var header = new VisualElement();
            header.style.flexDirection = FlexDirection.Row;
            header.style.alignItems = Align.Center;
            header.style.marginBottom = 12;

            var iconBadge = new VisualElement();
            iconBadge.style.width = 40;
            iconBadge.style.height = 40;
            iconBadge.style.backgroundColor = ExoforgeUIStyle.BrandPurpleGlow;
            iconBadge.style.borderTopLeftRadius = 8;
            iconBadge.style.borderTopRightRadius = 8;
            iconBadge.style.borderBottomLeftRadius = 8;
            iconBadge.style.borderBottomRightRadius = 8;
            iconBadge.style.alignItems = Align.Center;
            iconBadge.style.justifyContent = Justify.Center;
            iconBadge.style.marginRight = 12;

            var iconLabel = new Label("🚀");
            iconLabel.style.fontSize = 22;
            iconBadge.Add(iconLabel);
            header.Add(iconBadge);

            var titleCol = new VisualElement();
            var title = new Label("Welcome to Exoforge");
            title.style.fontSize = 16;
            title.style.unityFontStyleAndWeight = FontStyle.Bold;
            title.style.color = ExoforgeUIStyle.TextPrimary;
            titleCol.Add(title);

            var subtitle = new Label("Configure your cluster Base URL to initialize the SDK.");
            subtitle.style.fontSize = 11;
            subtitle.style.color = ExoforgeUIStyle.TextSecondary;
            titleCol.Add(subtitle);

            header.Add(titleCol);
            root.Add(header);

            // Divider
            var div = ExoforgeUIStyle.CreateDivider(4);
            div.style.marginBottom = 12;
            root.Add(div);

            // 2. Base URL Input
            var baseField = new TextField("Cluster Base URL") { value = _baseUrl };
            baseField.tooltip = "Enter your cluster host (e.g. exof1.alexcs.me, https://exof1.alexcs.me, or localhost)";
            baseField.style.marginBottom = 10;
            root.Add(baseField);

            // 3. Derived Endpoints Card (Preview)
            var card = new VisualElement();
            card.style.backgroundColor = ExoforgeUIStyle.BgCard;
            card.style.borderTopWidth = 1;
            card.style.borderBottomWidth = 1;
            card.style.borderLeftWidth = 1;
            card.style.borderRightWidth = 1;
            card.style.borderTopColor = ExoforgeUIStyle.BorderSubtle;
            card.style.borderBottomColor = ExoforgeUIStyle.BorderSubtle;
            card.style.borderLeftColor = ExoforgeUIStyle.BorderSubtle;
            card.style.borderRightColor = ExoforgeUIStyle.BorderSubtle;
            card.style.borderTopLeftRadius = 6;
            card.style.borderTopRightRadius = 6;
            card.style.borderBottomLeftRadius = 6;
            card.style.borderBottomRightRadius = 6;
            card.style.paddingLeft = 12;
            card.style.paddingRight = 12;
            card.style.paddingTop = 10;
            card.style.paddingBottom = 10;
            card.style.marginBottom = 10;

            var previewTitle = new Label("Inferred Endpoints");
            previewTitle.style.fontSize = 11;
            previewTitle.style.unityFontStyleAndWeight = FontStyle.Bold;
            previewTitle.style.color = ExoforgeUIStyle.TextSecondary;
            previewTitle.style.marginBottom = 6;
            card.Add(previewTitle);

            _previewWs = new Label();
            _previewWs.style.fontSize = 11;
            _previewWs.style.color = ExoforgeUIStyle.AccentBlue;
            _previewWs.style.marginBottom = 4;
            card.Add(_previewWs);

            _previewHttp = new Label();
            _previewHttp.style.fontSize = 11;
            _previewHttp.style.color = ExoforgeUIStyle.AccentGreen;
            card.Add(_previewHttp);

            root.Add(card);

            // Environment Name Field
            var envField = new TextField("Environment Name") { value = _envName };
            envField.style.marginBottom = 8;
            envField.RegisterValueChangedCallback(evt =>
            {
                _envName = evt.newValue ?? "";
                Validate();
            });
            root.Add(envField);

            baseField.RegisterValueChangedCallback(evt =>
            {
                _baseUrl = evt.newValue ?? "";
                UpdateDerivedEndpoints(envField);
                Validate();
            });

            // 4. Status / Error Message
            _statusLabel = new Label();
            _statusLabel.style.fontSize = 11;
            _statusLabel.style.color = ExoforgeUIStyle.AccentRed;
            _statusLabel.style.marginBottom = 8;
            root.Add(_statusLabel);

            var spacer = new VisualElement();
            spacer.style.flexGrow = 1;
            root.Add(spacer);

            // 5. Buttons
            var btnRow = new VisualElement();
            btnRow.style.flexDirection = FlexDirection.Row;
            btnRow.style.justifyContent = Justify.FlexEnd;
            btnRow.style.alignItems = Align.Center;

            var localBtn = ExoforgeUIStyle.CreateModernButton("Use Localhost", () =>
            {
                _baseUrl = "localhost";
                baseField.SetValueWithoutNotify(_baseUrl);
                UpdateDerivedEndpoints(envField);
                ExecuteSetup();
            }, height: 28);
            localBtn.style.marginRight = 8;
            btnRow.Add(localBtn);

            _continueBtn = ExoforgeUIStyle.CreateModernButton(
                "Confirm & Continue ➔",
                ExecuteSetup,
                bg: ExoforgeUIStyle.BrandPurple,
                textCol: Color.white,
                height: 28);
            btnRow.Add(_continueBtn);

            root.Add(btnRow);

            UpdateDerivedEndpoints(envField);
            Validate();
        }

        private void UpdateDerivedEndpoints(TextField envField)
        {
            ExoforgeEditorConfig.DeriveEndpoints(_baseUrl, out _wsUrl, out _httpUrl);

            if (_previewWs != null) _previewWs.text = $"• WebSocket: {_wsUrl}";
            if (_previewHttp != null) _previewHttp.text = $"• HTTP REST: {_httpUrl}";

            bool isLocal = ExoforgeEditorConfig.IsLocalUrl(_wsUrl);
            string suggestedName = isLocal ? "local" : "production";
            if (!isLocal && !string.IsNullOrWhiteSpace(_baseUrl))
            {
                string raw = _baseUrl.Trim().TrimEnd('/');
                if (raw.Contains("://")) raw = raw.Substring(raw.IndexOf("://", StringComparison.Ordinal) + 3);
                int slash = raw.IndexOf('/');
                if (slash > 0) raw = raw.Substring(0, slash);
                int colon = raw.IndexOf(':');
                if (colon > 0) raw = raw.Substring(0, colon);
                int dot = raw.IndexOf('.');
                if (dot > 0) raw = raw.Substring(0, dot);
                if (!string.IsNullOrEmpty(raw)) suggestedName = raw.ToLowerInvariant();
            }

            _envName = suggestedName;
            envField.SetValueWithoutNotify(_envName);
        }

        private void Validate()
        {
            if (string.IsNullOrWhiteSpace(_baseUrl))
            {
                _statusLabel?.SetText("Cluster Base URL is required.");
                _continueBtn?.SetEnabled(false);
                return;
            }

            if (string.IsNullOrWhiteSpace(_envName))
            {
                _statusLabel?.SetText("Environment name is required.");
                _continueBtn?.SetEnabled(false);
                return;
            }

            _statusLabel?.SetText("");
            _continueBtn?.SetEnabled(true);
        }

        private void ExecuteSetup()
        {
            try
            {
                string wsPath = ExoforgeEditorConfig.GetAbsoluteWorkspacePath();
                if (!ExoWorkspace.Exists(wsPath))
                {
                    ExoWorkspace.Initialize(wsPath);
                }

                var ws = ExoWorkspace.Load(wsPath);
                string cleanEnv = string.IsNullOrWhiteSpace(_envName) ? "local" : _envName.Trim().ToLowerInvariant();

                string defaultToken = cleanEnv == "local" ? "dev:developer" : "";
                ws.Config.Environments[cleanEnv] = new ExoEnvironmentConfig
                {
                    WsUrl = _wsUrl,
                    HttpUrl = _httpUrl,
                    Token = defaultToken
                };
                ws.Save();

                ExoforgeEditorConfig.SelectedEnvironment = cleanEnv;
                ExoforgeRuntimeConfigGenerator.Generate();
                ExoforgeEditorConfig.HasCompletedInitialSetup = true;

                var actionToInvoke = _onCompleted;
                Close();

                actionToInvoke?.Invoke();
            }
            catch (Exception ex)
            {
                _statusLabel?.SetText($"Setup failed: {ex.Message}");
            }
        }
    }
}
