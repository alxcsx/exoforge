using System;
using System.IO;
using Exoforge.Client;
using UnityEditor;
using UnityEngine;
using UnityEngine.UIElements;

namespace Exoforge.Unity.Editor
{
    /// <summary>
    /// Streamlined, modern modal popup for Developer Account and Studio Session Authentication.
    /// Replaces the old in-editor accordion fold with a clean, focused modal.
    /// </summary>
    public sealed class ExoforgeAccountModal : EditorWindow
    {
        private string _email = "";
        private string _password = "";
        private Label? _sessionLabel;
        private Label? _scopesLabel;
        private Label? _statusMessageLabel;
        private Button? _loginBtn;
        private Button? _logoutBtn;

        public static void Open()
        {
            EditorApplication.delayCall += () =>
            {
                var window = CreateInstance<ExoforgeAccountModal>();
                window.titleContent = new GUIContent("Account & Session");

                const float width = 450;
                const float height = 300;
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

            var iconLabel = new Label("👤");
            iconLabel.style.fontSize = 20;
            iconBadge.Add(iconLabel);
            header.Add(iconBadge);

            var titleCol = new VisualElement();
            var title = new Label("Account & Studio Session");
            title.style.fontSize = 15;
            title.style.unityFontStyleAndWeight = FontStyle.Bold;
            title.style.color = ExoforgeUIStyle.TextPrimary;
            titleCol.Add(title);

            var subtitle = new Label("Authenticate with developer credentials for full cluster access.");
            subtitle.style.fontSize = 11;
            subtitle.style.color = ExoforgeUIStyle.TextSecondary;
            titleCol.Add(subtitle);

            header.Add(titleCol);
            root.Add(header);

            // Divider
            var div = ExoforgeUIStyle.CreateDivider(4);
            div.style.marginBottom = 12;
            root.Add(div);

            // 2. Active Session Card
            var sessionCard = new VisualElement();
            sessionCard.style.backgroundColor = ExoforgeUIStyle.BgCard;
            sessionCard.style.borderTopWidth = 1;
            sessionCard.style.borderBottomWidth = 1;
            sessionCard.style.borderLeftWidth = 1;
            sessionCard.style.borderRightWidth = 1;
            sessionCard.style.borderTopColor = ExoforgeUIStyle.BorderSubtle;
            sessionCard.style.borderBottomColor = ExoforgeUIStyle.BorderSubtle;
            sessionCard.style.borderLeftColor = ExoforgeUIStyle.BorderSubtle;
            sessionCard.style.borderRightColor = ExoforgeUIStyle.BorderSubtle;
            sessionCard.style.borderTopLeftRadius = 6;
            sessionCard.style.borderTopRightRadius = 6;
            sessionCard.style.borderBottomLeftRadius = 6;
            sessionCard.style.borderBottomRightRadius = 6;
            sessionCard.style.paddingLeft = 10;
            sessionCard.style.paddingRight = 10;
            sessionCard.style.paddingTop = 8;
            sessionCard.style.paddingBottom = 8;
            sessionCard.style.marginBottom = 12;

            _sessionLabel = new Label();
            _sessionLabel.style.fontSize = 11;
            _sessionLabel.style.unityFontStyleAndWeight = FontStyle.Bold;
            sessionCard.Add(_sessionLabel);

            _scopesLabel = new Label();
            _scopesLabel.style.fontSize = 10;
            _scopesLabel.style.color = ExoforgeUIStyle.TextMuted;
            _scopesLabel.style.marginTop = 2;
            sessionCard.Add(_scopesLabel);

            root.Add(sessionCard);

            // 3. Email and Password Fields
            _email = ExoforgeEditorConfig.LastLoginEmail;
            _password = ExoforgeEditorConfig.LastLoginPassword;

            var emailField = new TextField("Email") { value = _email };
            emailField.style.marginBottom = 6;
            emailField.RegisterValueChangedCallback(evt =>
            {
                _email = evt.newValue ?? "";
                UpdateButtons();
            });
            root.Add(emailField);

            var passwordField = new TextField("Password") { value = _password, isPasswordField = true };
            passwordField.style.marginBottom = 4;
            passwordField.RegisterValueChangedCallback(evt =>
            {
                _password = evt.newValue ?? "";
                UpdateButtons();
            });
            root.Add(passwordField);

            var hintLabel = new Label("Credentials are saved in local per-user EditorPrefs (never committed).");
            hintLabel.style.fontSize = 10;
            hintLabel.style.color = ExoforgeUIStyle.TextMuted;
            hintLabel.style.marginLeft = 120;
            hintLabel.style.marginBottom = 8;
            root.Add(hintLabel);

            _statusMessageLabel = new Label();
            _statusMessageLabel.style.fontSize = 11;
            _statusMessageLabel.style.color = ExoforgeUIStyle.AccentOrange;
            _statusMessageLabel.style.marginBottom = 8;
            root.Add(_statusMessageLabel);

            var spacer = new VisualElement();
            spacer.style.flexGrow = 1;
            root.Add(spacer);

            // 4. Action Buttons
            var btnRow = new VisualElement();
            btnRow.style.flexDirection = FlexDirection.Row;
            btnRow.style.justifyContent = Justify.FlexEnd;
            btnRow.style.alignItems = Align.Center;

            _logoutBtn = ExoforgeUIStyle.CreateModernButton("Log Out & Clear", async () =>
            {
                await ExoforgeControlCenter.LogOutSharedAsync();
                UpdateSessionState();
                _statusMessageLabel.text = "Logged out.";
                _statusMessageLabel.style.color = ExoforgeUIStyle.TextMuted;
            }, height: 28);
            _logoutBtn.style.marginRight = 8;
            btnRow.Add(_logoutBtn);

            var closeBtn = ExoforgeUIStyle.CreateModernButton("Close", () => Close(), height: 28);
            closeBtn.style.marginRight = 8;
            btnRow.Add(closeBtn);

            _loginBtn = ExoforgeUIStyle.CreateModernButton(
                "Sign In (auth.login)",
                async () =>
                {
                    _loginBtn?.SetEnabled(false);
                    _statusMessageLabel.text = "Signing in...";
                    _statusMessageLabel.style.color = ExoforgeUIStyle.AccentBlue;

                    bool ok = await ExoforgeControlCenter.LogInSharedAsync(_email, _password);
                    if (ok)
                    {
                        UpdateSessionState();
                        _statusMessageLabel.text = "✓ Successfully authenticated.";
                        _statusMessageLabel.style.color = ExoforgeUIStyle.AccentGreen;
                    }
                    else
                    {
                        _statusMessageLabel.text = "Sign in failed. Check credentials or connection.";
                        _statusMessageLabel.style.color = ExoforgeUIStyle.AccentOrange;
                    }
                    _loginBtn?.SetEnabled(true);
                },
                bg: ExoforgeUIStyle.BrandPurple,
                textCol: Color.white,
                height: 28);
            btnRow.Add(_loginBtn);

            root.Add(btnRow);

            UpdateSessionState();
            UpdateButtons();
        }

        private void UpdateSessionState()
        {
            string playerId = ExoTokenStore.StudioPlayerId;
            bool hasSession = !string.IsNullOrEmpty(playerId);

            if (_sessionLabel != null)
            {
                _sessionLabel.text = hasSession
                    ? $"● Active Session: {playerId}"
                    : "○ No Active Studio Session (Using guest or dev token)";
                _sessionLabel.style.color = hasSession ? ExoforgeUIStyle.AccentGreen : ExoforgeUIStyle.TextSecondary;
            }

            if (_scopesLabel != null)
            {
                _scopesLabel.text = hasSession && !string.IsNullOrEmpty(ExoTokenStore.StudioScopes)
                    ? $"Scopes: [{ExoTokenStore.StudioScopes}]"
                    : "Connect or sign in with email/password to claim staff scopes.";
            }

            _logoutBtn?.SetEnabled(hasSession || !string.IsNullOrEmpty(ExoTokenStore.StudioToken));
        }

        private void UpdateButtons()
        {
            bool canLogin = !string.IsNullOrWhiteSpace(_email) && !string.IsNullOrEmpty(_password);
            _loginBtn?.SetEnabled(canLogin);
        }
    }
}
