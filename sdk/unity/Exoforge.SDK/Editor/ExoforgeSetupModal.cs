using System;
using System.IO;
using Exoforge.Client;
using Exoforge.Client.Unity;
using Exoforge.Management;
using UnityEditor;
using UnityEngine;
using UnityEngine.UIElements;

namespace Exoforge.Unity.Editor
{
    /// <summary>
    /// Unified 5-Step First-Run Setup Wizard:
    /// Step 1: Connect to an instance (test connection, BaaS-first, offline escape hatch).
    /// Step 2: Sign in (Local dev or credentials).
    /// Step 3: Project readiness (verify dotnet >= 9, initialize workspace, runtime config).
    /// Step 4: Scene setup (non-destructive ExoforgeManager attachment).
    /// Step 5: Ready CTA ("Create your first extension").
    /// </summary>
    public sealed class ExoforgeSetupModal : EditorWindow
    {
        private int _currentStep = 1;
        private string _baseUrl = "localhost";
        private string _envName = "local";
        private string _wsUrl = "ws://localhost:4000/ws";
        private string _httpUrl = "http://localhost:4001";
        private bool _isOfflineMode = false;

        private string _email = !string.IsNullOrEmpty(ExoforgeEditorConfig.LastLoginEmail) ? ExoforgeEditorConfig.LastLoginEmail : "admin";
        private string _password = !string.IsNullOrEmpty(ExoforgeEditorConfig.LastLoginPassword) ? ExoforgeEditorConfig.LastLoginPassword : "";

        private Action? _onCompleted;
        private VisualElement? _stepContainer;
        private Label? _stepProgressLabel;
        private Label? _statusLabel;

        [MenuItem("Tools/Exoforge/Setup Wizard...", false, 10)]
        [MenuItem("Window/Exoforge/Setup Wizard...", false, 10)]
        public static void OpenMenu()
        {
            Open();
        }

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
                window.titleContent = new GUIContent("Exoforge Setup Wizard");
                window._onCompleted = onCompleted;

                const float width = 520;
                const float height = 440;
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
            root.style.paddingLeft = 20;
            root.style.paddingRight = 20;
            root.style.paddingTop = 16;
            root.style.paddingBottom = 16;
            root.style.flexDirection = FlexDirection.Column;

            // 1. Header with Badge & Step Indicator
            var header = new VisualElement();
            header.style.flexDirection = FlexDirection.Row;
            header.style.alignItems = Align.Center;
            header.style.marginBottom = 10;

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
            var title = new Label("Exoforge Onboarding Wizard");
            title.style.fontSize = 16;
            title.style.unityFontStyleAndWeight = FontStyle.Bold;
            title.style.color = ExoforgeUIStyle.TextPrimary;
            titleCol.Add(title);

            _stepProgressLabel = new Label("Step 1 of 5: Connect to Instance");
            _stepProgressLabel.style.fontSize = 11;
            _stepProgressLabel.style.color = ExoforgeUIStyle.BrandPurple;
            _stepProgressLabel.style.unityFontStyleAndWeight = FontStyle.Bold;
            titleCol.Add(_stepProgressLabel);

            header.Add(titleCol);
            root.Add(header);

            // Divider
            var div = ExoforgeUIStyle.CreateDivider(4);
            div.style.marginBottom = 12;
            root.Add(div);

            // 2. Step Content Container
            _stepContainer = new VisualElement();
            _stepContainer.style.flexGrow = 1;
            root.Add(_stepContainer);

            // 3. Status message label
            _statusLabel = new Label();
            _statusLabel.style.fontSize = 11;
            _statusLabel.style.marginTop = 6;
            _statusLabel.style.marginBottom = 4;
            _statusLabel.style.whiteSpace = WhiteSpace.Normal;
            root.Add(_statusLabel);

            RenderCurrentStep();
        }

        private void RenderCurrentStep()
        {
            if (_stepContainer == null) return;
            _stepContainer.Clear();
            _statusLabel?.SetText("");

            switch (_currentStep)
            {
                case 1:
                    RenderStep1Connect();
                    break;
                case 2:
                    RenderStep2SignIn();
                    break;
                case 3:
                    RenderStep3Project();
                    break;
                case 4:
                    RenderStep4Scene();
                    break;
                case 5:
                    RenderStep5Ready();
                    break;
            }
        }

        // =========================================================================
        // Step 1: Connect to Instance
        // =========================================================================
        private void RenderStep1Connect()
        {
            if (_stepProgressLabel != null) _stepProgressLabel.text = "Step 1 of 5: Connect to Instance";

            var desc = new Label("Enter your Exoforge server URL. For local development with Docker, keep localhost.");
            desc.style.fontSize = 11;
            desc.style.color = ExoforgeUIStyle.TextSecondary;
            desc.style.marginBottom = 12;
            _stepContainer!.Add(desc);

            var baseField = new TextField("Instance URL") { value = _baseUrl };
            baseField.tooltip = "Enter your cluster host (e.g. localhost, https://my-cluster.exoforge.app)";
            baseField.style.marginBottom = 8;
            _stepContainer.Add(baseField);

            var previewCard = new VisualElement();
            previewCard.style.backgroundColor = ExoforgeUIStyle.BgCard;
            previewCard.style.paddingLeft = 12;
            previewCard.style.paddingRight = 12;
            previewCard.style.paddingTop = 8;
            previewCard.style.paddingBottom = 8;
            previewCard.style.borderTopLeftRadius = 6;
            previewCard.style.borderTopRightRadius = 6;
            previewCard.style.borderBottomLeftRadius = 6;
            previewCard.style.borderBottomRightRadius = 6;
            previewCard.style.marginBottom = 10;

            var wsLabel = new Label();
            wsLabel.style.fontSize = 11;
            wsLabel.style.color = ExoforgeUIStyle.TextSecondary;
            previewCard.Add(wsLabel);

            var httpLabel = new Label();
            httpLabel.style.fontSize = 11;
            httpLabel.style.color = ExoforgeUIStyle.TextSecondary;
            previewCard.Add(httpLabel);

            _stepContainer.Add(previewCard);

            Action updateDerived = () =>
            {
                _baseUrl = baseField.value?.Trim() ?? "localhost";
                ExoforgeEditorConfig.DeriveEndpoints(_baseUrl, out _wsUrl, out _httpUrl);
                wsLabel.text = $"• WebSocket: {_wsUrl}";
                httpLabel.text = $"• HTTP REST: {_httpUrl}";
                bool isLocal = ExoforgeEditorConfig.IsLocalUrl(_wsUrl);
                _envName = isLocal ? "local" : "production";
            };

            baseField.RegisterValueChangedCallback(_ => updateDerived());
            updateDerived();

            // Test Ping Button
            var testPingBtn = ExoforgeUIStyle.CreateModernButton("🔍 Test Connection (Ping)", async () =>
            {
                _statusLabel?.SetText("Pinging cluster...");
                _statusLabel!.style.color = ExoforgeUIStyle.AccentBlue;
                try
                {
                    var sw = System.Diagnostics.Stopwatch.StartNew();
                    using var testClient = new ExoClient();
                    await testClient.ConnectAsync(new Uri(_wsUrl));
                    sw.Stop();
                    await testClient.DisconnectAsync();

                    _statusLabel.SetText($"✓ Connection verified! Latency: {sw.ElapsedMilliseconds} ms");
                    _statusLabel.style.color = ExoforgeUIStyle.AccentGreen;
                }
                catch (Exception ex)
                {
                    _statusLabel.SetText($"Connection test failed to {_wsUrl}: {ex.Message}");
                    _statusLabel.style.color = ExoforgeUIStyle.AccentOrange;
                }
            }, height: 26);
            testPingBtn.style.marginBottom = 12;
            _stepContainer.Add(testPingBtn);

            var spacer = new VisualElement();
            spacer.style.flexGrow = 1;
            _stepContainer.Add(spacer);

            // Nav buttons
            var btnRow = new VisualElement();
            btnRow.style.flexDirection = FlexDirection.Row;
            btnRow.style.justifyContent = Justify.SpaceBetween;
            btnRow.style.alignItems = Align.Center;

            var offlineToggle = new Button(() =>
            {
                _isOfflineMode = true;
                _statusLabel?.SetText("⚠️ Warning: Developing offline will disable cloud sync, build, and deploy.");
                _statusLabel!.style.color = ExoforgeUIStyle.AccentOrange;
                _currentStep = 3; // skip login if offline
                RenderCurrentStep();
            })
            { text = "Work Offline (Testing Only)" };
            offlineToggle.style.backgroundColor = Color.clear;
            offlineToggle.style.color = ExoforgeUIStyle.TextMuted;
            offlineToggle.style.borderTopWidth = 0;
            offlineToggle.style.borderBottomWidth = 0;
            offlineToggle.style.borderLeftWidth = 0;
            offlineToggle.style.borderRightWidth = 0;
            offlineToggle.style.fontSize = 11;
            btnRow.Add(offlineToggle);

            var nextBtn = ExoforgeUIStyle.CreateModernButton("Next: Sign In ➔", () =>
            {
                _isOfflineMode = false;
                SaveWorkspaceEnvironment();
                _currentStep = 2;
                RenderCurrentStep();
            }, bg: ExoforgeUIStyle.BrandPurple, textCol: Color.white, height: 28);
            btnRow.Add(nextBtn);

            _stepContainer.Add(btnRow);
        }

        // =========================================================================
        // Step 2: Sign In
        // =========================================================================
        private void RenderStep2SignIn()
        {
            if (_stepProgressLabel != null) _stepProgressLabel.text = "Step 2 of 5: Authenticate";

            var desc = new Label("Enter your credentials to authenticate with the server.");
            desc.style.fontSize = 11;
            desc.style.color = ExoforgeUIStyle.TextSecondary;
            desc.style.marginBottom = 12;
            _stepContainer!.Add(desc);

            var credBox = new VisualElement();
            var emailField = new TextField("Email / Username") { value = _email };
            emailField.style.marginBottom = 6;
            credBox.Add(emailField);

            var passField = new TextField("Password") { value = _password, isPasswordField = true };
            passField.style.marginBottom = 6;
            credBox.Add(passField);

            _stepContainer.Add(credBox);

            var spacer = new VisualElement();
            spacer.style.flexGrow = 1;
            _stepContainer.Add(spacer);

            var btnRow = new VisualElement();
            btnRow.style.flexDirection = FlexDirection.Row;
            btnRow.style.justifyContent = Justify.SpaceBetween;
            btnRow.style.alignItems = Align.Center;

            var backBtn = ExoforgeUIStyle.CreateModernButton("⯇ Back", () =>
            {
                _currentStep = 1;
                RenderCurrentStep();
            }, height: 28);
            btnRow.Add(backBtn);

            var nextBtn = ExoforgeUIStyle.CreateModernButton("Next: Project Setup ➔", async () =>
            {
                _statusLabel?.SetText("Authenticating...");
                _statusLabel!.style.color = ExoforgeUIStyle.AccentBlue;

                _email = emailField.value?.Trim() ?? "";
                _password = passField.value ?? "";
                var (ok, msg) = await ExoforgeControlCenter.LogInSharedWithResultAsync(
                    _email,
                    _password,
                    httpUrlOverride: _httpUrl,
                    wsUrlOverride: _wsUrl);

                if (ok)
                {
                    SaveWorkspaceEnvironment();
                    _statusLabel.SetText("✓ Authentication successful.");
                    _statusLabel.style.color = ExoforgeUIStyle.AccentGreen;
                    _currentStep = 3;
                    RenderCurrentStep();
                }
                else
                {
                    _statusLabel.SetText($"Authentication failed: {msg}");
                    _statusLabel.style.color = ExoforgeUIStyle.AccentOrange;
                }
            }, bg: ExoforgeUIStyle.BrandPurple, textCol: Color.white, height: 28);
            btnRow.Add(nextBtn);

            _stepContainer.Add(btnRow);
        }

        private void SaveWorkspaceEnvironment()
        {
            try
            {
                string wsPath = ExoforgeEditorConfig.GetAbsoluteWorkspacePath();
                if (!ExoWorkspace.Exists(wsPath))
                {
                    ExoWorkspace.Initialize(wsPath);
                }

                var ws = ExoWorkspace.Load(wsPath);
                string defaultToken = !string.IsNullOrEmpty(ExoTokenStore.StudioToken)
                    ? ExoTokenStore.StudioToken
                    : ExoTokenStore.Token;

                ws.Config.Environments[_envName] = new ExoEnvironmentConfig
                {
                    WsUrl = _wsUrl,
                    HttpUrl = _httpUrl,
                    Token = defaultToken
                };
                ws.Config.DefaultEnvironment = _envName;
                ws.Save();

                ExoforgeEditorConfig.SelectedEnvironment = _envName;
                ExoforgeControlCenter.InvalidateWorkspaceShared();
                ExoforgeRuntimeConfigGenerator.Generate();
            }
            catch (Exception ex)
            {
                Debug.LogWarning($"[Exoforge] Failed to save workspace environment: {ex.Message}");
            }
        }

        // =========================================================================
        // Step 3: Project Readiness
        // =========================================================================
        private void RenderStep3Project()
        {
            if (_stepProgressLabel != null) _stepProgressLabel.text = "Step 3 of 5: Project Readiness";

            int sdkMajor = ExoScaffolder.DetectHighestInstalledSdkMajor("dotnet");
            bool dotnetReady = sdkMajor >= ExoScaffolder.MinimumMajorDotnetVersion;

            var statusCard = new VisualElement();
            statusCard.style.backgroundColor = ExoforgeUIStyle.BgCard;
            statusCard.style.paddingLeft = 14;
            statusCard.style.paddingRight = 14;
            statusCard.style.paddingTop = 12;
            statusCard.style.paddingBottom = 12;
            statusCard.style.borderTopLeftRadius = 6;
            statusCard.style.borderTopRightRadius = 6;
            statusCard.style.borderBottomLeftRadius = 6;
            statusCard.style.borderBottomRightRadius = 6;
            statusCard.style.marginBottom = 12;

            var dotnetRow = new Label(dotnetReady
                ? $"✓ .NET SDK {sdkMajor}.0 installed (Minimum .NET 9 required)"
                : $"⚠️ .NET SDK >= 9.0 not detected. Installed: {sdkMajor}.0. Extensions require .NET 9+ to compile.");
            dotnetRow.style.fontSize = 11;
            dotnetRow.style.color = dotnetReady ? ExoforgeUIStyle.AccentGreen : ExoforgeUIStyle.AccentOrange;
            dotnetRow.style.marginBottom = 6;
            statusCard.Add(dotnetRow);

            var wsRow = new Label("• Workspace directory: Exoforge/");
            wsRow.style.fontSize = 11;
            wsRow.style.color = ExoforgeUIStyle.TextSecondary;
            wsRow.style.marginBottom = 4;
            statusCard.Add(wsRow);

            var rtRow = new Label("• Runtime config: Assets/Resources/exoforge.json");
            rtRow.style.fontSize = 11;
            rtRow.style.color = ExoforgeUIStyle.TextSecondary;
            statusCard.Add(rtRow);

            _stepContainer!.Add(statusCard);

            var prepBtn = ExoforgeUIStyle.CreateModernButton("⚙️ Initialize Workspace & Configs", () =>
            {
                SaveWorkspaceEnvironment();
                _statusLabel?.SetText("✓ Workspace initialized and runtime config generated.");
                _statusLabel!.style.color = ExoforgeUIStyle.AccentGreen;
            }, height: 28);
            prepBtn.style.marginBottom = 12;
            _stepContainer.Add(prepBtn);

            var spacer = new VisualElement();
            spacer.style.flexGrow = 1;
            _stepContainer.Add(spacer);

            var btnRow = new VisualElement();
            btnRow.style.flexDirection = FlexDirection.Row;
            btnRow.style.justifyContent = Justify.SpaceBetween;
            btnRow.style.alignItems = Align.Center;

            var backBtn = ExoforgeUIStyle.CreateModernButton("⯇ Back", () =>
            {
                _currentStep = 2;
                RenderCurrentStep();
            }, height: 28);
            btnRow.Add(backBtn);

            var nextBtn = ExoforgeUIStyle.CreateModernButton("Next: Scene Setup ➔", () =>
            {
                SaveWorkspaceEnvironment();
                _currentStep = 4;
                RenderCurrentStep();
            }, bg: ExoforgeUIStyle.BrandPurple, textCol: Color.white, height: 28);
            btnRow.Add(nextBtn);

            _stepContainer.Add(btnRow);
        }

        // =========================================================================
        // Step 4: Add Exoforge to Scene
        // =========================================================================
        private void RenderStep4Scene()
        {
            if (_stepProgressLabel != null) _stepProgressLabel.text = "Step 4 of 5: Scene Setup";

            bool hasManager = UnityEngine.Object.FindAnyObjectByType<ExoforgeManager>(FindObjectsInactive.Include) != null;

            var desc = new Label("Exoforge requires an ExoforgeManager in the scene to manage client connection and thread dispatching.");
            desc.style.fontSize = 11;
            desc.style.color = ExoforgeUIStyle.TextSecondary;
            desc.style.marginBottom = 12;
            _stepContainer!.Add(desc);

            var sceneCard = new VisualElement();
            sceneCard.style.backgroundColor = ExoforgeUIStyle.BgCard;
            sceneCard.style.paddingLeft = 14;
            sceneCard.style.paddingRight = 14;
            sceneCard.style.paddingTop = 12;
            sceneCard.style.paddingBottom = 12;
            sceneCard.style.borderTopLeftRadius = 6;
            sceneCard.style.borderTopRightRadius = 6;
            sceneCard.style.borderBottomLeftRadius = 6;
            sceneCard.style.borderBottomRightRadius = 6;
            sceneCard.style.marginBottom = 12;

            var mgrLabel = new Label(hasManager
                ? "✓ ExoforgeManager detected in current active scene."
                : "○ No ExoforgeManager found in the current scene.");
            mgrLabel.style.fontSize = 11;
            mgrLabel.style.color = hasManager ? ExoforgeUIStyle.AccentGreen : ExoforgeUIStyle.TextMuted;
            sceneCard.Add(mgrLabel);
            _stepContainer.Add(sceneCard);

            var addBtn = ExoforgeUIStyle.CreateModernButton("➕ Add Exoforge to Active Scene", () =>
            {
                ExoforgeSceneSetup.AddToScene();
                mgrLabel.text = "✓ ExoforgeManager successfully added to scene.";
                mgrLabel.style.color = ExoforgeUIStyle.AccentGreen;
            }, height: 28);
            addBtn.style.marginBottom = 12;
            _stepContainer.Add(addBtn);

            var spacer = new VisualElement();
            spacer.style.flexGrow = 1;
            _stepContainer.Add(spacer);

            var btnRow = new VisualElement();
            btnRow.style.flexDirection = FlexDirection.Row;
            btnRow.style.justifyContent = Justify.SpaceBetween;
            btnRow.style.alignItems = Align.Center;

            var backBtn = ExoforgeUIStyle.CreateModernButton("⯇ Back", () =>
            {
                _currentStep = 3;
                RenderCurrentStep();
            }, height: 28);
            btnRow.Add(backBtn);

            var nextBtn = ExoforgeUIStyle.CreateModernButton("Next: Complete ➔", () =>
            {
                _currentStep = 5;
                RenderCurrentStep();
            }, bg: ExoforgeUIStyle.BrandPurple, textCol: Color.white, height: 28);
            btnRow.Add(nextBtn);

            _stepContainer.Add(btnRow);
        }

        // =========================================================================
        // Step 5: Ready / Call To Action
        // =========================================================================
        private void RenderStep5Ready()
        {
            if (_stepProgressLabel != null) _stepProgressLabel.text = "Step 5 of 5: Ready to Build";

            ExoforgeEditorConfig.HasCompletedInitialSetup = true;

            var card = new VisualElement();
            card.style.backgroundColor = ExoforgeUIStyle.BgCard;
            card.style.paddingLeft = 16;
            card.style.paddingRight = 16;
            card.style.paddingTop = 16;
            card.style.paddingBottom = 16;
            card.style.borderTopLeftRadius = 8;
            card.style.borderTopRightRadius = 8;
            card.style.borderBottomLeftRadius = 8;
            card.style.borderBottomRightRadius = 8;
            card.style.alignItems = Align.Center;
            card.style.marginBottom = 16;

            var checkIcon = new Label("🎉");
            checkIcon.style.fontSize = 32;
            checkIcon.style.marginBottom = 6;
            card.Add(checkIcon);

            var congrats = new Label("Exoforge Setup Complete!");
            congrats.style.fontSize = 15;
            congrats.style.unityFontStyleAndWeight = FontStyle.Bold;
            congrats.style.color = ExoforgeUIStyle.TextPrimary;
            congrats.style.marginBottom = 4;
            card.Add(congrats);

            var sub = new Label("Your Unity project is configured and ready. Create your first server extension to begin.");
            sub.style.fontSize = 11;
            sub.style.color = ExoforgeUIStyle.TextSecondary;
            sub.style.unityTextAlign = TextAnchor.MiddleCenter;
            card.Add(sub);

            _stepContainer!.Add(card);

            var createExtBtn = ExoforgeUIStyle.CreateModernButton("⚡ Create Your First Extension", () =>
            {
                Close();
                _onCompleted?.Invoke();
                ExoforgeScaffoldModal.Open(onCreatedWithId: id =>
                {
                    ExoforgeControlCenter.ShowWindow();
                });
            }, bg: ExoforgeUIStyle.BrandPurple, textCol: Color.white, height: 34);
            createExtBtn.style.marginBottom = 8;
            _stepContainer.Add(createExtBtn);

            var openStudioBtn = ExoforgeUIStyle.CreateModernButton("Open Exoforge Studio", () =>
            {
                Close();
                _onCompleted?.Invoke();
                ExoforgeControlCenter.ShowWindow();
            }, height: 28);
            _stepContainer.Add(openStudioBtn);
        }

        private void OnDestroy()
        {
            if (_currentStep == 5)
            {
                _onCompleted?.Invoke();
            }
        }
    }
}
