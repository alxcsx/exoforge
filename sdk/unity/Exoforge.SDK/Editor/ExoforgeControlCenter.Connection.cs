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
            _connectionLatency = $"{sw.ElapsedMilliseconds} ms";
            ShowStatus($"Server reachable at {ActiveWsUrl} in {sw.ElapsedMilliseconds} ms.", MessageType.Info);
            await testClient.DisconnectAsync();
        }
        catch (Exception ex)
        {
            ShowStatus($"Ping failed to {ActiveWsUrl}: {ex.Message}", MessageType.Error);
        }
        Repaint();
    }

    private async Task ConnectAsync(string? tokenOverride = null, string? wsUrlOverride = null)
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

        string targetWs = !string.IsNullOrWhiteSpace(wsUrlOverride) ? wsUrlOverride : ActiveWsUrl;
        if (string.IsNullOrEmpty(targetWs))
        {
            _isConnected = false;
            _isConnecting = false;
            _connectionStatus = "No WS endpoint";
            ShowStatus("No WebSocket endpoint declared in current environment.", MessageType.Error);
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
            _editorClient.OnDisconnected += HandleClientDisconnected;

            await _editorClient.ConnectAsync(new Uri(targetWs), cts.Token);

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

                    _editorClient.OnDisconnected -= HandleClientDisconnected;
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
                ShowStatus($"Authentication failed: {auth.Error}. Sign in using the Account button.", MessageType.Error);
                ExoTokenStore.ClearStudioSession();
            }
        }
        catch (OperationCanceledException)
        {
            _rawConnected = false;
            _connectionStatus = "Timed out";
            ShowStatus($"Connection to {ActiveWsUrl} timed out or was retried. Click Retry to connect.", MessageType.Warning);
        }
        catch (ExoActionException ex)
        {
            _rawConnected = false;
            SessionState.SetBool(WasConnectedSessionKey, false);
            _connectionStatus = "Auth rejected";
            ShowStatus($"Auth rejected: {ex.Message}. Sign in using the Account button.", MessageType.Error);
            ExoTokenStore.ClearStudioSession();
        }
        catch (Exception ex)
        {
            _rawConnected = false;
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

    private void HandleClientDisconnected(Exception? ex)
    {
        EditorApplication.delayCall += () =>
        {
            _rawConnected = false;
            _connectionStatus = "Disconnected";
            Repaint();

            if (SessionState.GetBool(WasConnectedSessionKey, false) && !_isConnecting)
            {
                ShowStatus("Connection to cluster lost. Reconnecting…", MessageType.Warning);
                _ = ReconnectWithRetryAsync(maxRetries: 6, delayMs: 1200);
            }
        };
    }

    private async Task ReconnectWithRetryAsync(int maxRetries = 6, int delayMs = 1000)
    {
        for (int attempt = 1; attempt <= maxRetries; attempt++)
        {
            _isConnecting = true;
            _connectionStatus = attempt == 1 ? "Reconnecting..." : $"Reconnecting ({attempt}/{maxRetries})...";
            Repaint();

            try
            {
                await ConnectAsync();
                if (_isConnected)
                {
                    return;
                }
            }
            catch (Exception ex)
            {
                UnityEngine.Debug.LogWarning($"[Exoforge] Reconnection attempt {attempt} failed: {ex.Message}");
            }

            if (attempt < maxRetries)
            {
                _isConnecting = true;
                _connectionStatus = $"Reconnecting ({attempt + 1}/{maxRetries})...";
                Repaint();
                await Task.Delay(delayMs);
            }
        }

        _isConnecting = false;
        _connectionStatus = "Disconnected";
        SessionState.SetBool(WasConnectedSessionKey, false);
        ShowStatus("Auto-reconnection timed out. Click Connect to retry.", MessageType.Warning);
        Repaint();
    }

    private async Task DisconnectAsync(bool preserveSessionState = false)
    {
        try
        {
            _connectCts?.Cancel();
            _connectCts?.Dispose();
            _connectCts = null;
        }
        catch { }

        if (!preserveSessionState)
        {
            SessionState.SetBool(WasConnectedSessionKey, false);
        }

        if (_editorClient != null)
        {
            try
            {
                _editorClient.OnDisconnected -= HandleClientDisconnected;
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
        RemoteSdkVersion = null;
        RemoteSdkPackageUrl = null;
        RemoteSdkPackageFilename = null;
        SdkStatus = SdkCompatibilityStatus.Unknown;
        Repaint();
        ExoforgePluginsWindow.Instance?.Repaint();
    }

    public static async Task ConnectSharedAsync(string? tokenOverride = null)
    {
        if (Instance != null)
        {
            await Instance.ConnectAsync(tokenOverride);
        }
        else
        {
            var window = GetWindow<ExoforgeControlCenter>("Exoforge Studio");
            await window.ConnectAsync(tokenOverride);
        }
    }

    public static async Task DisconnectSharedAsync()
    {
        if (Instance != null)
        {
            await Instance.DisconnectAsync();
        }
        else if (s_editorClient != null)
        {
            try
            {
                await s_editorClient.DisconnectAsync();
                s_editorClient.Dispose();
            }
            catch { }
            s_editorClient = null;
            s_rawConnected = false;
            s_connectionStatus = "Disconnected";
            ExoforgePluginsWindow.Instance?.Repaint();
        }
    }

    public static async Task<bool> LogInSharedAsync(string email, string password, string? httpUrlOverride = null, string? wsUrlOverride = null)
    {
        var (ok, _) = await LogInSharedWithResultAsync(email, password, httpUrlOverride, wsUrlOverride);
        return ok;
    }

    public static async Task<(bool success, string message)> LogInSharedWithResultAsync(
        string email,
        string password,
        string? httpUrlOverride = null,
        string? wsUrlOverride = null)
    {
        if (string.IsNullOrWhiteSpace(email) || string.IsNullOrEmpty(password))
        {
            string msg = "Enter an email and password to log in.";
            Instance?.ShowStatus(msg, MessageType.Error);
            Instance?.Repaint();
            return (false, msg);
        }

        try
        {
            string httpUrl = !string.IsNullOrWhiteSpace(httpUrlOverride) ? httpUrlOverride : ActiveHttpEndpoint;
            if (string.IsNullOrEmpty(httpUrl))
            {
                string msg = "This environment declares no http_url; add one to exoforge.json to sign in with email/password.";
                Instance?.ShowStatus(msg, MessageType.Error);
                Instance?.Repaint();
                return (false, msg);
            }

            using var loginClient = new ExoClient { HttpBaseUri = new Uri(httpUrl) };
            var data = await loginClient.SendActionAsync<JsonElement>("auth", "login", new { email, password }, ExoTransportPreference.Http);
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
                string msg = "Login failed: the server returned no token.";
                Instance?.ShowStatus(msg, MessageType.Error);
                Instance?.Repaint();
                return (false, msg);
            }

            ExoTokenStore.SaveStudioSession(token, playerId, scopes);
            ExoforgeEditorConfig.LastLoginEmail = email;
            ExoforgeEditorConfig.LastLoginPassword = password;
            string successMsg = $"Successfully logged in as {playerId}.";
            Instance?.ShowStatus(successMsg, MessageType.Info);

            if (Instance != null)
            {
                await Instance.ConnectAsync(token, wsUrlOverride);
            }
            return (true, successMsg);
        }
        catch (Exception ex)
        {
            string msg = $"Login failed: {ex.Message}";
            Instance?.ShowStatus(msg, MessageType.Error);
            return (false, msg);
        }
        finally
        {
            Instance?.Repaint();
            ExoforgeExtensionsWindow.Instance?.Repaint();
            ExoforgePluginsWindow.Instance?.Repaint();
        }
    }

    public static async Task LogOutSharedAsync()
    {
        ExoTokenStore.ClearStudioSession();
        ExoTokenStore.Clear();
        ExoforgeEditorConfig.LastLoginPassword = string.Empty;
        await DisconnectSharedAsync();
        Instance?.ShowStatus("Logged out and cleared the stored session.", MessageType.Info);
        Instance?.Repaint();
        ExoforgePluginsWindow.Instance?.Repaint();
    }

    /// <summary>
    /// Checks whether the specified token is valid against the cluster (via HTTP or WebSocket).
    /// Returns false if rejected by cluster auth; returns true if valid or if cluster is unreachable offline.
    /// </summary>
    public static async Task<bool> ValidateTokenWithClusterAsync(string token)
    {
        if (string.IsNullOrWhiteSpace(token)) return false;

        string httpUrl = ActiveHttpEndpoint;
        string wsUrl = ActiveWsEndpoint;

        if (!string.IsNullOrEmpty(httpUrl))
        {
            try
            {
                using var cts = new System.Threading.CancellationTokenSource(2500);
                using var client = new ExoClient
                {
                    HttpBaseUri = new Uri(httpUrl),
                    DefaultTransportPreference = ExoTransportPreference.Http
                };
                var res = await client.SendActionAsync<JsonElement>(
                    "auth", "authenticate", new { token }, timeout: null, cancellationToken: cts.Token);

                if (res.TryGetProperty("player_id", out _) || res.TryGetProperty("user_id", out _))
                {
                    return true;
                }
                return false;
            }
            catch (ExoActionException ex)
            {
                UnityEngine.Debug.LogWarning($"[Exoforge] Stored session rejected by cluster: {ex.Message}");
                return false;
            }
            catch (Exception)
            {
                // Cluster unreachable or request timed out; try WS below
            }
        }

        if (!string.IsNullOrEmpty(wsUrl))
        {
            try
            {
                using var cts = new System.Threading.CancellationTokenSource(2500);
                using var wsClient = new ExoClient();
                await wsClient.ConnectAsync(new Uri(wsUrl), cts.Token);
                var auth = await wsClient.AuthenticateAsync(token, timeout: TimeSpan.FromSeconds(2.5), cancellationToken: cts.Token);
                await wsClient.DisconnectAsync();
                return auth.IsSuccess;
            }
            catch (ExoActionException ex)
            {
                UnityEngine.Debug.LogWarning($"[Exoforge] Stored session rejected by cluster: {ex.Message}");
                return false;
            }
            catch (Exception)
            {
                // Cluster is offline/unreachable; do not invalidate offline session
                return true;
            }
        }

        return true;
    }

    private async Task LogInAsync()
    {
        await LogInSharedAsync(_loginEmail, _loginPassword);
    }

    private async Task LogOutAsync()
    {
        await LogOutSharedAsync();
    }

    // Serialized on a background thread; only drawn on the main thread.
    private void HandleIncomingEvent(ExoEventFrame evt)
    {
        if (evt.Event == "project.metadata_updated" || evt.Event == "project_metadata_updated")
        {
            try
            {
                if (evt.Payload.TryGetProperty("metadata", out var meta))
                {
                    if (meta.TryGetProperty("project_name", out var pn)) RemoteProjectName = pn.GetString() ?? RemoteProjectName;
                    if (meta.TryGetProperty("studio_name", out var sn)) RemoteStudioName = sn.GetString() ?? RemoteStudioName;
                    if (meta.TryGetProperty("description", out var desc)) RemoteDescription = desc.GetString() ?? "";
                    if (meta.TryGetProperty("website_url", out var url)) RemoteWebsiteUrl = url.GetString() ?? "";
                    EditorApplication.delayCall += Repaint;
                }
            }
            catch { }
        }

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
            ShowStatus("Not connected to cluster. Connect to view remote extensions.", MessageType.Warning);
            Repaint();
            return;
        }

        bool updated = false;

        // 1. Remote Extensions
        try
        {
            var plugins = await _editorClient.SendActionAsync<JsonElement>("extension_manager", "list_extensions", null);
            JsonElement arr = default;
            bool hasList = plugins.ValueKind == JsonValueKind.Object &&
                (plugins.TryGetProperty("extensions", out arr) || plugins.TryGetProperty("plugins", out arr)) &&
                arr.ValueKind == JsonValueKind.Array;
            if (hasList)
            {
                _remotePlugins = arr.EnumerateArray().Select(x => x.Clone()).ToList();
                _pluginsCount = _remotePlugins.Count;
                updated = true;
            }
        }
        catch (Exception ex)
        {
            UnityEngine.Debug.LogWarning($"[Exoforge] Failed to list remote extensions: {ex.Message}");
            ShowStatus($"Failed to list remote extensions: {ex.Message}", MessageType.Error);
        }

        // 2. Cluster Telemetry
        try
        {
            var info = await _editorClient.SendActionAsync<JsonElement>("extension_manager", "get_system_info", null);
            if (info.ValueKind == JsonValueKind.Object && info.TryGetProperty("system", out var sys))
            {
                _nodeName = sys.TryGetProperty("node", out var n) ? n.GetString() ?? "—" : "—";
                _memoryMb = sys.TryGetProperty("memory_mb", out var m) ? $"{m.GetRawText()} MB" : "—";
                RemoteVersion = sys.TryGetProperty("version", out var v) ? v.GetString() ?? "—" : "—";
                RemoteCommitHash = sys.TryGetProperty("commit_hash", out var h) ? h.GetString() ?? "—" : "—";
                RemoteBuildDate = sys.TryGetProperty("build_date", out var d) ? d.GetString() ?? "—" : "—";
                RemoteProjectName = sys.TryGetProperty("project_name", out var pn) ? pn.GetString() ?? "—" : "—";
                RemoteStudioName = sys.TryGetProperty("studio_name", out var sn) ? sn.GetString() ?? "—" : "—";
                if (sys.TryGetProperty("extensions_count", out var ec))
                {
                    _pluginsCount = ec.GetInt32();
                }
                else if (sys.TryGetProperty("plugins_count", out var pc))
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

        // 2b. Remote SDK Package Metadata from File Bucket
        try
        {
            var sdkReq = new Dictionary<string, object>
            {
                ["bucket"] = "sdk",
                ["id"] = "unity"
            };
            var sdkResp = await _editorClient.SendActionAsync<JsonElement>("file_bucket", "get_file_info", sdkReq);
            if (sdkResp.ValueKind == JsonValueKind.Object && sdkResp.TryGetProperty("file", out var fileEl))
            {
                RemoteSdkPackageFilename = fileEl.TryGetProperty("filename", out var fn) ? fn.GetString() : null;
                RemoteSdkPackageUrl = fileEl.TryGetProperty("url", out var u) ? u.GetString() : null;
                if (fileEl.TryGetProperty("metadata", out var meta) && meta.TryGetProperty("version", out var verProp))
                {
                    RemoteSdkVersion = verProp.GetString();
                }
                else if (!string.IsNullOrEmpty(RemoteSdkPackageFilename))
                {
                    var m = System.Text.RegularExpressions.Regex.Match(RemoteSdkPackageFilename, @"-(\d+\.\d+\.\d+[^.]*)");
                    if (m.Success) RemoteSdkVersion = m.Groups[1].Value;
                }
            }
        }
        catch
        {
            // SDK bucket or package not seeded yet
        }

        RemoteSdkVersion ??= (RemoteVersion != "—" ? RemoteVersion : null);
        SdkStatus = ExoforgePackageVersion.Compare(RemoteSdkVersion ?? RemoteVersion, RemoteCommitHash);

        // 2c. Dashboard Project Metadata
        try
        {
            var metaResp = await _editorClient.SendActionAsync<JsonElement>("dashboard", "get_project_metadata", null);
            if (metaResp.ValueKind == JsonValueKind.Object)
            {
                if (metaResp.TryGetProperty("project_name", out var pProp)) RemoteProjectName = pProp.GetString() ?? RemoteProjectName;
                if (metaResp.TryGetProperty("studio_name", out var sProp)) RemoteStudioName = sProp.GetString() ?? RemoteStudioName;
                if (metaResp.TryGetProperty("description", out var dProp)) RemoteDescription = dProp.GetString() ?? "";
                if (metaResp.TryGetProperty("website_url", out var wProp)) RemoteWebsiteUrl = wProp.GetString() ?? "";
                updated = true;
            }
        }
        catch
        {
            // Optional dashboard metadata
        }

        // 3. Service Catalog Export
        try
        {
            var export = await _editorClient.SendActionAsync<JsonElement>("extension_manager", "export_extension_info", null);
            ParseServiceCatalog(export);
            updated = true;
        }
        catch (Exception ex)
        {
            ShowStatus($"Could not read cluster telemetry: {ex.Message}", MessageType.Error);
        }

        if (updated)
        {
            ShowStatus($"✓ Extensions & telemetry updated: {_remotePlugins.Count} remote extensions, cluster node: {_nodeName}.", MessageType.Info);
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
            ShowStatus($"✓ Local extensions refreshed ({_localPlugins.Count} found). Connect to cluster to refresh remote extensions.", MessageType.Info);
            Repaint();
        }
    }

    private void ParseServiceCatalog(JsonElement export)
    {
        if (!export.TryGetProperty("export", out var root))
            return;

        JsonElement pluginsArr = default;
        bool hasItems = (root.TryGetProperty("extensions", out pluginsArr) || root.TryGetProperty("plugins", out pluginsArr)) &&
            pluginsArr.ValueKind == JsonValueKind.Array;
        if (!hasItems)
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

            string icon = "🧩";
            string title = name;
            string manifestPath = Path.Combine(dir, "manifest.json");
            if (File.Exists(manifestPath))
            {
                try
                {
                    var json = File.ReadAllText(manifestPath);
                    using var doc = JsonDocument.Parse(json);
                    var root = doc.RootElement;
                    if (root.TryGetProperty("icon", out var ic) && ic.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(ic.GetString()))
                    {
                        icon = ic.GetString()!;
                    }
                    else if (root.TryGetProperty("dashboard_view", out var dv) && dv.ValueKind == JsonValueKind.Object && dv.TryGetProperty("icon", out var dvIcon) && dvIcon.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(dvIcon.GetString()))
                    {
                        icon = dvIcon.GetString()!;
                    }

                    if (root.TryGetProperty("title", out var tit) && tit.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(tit.GetString()))
                    {
                        title = tit.GetString()!;
                    }
                    else if (root.TryGetProperty("dashboard_view", out var dv2) && dv2.ValueKind == JsonValueKind.Object && dv2.TryGetProperty("title", out var dvTitle) && dvTitle.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(dvTitle.GetString()))
                    {
                        title = dvTitle.GetString()!;
                    }
                }
                catch { }
            }

            if (TryExtractAttributeMetadata(dir, out var attrTitle, out var attrIcon, out _, out _))
            {
                if (!string.IsNullOrWhiteSpace(attrIcon)) icon = attrIcon!;
                if (!string.IsNullOrWhiteSpace(attrTitle) && (title == name || string.IsNullOrEmpty(title))) title = attrTitle!;
            }

            _localPlugins.Add(new LocalPluginInfo(name, dir, pluginType, isBuilt, canBuild, binaryPath, size, modified, version, icon, title));
        }
    }

    /// <summary>Downloads or saves the latest SDK package archive from the connected cluster.</summary>
    public static async Task DownloadOrUpdateSdkAsync()
    {
        string host = ActiveHttpEndpoint;
        if (string.IsNullOrEmpty(host))
        {
            EditorUtility.DisplayDialog("Exoforge SDK", "No active cluster HTTP endpoint is configured. Please connect to a cluster first.", "OK");
            return;
        }

        string targetUrl = !string.IsNullOrEmpty(RemoteSdkPackageUrl)
            ? $"{host.TrimEnd('/')}{RemoteSdkPackageUrl}"
            : $"{host.TrimEnd('/')}/api/files/sdk/unity";

        string filename = RemoteSdkPackageFilename ?? $"com.exoforge.sdk-{RemoteSdkVersion ?? "latest"}.tgz";

        bool download = EditorUtility.DisplayDialog(
            "Exoforge Unity SDK Package",
            $"An SDK package is hosted on the cluster:\n• File: {filename}\n• Remote Version: {RemoteSdkVersion ?? RemoteVersion}\n• Local Version: {ExoforgePackageVersion.SdkVersion}\n\nChoose an option to install or download:",
            "Download .tgz",
            "Open Download in Browser"
        );

        if (!download)
        {
            Application.OpenURL(targetUrl);
            return;
        }

        string savePath = EditorUtility.SaveFilePanel("Save Exoforge SDK Package", "", filename, "tgz");
        if (string.IsNullOrEmpty(savePath)) return;

        EditorUtility.DisplayProgressBar("Exoforge SDK", "Downloading package archive from cluster...", 0.4f);
        try
        {
            using var http = new System.Net.Http.HttpClient();
            var bytes = await http.GetByteArrayAsync(targetUrl);
            await File.WriteAllBytesAsync(savePath, bytes);
            EditorUtility.ClearProgressBar();
            EditorUtility.DisplayDialog("Exoforge SDK", $"Package archive saved successfully to:\n{savePath}\n\nTo apply in Unity: Window ▸ Package Manager ▸ '+' ▸ Add package from tarball...", "OK");
        }
        catch (Exception ex)
        {
            EditorUtility.ClearProgressBar();
            EditorUtility.DisplayDialog("Download Failed", $"Failed to download package from {targetUrl}:\n\n{ex.Message}", "OK");
        }
    }

    public void ShowStatus(string message, MessageType type = MessageType.Info)
    {
        switch (type)
        {
            case MessageType.Error:
                UnityEngine.Debug.LogError($"[Exoforge] {message}");
                _statusMessage = message;
                _statusMessageType = type;
                break;
            case MessageType.Warning:
                UnityEngine.Debug.LogWarning($"[Exoforge] {message}");
                _statusMessage = message;
                _statusMessageType = type;
                break;
            default:
                UnityEngine.Debug.Log($"[Exoforge] {message}");
                _statusMessage = "";
                break;
        }
    }
}
}
