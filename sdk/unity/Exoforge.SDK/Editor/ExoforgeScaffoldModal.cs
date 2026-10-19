using System;
using System.IO;
using System.Linq;
using Exoforge.Management;
using UnityEditor;
using UnityEngine;
using UnityEngine.UIElements;

namespace Exoforge.Unity.Editor
{
    /// <summary>
    /// Streamlined, modern modal popup for scaffolding a new Exoforge C# extension/plugin.
    /// Reusable across both Exoforge Studio and Exoforge Plugins inspector windows.
    /// </summary>
    public sealed class ExoforgeScaffoldModal : EditorWindow
    {
        private string _pluginName = "";
        private int _templateIndex = 0;
        private Action? _onCreated;
        private Label? _pathHintLabel;
        private Button? _createBtn;

        public static void Open(Action? onCreated = null)
        {
            EditorApplication.delayCall += () =>
            {
                var window = CreateInstance<ExoforgeScaffoldModal>();
                window.titleContent = new GUIContent("New Extension");
                window._onCreated = onCreated;

                const float width = 450;
                const float height = 270;
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

            var iconLabel = new Label("⚡");
            iconLabel.style.fontSize = 20;
            iconBadge.Add(iconLabel);
            header.Add(iconBadge);

            var titleCol = new VisualElement();
            var title = new Label("Create New Extension");
            title.style.fontSize = 15;
            title.style.unityFontStyleAndWeight = FontStyle.Bold;
            title.style.color = ExoforgeUIStyle.TextPrimary;
            titleCol.Add(title);

            var subtitle = new Label("Scaffold a new C# plugin module directly into your workspace.");
            subtitle.style.fontSize = 11;
            subtitle.style.color = ExoforgeUIStyle.TextSecondary;
            titleCol.Add(subtitle);

            header.Add(titleCol);
            root.Add(header);

            // Divider
            var div = ExoforgeUIStyle.CreateDivider(4);
            div.style.marginBottom = 14;
            root.Add(div);

            // 2. Extension Name Field
            var nameField = new TextField("Extension Name");
            nameField.style.marginBottom = 8;
            nameField.RegisterValueChangedCallback(evt =>
            {
                _pluginName = evt.newValue ?? "";
                UpdatePreview();
            });
            root.Add(nameField);

            // 3. Template Dropdown
            var templateDropdown = new DropdownField("Template", ExoScaffolder.Templates.ToList(), _templateIndex);
            templateDropdown.style.marginBottom = 6;
            templateDropdown.RegisterValueChangedCallback(evt =>
            {
                _templateIndex = templateDropdown.index;
            });
            root.Add(templateDropdown);

            // 4. Target Path & Format Hint
            _pathHintLabel = new Label("Target path: extensions/<name>/");
            _pathHintLabel.style.fontSize = 11;
            _pathHintLabel.style.color = ExoforgeUIStyle.TextMuted;
            _pathHintLabel.style.marginBottom = 16;
            _pathHintLabel.style.marginLeft = 120; // align with input labels
            root.Add(_pathHintLabel);

            var spacer = new VisualElement();
            spacer.style.flexGrow = 1;
            root.Add(spacer);

            // 5. Action Buttons (Cancel / Create)
            var buttonRow = new VisualElement();
            buttonRow.style.flexDirection = FlexDirection.Row;
            buttonRow.style.justifyContent = Justify.FlexEnd;
            buttonRow.style.alignItems = Align.Center;

            var cancelBtn = ExoforgeUIStyle.CreateModernButton("Cancel", () => Close(), height: 28);
            cancelBtn.style.marginRight = 8;
            buttonRow.Add(cancelBtn);

            _createBtn = ExoforgeUIStyle.CreateModernButton(
                "⚡ Create Extension",
                () => ExecuteCreate(),
                bg: ExoforgeUIStyle.BrandPurple,
                textCol: Color.white,
                height: 28);
            _createBtn.SetEnabled(false);
            buttonRow.Add(_createBtn);

            root.Add(buttonRow);

            nameField.Focus();
        }

        private void UpdatePreview()
        {
            string clean = !string.IsNullOrWhiteSpace(_pluginName)
                ? ExoScaffolder.NormalizePluginName(_pluginName)
                : "";

            bool isValid = !string.IsNullOrWhiteSpace(clean);
            if (_pathHintLabel != null)
            {
                _pathHintLabel.text = isValid
                    ? $"Target path: extensions/{clean}/"
                    : "Names are converted to lower_snake_case (e.g. guild_system, snake_game).";
                _pathHintLabel.style.color = isValid ? ExoforgeUIStyle.TextSecondary : ExoforgeUIStyle.TextMuted;
            }

            _createBtn?.SetEnabled(isValid);
        }

        private void ExecuteCreate()
        {
            if (string.IsNullOrWhiteSpace(_pluginName)) return;

            try
            {
                string wsPath = ExoforgeEditorConfig.GetAbsoluteWorkspacePath();
                var ws = ExoWorkspace.Load(wsPath);
                string normalized = ExoScaffolder.NormalizePluginName(_pluginName);
                string template = (_templateIndex >= 0 && _templateIndex < ExoScaffolder.Templates.Length)
                    ? ExoScaffolder.Templates[_templateIndex]
                    : ExoScaffolder.Templates[0];

                ExoScaffolder.ScaffoldExtension(ws.ExtensionsPath, normalized, template: template);
                Close();
                _onCreated?.Invoke();
            }
            catch (Exception ex)
            {
                EditorUtility.DisplayDialog("Scaffold Failed", ex.Message, "OK");
            }
        }
    }
}
