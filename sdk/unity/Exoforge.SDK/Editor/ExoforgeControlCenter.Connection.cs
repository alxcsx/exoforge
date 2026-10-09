using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Exoforge.Client;
using Exoforge.Management;
using UnityEditor;
using UnityEngine;

namespace Exoforge.Unity.Editor
{
// NOTE: keep this a block-scoped namespace. Unity's layout serializer drops windows declared
// with file-scoped namespaces, so the window would vanish from saved layouts (Unity issue 9734).

/// <summary>Connection, authentication and cluster introspection for the Exoforge Studio window.</summary>
public partial class ExoforgeControlCenter : EditorWindow
{
    // =========================================================================
    // Connection & Auth Logic
    // =========================================================================

    private async Task PingClusterAsync()
    {
        try
        {
            var sw = Stopwatch.StartNew();
            using var testClient = new ExoClient();
            await testClient.ConnectAsync(new Uri(ActiveWsUrl));
            sw.Stop();
            ShowStatus($"Server reachable at {ActiveWsUrl} in {sw.ElapsedMilliseconds} ms.", MessageType.Info);
            await testClient.DisconnectAsync();
        }
        catch (Exception ex)
        {
            ShowStatus($"Ping failed to {ActiveWsUrl}: {ex.Message}", MessageType.Error);
        }
        Repaint();
    }

    private async Task ConnectAsync(string? tokenOverride = null)
    {
        try
        {
            _connectCts?.Cancel();
            _connectCts?.Dispose();
        }
        catch { }

        var cts = new CancellationTokenSource(TimeSpan.FromSeconds(6));
        _connectCts = cts;

        _isConnecting = true;
        _connectionStatus = "Connecting...";
        Repaint();

        string targetToken = !string.IsNullOrWhiteSpace(tokenOverride)
            ? tokenOverride
            : (!string.IsNullOrWhiteSpace(ExoTokenStore.StudioToken)
                ? ExoTokenStore.StudioToken
                : ExoTokenStore.Token);

        if (string.IsNullOrWhiteSpace(targetToken))
        {
            _isConnected = false;
            _isConnecting = false;
            _connectionStatus = "No token";
            ShowStatus("A bearer token is required. Enter one above (e.g. 'dev:developer') or sign in.", MessageType.Error);
            Repaint();
            return;
        }

        try
        {
            _editorClient?.Dispose();
            _editorClient = new ExoClient();
            if (!string.IsNullOrEmpty(ActiveHttpUrl))
            {
                _editorClient.HttpBaseUri = new Uri(ActiveHttpUrl);
            }
            _editorClient.OnAnyEvent += HandleIncomingEvent;

            await _editorClient.ConnectAsync(new Uri(ActiveWsUrl), cts.Token);

            var auth = await _editorClient.AuthenticateAsync(targetToken, cancellationToken: cts.Token);
            if (auth.IsSuccess)
            {
                // The Studio is staff tooling (M33 Fix 14): its tabs read users, tokens, plugins and
                // telemetry. A session scoped below staff connects to the game, never to this
                // window.
                if (!ExoStaff.HasAccess(auth.Scopes))
                {
                    _isConnected = false;
                    SessionState.SetBool(WasConnectedSessionKey, false);
                    _connectionStatus = "Access Denied (Staff Only)";
                    ShowStatus(
                        "Editor tools require a staff account (studio or admin). Player and guest access is denied.",
                        MessageType.Error);

                    await _editorClient.DisconnectAsync();
                    _editorClient.Dispose();
                    _editorClient = null;
                    return;
                }

                _isConnected = true;
                SessionState.SetBool(WasConnectedSessionKey, true);
                _connectionStatus = auth.PlayerId ?? "authenticated";
                // Stored as the Studio's session, not the device's: play mode reads it when
                // ExoforgeManager's "use studio connection" flag is on, and the device's own session
                // is left intact for when it is off.
                ExoTokenStore.SaveStudioSession(targetToken, auth.PlayerId, auth.Scopes);

                ShowStatus($"Connected as {auth.PlayerId} to {ActiveWsUrl}.", MessageType.Info);

                await _editorClient.SubscribeAsync("*", cancellationToken: cts.Token);
                await RefreshRemoteInfoAsync();
            }
            else
            {
                _isConnected = false;
                SessionState.SetBool(WasConnectedSessionKey, false);
                _connectionStatus = "Auth failed";
                ShowStatus($"Authentication failed: {auth.Error}", MessageType.Error);
            }
        }
        catch (OperationCanceledException)
        {
            _isConnected = false;
            SessionState.SetBool(WasConnectedSessionKey, false);
            _connectionStatus = "Timed out";
            ShowStatus($"Connection to {ActiveWsUrl} timed out or was retried. Click Retry to connect.", MessageType.Warning);
        }
        catch (ExoActionException ex)
        {
            _isConnected = false;
            SessionState.SetBool(WasConnectedSessionKey, false);
            _connectionStatus = "Auth rejected";
            ShowStatus(
                $"Auth rejected: {ex.Message}\n" +
                "Tip: 'dev:developer' works in dev mode. For production, sign in with email/password.",
                MessageType.Error);
        }
        catch (Exception ex)
        {
            _isConnected = false;
            SessionState.SetBool(WasConnectedSessionKey, false);
            _connectionStatus = "Connection error";
            ShowStatus($"Could not connect to {ActiveWsUrl}: {ex.Message}", MessageType.Error);
        }
        finally
        {
            if (_connectCts == cts)
            {
                _isConnecting = false;
            }
            Repaint();
        }
    }

    private async Task DisconnectAsync()
    {
        try
        {
            _connectCts?.Cancel();
            _connectCts?.Dispose();
            _connectCts = null;
        }
        catch { }

        SessionState.SetBool(WasConnectedSessionKey, false);
        if (_editorClient != null)
        {
            try
            {
                await _editorClient.DisconnectAsync();
            }
            catch (Exception ex)
            {
                // Teardown: worth a line in the console, not worth failing the disconnect over.
                UnityEngine.Debug.LogWarning($"[Exoforge] Disconnect while closing the editor client failed: {ex.Message}");
            }
            _editorClient.Dispose();
            _editorClient = null;
        }

        _isConnected = false;
        _isConnecting = false;
        _connectionStatus = "Disconnected";
        Repaint();
    }

    private async Task LogInAsync()
    {
        if (string.IsNullOrWhiteSpace(_loginEmail) || string.IsNullOrEmpty(_loginPassword))
        {
            ShowStatus("Enter an email and password to log in.", MessageType.Error);
            Repaint();
            return;
        }

        try
        {
            // Over HTTP, with no socket: signing in no longer pretends to be "guest" to get a
            // connection to sign in over (M33 Fix 14).
            string httpUrl = ActiveHttpUrl;

            if (string.IsNullOrEmpty(httpUrl))
            {
                ShowStatus("This environment declares no http_url; add one to exoforge.json to sign in with email/password.", MessageType.Error);
                Repaint();
                return;
            }

            using var loginClient = new ExoClient { HttpBaseUri = new Uri(httpUrl) };

            var data = await loginClient.SendActionAsync<JsonElement>("auth", "login", new { email = _loginEmail, password = _loginPassword }, ExoTransportPreference.Http);
            string token = data.TryGetProperty("token", out var tProp) ? tProp.GetString() ?? "" : "";
            string playerId = data.TryGetProperty("player_id", out var pProp) ? pProp.GetString() ?? "" : "";

            var scopes = new List<string>();
            if (data.TryGetProperty("scopes", out var sProp) && sProp.ValueKind == JsonValueKind.Array)
            {
                foreach (var s in sProp.EnumerateArray())
                {
                    scopes.Add(s.GetString() ?? "");
                }
            }

            if (string.IsNullOrEmpty(token))
            {
                ShowStatus("Login failed: the server returned no token.", MessageType.Error);
                Repaint();
                return;
            }

            ExoTokenStore.SaveStudioSession(token, playerId, scopes);

            // Keep the dev login for the next editor start
            ExoforgeEditorConfig.LastLoginEmail = _loginEmail;
            ExoforgeEditorConfig.LastLoginPassword = _loginPassword;
            ShowStatus($"Successfully logged in as {playerId}.", MessageType.Info);

            await ConnectAsync(token);
        }
        catch (Exception ex)
        {
            ShowStatus($"Login failed: {ex.Message}", MessageType.Error);
        }

        Repaint();
    }

    private async Task LogOutAsync()
    {
        ExoTokenStore.ClearStudioSession();
        ExoTokenStore.Clear();
        ExoforgeEditorConfig.LastLoginPassword = string.Empty;
        await DisconnectAsync();
        ShowStatus("Logged out and cleared the stored session.", MessageType.Info);
        Repaint();
    }

    // Serialized on a background thread; only drawn on the main thread.
    private void HandleIncomingEvent(ExoEventFrame evt)
    {
        if (_eventPaused) return;

        string raw;
        try { raw = JsonSerializer.Serialize(evt.Payload, new JsonSerializerOptions { WriteIndented = true }); }
        catch { raw = evt.Payload.ToString() ?? "{}"; }

        _pendingEvents.Enqueue(new LoggedEvent(DateTime.UtcNow, evt.Topic, evt.Event, raw));
    }

    private async Task RefreshRemoteInfoAsync()
    {
        if (_editorClient == null || !_isConnected)
        {
            ShowStatus("Not connected to cluster. Connect to view remote plugins.", MessageType.Warning);
            Repaint();
            return;
        }

        bool updated = false;

        // 1. Remote Plugins
        try
        {
            var plugins = await _editorClient.SendActionAsync<JsonElement>("plugin_manager", "list_plugins", null);
            if (plugins.ValueKind == JsonValueKind.Object && plugins.TryGetProperty("plugins", out var arr) && arr.ValueKind == JsonValueKind.Array)
            {
                _remotePlugins = arr.EnumerateArray().Select(x => x.Clone()).ToList();
                _pluginsCount = _remotePlugins.Count;
                updated = true;
            }
        }
        catch (Exception ex)
        {
            UnityEngine.Debug.LogWarning($"[Exoforge] Failed to list remote plugins: {ex.Message}");
            ShowStatus($"Failed to list remote plugins: {ex.Message}", MessageType.Error);
        }

        // 2. Cluster Telemetry
        try
        {
            var info = await _editorClient.SendActionAsync<JsonElement>("plugin_manager", "get_system_info", null);
            if (info.ValueKind == JsonValueKind.Object && info.TryGetProperty("system", out var sys))
            {
                _nodeName = sys.TryGetProperty("node", out var n) ? n.GetString() ?? "—" : "—";
                _memoryMb = sys.TryGetProperty("memory_mb", out var m) ? $"{m.GetRawText()} MB" : "—";
                if (sys.TryGetProperty("plugins_count", out var pc))
                {
                    _pluginsCount = pc.GetInt32();
                }

                if (sys.TryGetProperty("uptime_seconds", out var u))
                {
                    int s = u.GetInt32();
                    _uptime = s < 60 ? $"{s}s" : $"{s / 60}m {s % 60}s";
                }
                updated = true;
            }
        }
        catch (Exception ex)
        {
            UnityEngine.Debug.LogWarning($"[Exoforge] Failed to get system info: {ex.Message}");
        }

        // 3. Service Catalog Export
        try
        {
            var export = await _editorClient.SendActionAsync<JsonElement>("plugin_manager", "export_plugin_info", null);
            ParseServiceCatalog(export);
            updated = true;
        }
        catch (Exception ex)
        {
            ShowStatus($"Could not read cluster telemetry: {ex.Message}", MessageType.Error);
        }

        if (updated)
        {
            ShowStatus($"✓ Plugins & telemetry updated: {_remotePlugins.Count} remote plugins, cluster node: {_nodeName}.", MessageType.Info);
        }

        Repaint();
    }

    private async Task RefreshPluginsAsync()
    {
        RefreshLocalPlugins();
        if (_isConnected && _editorClient != null)
        {
            await RefreshRemoteInfoAsync();
        }
        else
        {
            ShowStatus($"✓ Local plugins refreshed ({_localPlugins.Count} found). Connect to cluster to refresh remote plugins.", MessageType.Info);
            Repaint();
        }
    }

    private void ParseServiceCatalog(JsonElement export)
    {
        if (!export.TryGetProperty("export", out var root) || !root.TryGetProperty("plugins", out var pluginsArr))
            return;

        // Replace, don't merge: the export is the whole truth, so a plugin that was removed must
        // disappear from the catalog too.
        _serviceCatalog.Clear();
        _pluginServices.Clear();

        foreach (var plugin in pluginsArr.EnumerateArray())
        {
            if (!plugin.TryGetProperty("services", out var servicesArr)) continue;

            foreach (var s in servicesArr.EnumerateArray())
            {
                string sName = s.TryGetProperty("name", out var sn) ? sn.GetString() ?? "" : "";
                if (string.IsNullOrEmpty(sName)) continue;

                if (!_serviceCatalog.ContainsKey(sName))
                    _serviceCatalog[sName] = new List<ActionSpec>();

                string pluginId = plugin.TryGetProperty("id", out var pid) ? pid.GetString() ?? "" : "";

                if (pluginId.Length > 0)
                {
                    if (!_pluginServices.TryGetValue(pluginId, out var provided))
                    {
                        provided = new List<string>();
                        _pluginServices[pluginId] = provided;
                    }

                    if (!provided.Contains(sName)) provided.Add(sName);
                }

                if (!s.TryGetProperty("actions", out var actionsArr)) continue;

                foreach (var a in actionsArr.EnumerateArray())
                {
                    string aName = a.TryGetProperty("name", out var an) ? an.GetString() ?? "" : "";
                    if (string.IsNullOrEmpty(aName)) continue;
                    if (_serviceCatalog[sName].Any(existing => existing.Name == aName)) continue;

                    var parameters = new Dictionary<string, JsonElement>();

                    if (a.TryGetProperty("params", out var paramsObj) && paramsObj.ValueKind == JsonValueKind.Object)
                    {
                        foreach (var property in paramsObj.EnumerateObject())
                        {
                            parameters[property.Name] = property.Value.Clone();
                        }
                    }

                    _serviceCatalog[sName].Add(new ActionSpec(aName, parameters));
                }
            }
        }

        SelectDefaultSandboxAction();
    }

    /// <summary>
    /// Picks the first real action so the Sandbox is usable on open. Previously it defaulted to a
    /// hardcoded action name that no longer existed, so the first dispatch always failed.
    /// </summary>
    private void SelectDefaultSandboxAction()
    {
        if (_serviceCatalog.Count == 0) return;

        bool stillValid = _serviceCatalog.TryGetValue(_sandboxService, out var current) &&
                          current.Any(a => a.Name == _sandboxAction);

        if (stillValid) return;

        _sandboxService = _serviceCatalog.Keys.First();
        _sandboxAction = _serviceCatalog[_sandboxService][0].Name;
        _selectedServiceIndex = _serviceCatalog.Keys.ToList().IndexOf(_sandboxService);
        _selectedActionIndex = 0;
        LoadSamplePayload(_sandboxService, _sandboxAction);
    }

    private void RefreshLocalPlugins()
    {
        _localPlugins = new List<LocalPluginInfo>();
        string pluginsDir = Workspace.PluginsPath;
        if (!Directory.Exists(pluginsDir)) return;

        foreach (var dir in Directory.GetDirectories(pluginsDir))
        {
            string name = Path.GetFileName(dir);
            string csproj = Path.Combine(dir, "src", name + ".csproj");
            if (!File.Exists(csproj)) csproj = Path.Combine(dir, name + ".csproj");
            if (!File.Exists(csproj))
            {
                csproj = Directory.GetFiles(dir, "*.csproj", SearchOption.AllDirectories)
                    .FirstOrDefault(path => !IsBuildPath(path)) ?? "";
            }

            bool canBuild = File.Exists(csproj);

            string pluginType = "native";

            // `exo plugin build` stages it under .exoforge/; the plugin root is the older layout.
            string binaryPath = ExoDeployer.StagedBinary(dir, name);

            bool isBuilt = binaryPath != "" && File.Exists(binaryPath);
            long size = isBuilt ? new FileInfo(binaryPath).Length : 0;

            // The manifest version carries the build stamp (1.0.0+<build>.<hash>); if the current
            // sources hash differently, the plugin changed since it was last built.
            bool modified = false;
            string? version = null;
            if (isBuilt)
            {
                version = ExoDeployer.ReadManifestVersion(dir);
                string fingerprint = ExoDeployer.ComputeSourceFingerprint(dir);
                modified = version == null || !version.EndsWith("." + fingerprint, StringComparison.Ordinal);
            }

            _localPlugins.Add(new LocalPluginInfo(name, dir, pluginType, isBuilt, canBuild, binaryPath, size, modified, version));
        }
    }

    private void ShowStatus(string message, MessageType type)
    {
        _statusMessage = message;
        _statusMessageType = type;
    }
}
}
