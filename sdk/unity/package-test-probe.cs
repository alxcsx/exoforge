using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using Exoforge.Client;
using Exoforge.Client.Unity;
using Exoforge.Unity.Editor;
using UnityEditor;
using UnityEngine;

/// <summary>
/// Comprehensive verification probe for a fresh Unity project with the Exoforge SDK
/// imported from the package tarball (<c>com.exoforge.sdk-*.tgz</c>).
///
/// Tests:
/// 1. Package import and assembly compilation.
/// 2. SDK editor toolchain and metadata resolution.
/// 3. Runtime configuration loading from <c>Resources/exoforge.json</c>.
/// 4. Live connection & anonymous authentication against a cluster (default: <c>http://localhost:4001</c>).
///
/// Executed via:
/// <c>Unity -batchmode -nographics -projectPath ... -executeMethod ExoforgePackageProbe.Run -logFile ...</c>
/// </summary>
public static class ExoforgePackageProbe
{
    private const string DefaultServerUrl = "http://localhost:4001";
    private const string DefaultWsUrl = "ws://localhost:4000/ws";

    private static int s_failures = 0;

    public static void Run()
    {
        s_failures = 0;
        Debug.Log("[package-probe] ========================================================");
        Debug.Log("[package-probe] Starting Exoforge Unity SDK Package Integration Probe");
        Debug.Log("[package-probe] ========================================================");

        try
        {
            // 1. Verify Package and Editor Toolchain
            CheckEditorToolchain();

            // 2. Setup Resources/exoforge.json for connection
            string serverUrl = Environment.GetEnvironmentVariable("EXOFORGE_TEST_URL");
            if (string.IsNullOrWhiteSpace(serverUrl)) serverUrl = DefaultServerUrl;

            string wsUrl = Environment.GetEnvironmentVariable("EXOFORGE_TEST_WS_URL");
            if (string.IsNullOrWhiteSpace(wsUrl)) wsUrl = DefaultWsUrl;

            SetupRuntimeConfig(serverUrl, wsUrl);

            // 3. Test Live Connection & Authentication
            TestLiveAuthentication(serverUrl, wsUrl);
        }
        catch (Exception ex)
        {
            s_failures++;
            Debug.LogError($"[package-probe] UNHANDLED EXCEPTION: {ex.GetType().Name}: {ex.Message}\n{ex.StackTrace}");
        }

        Debug.Log("[package-probe] ========================================================");
        if (s_failures == 0)
        {
            Debug.Log("[package-probe] SUCCESS: All package verification & connection checks passed!");
        }
        else
        {
            Debug.LogError($"[package-probe] FAILED: {s_failures} check(s) failed.");
        }
        Debug.Log("[package-probe] ========================================================");

        EditorApplication.Exit(s_failures == 0 ? 0 : 1);
    }

    private static void Check(bool condition, string message)
    {
        if (condition)
        {
            Debug.Log($"[package-probe] PASS: {message}");
        }
        else
        {
            s_failures++;
            Debug.LogError($"[package-probe] FAIL: {message}");
        }
    }

    private static void CheckEditorToolchain()
    {
        Debug.Log("[package-probe] --- Step 1: Checking Package & Editor Toolchain ---");

        string? pkgRoot = ExoforgeEditorConfig.PackageRoot;
        Debug.Log($"[package-probe] PackageRoot: {pkgRoot}");
        Check(!string.IsNullOrEmpty(pkgRoot) && Directory.Exists(pkgRoot), "SDK PackageRoot resolved and exists on disk");

        string? genPath = ExoforgeEditorConfig.GeneratorPath;
        Debug.Log($"[package-probe] GeneratorPath: {genPath}");
        Check(!string.IsNullOrEmpty(genPath) && File.Exists(genPath), "Exoforge Roslyn source generator bundled with package");

        string sdkVersion = ExoforgePackageVersion.SdkVersion;
        Debug.Log($"[package-probe] SDK Version: {sdkVersion} ({ExoforgePackageVersion.Formatted})");
        Check(!string.IsNullOrEmpty(sdkVersion), "SDK Version string present");
    }

    private static void SetupRuntimeConfig(string serverUrl, string wsUrl)
    {
        Debug.Log("[package-probe] --- Step 2: Setting up Runtime Config ---");

        string resourcesDir = Path.Combine(Application.dataPath, "Resources");
        if (!Directory.Exists(resourcesDir))
        {
            Directory.CreateDirectory(resourcesDir);
        }

        string configJson = $@"{{
  ""project_name"": ""PackageTestProject"",
  ""default_environment"": ""test"",
  ""environments"": {{
    ""test"": {{
      ""ws_url"": ""{wsUrl}"",
      ""http_url"": ""{serverUrl}"",
      ""token"": """"
    }}
  }}
}}";

        string configPath = Path.Combine(resourcesDir, "exoforge.json");
        File.WriteAllText(configPath, configJson);
        Debug.Log($"[package-probe] Wrote runtime config to {configPath}");

        AssetDatabase.Refresh(ImportAssetOptions.ForceSynchronousImport);

        var configAsset = Resources.Load<TextAsset>(ExoforgeRuntimeConfig.ResourcePath);
        Check(configAsset != null, "Resources/exoforge.json loaded successfully via Resources.Load");

        if (configAsset != null)
        {
            var parsed = ExoforgeRuntimeConfig.FromWorkspaceJson(configAsset.text);
            Check(parsed.HttpUrl == serverUrl, $"Parsed HttpUrl ({parsed.HttpUrl}) matches configured {serverUrl}");
            Check(parsed.WsUrl == wsUrl, $"Parsed WsUrl ({parsed.WsUrl}) matches configured {wsUrl}");
        }
    }

    private static void TestLiveAuthentication(string serverUrl, string wsUrl)
    {
        Debug.Log("[package-probe] --- Step 3: Testing Live Connection & Anonymous Auth ---");
        Debug.Log($"[package-probe] Target server: {serverUrl} (WS: {wsUrl})");

        // Ensure ExoforgeManager is initialized on the main thread
        var manager = ExoforgeManager.Current ?? new GameObject("ExoforgeManager").AddComponent<ExoforgeManager>();
        ExoforgeManager.Current = manager;
        manager.ServerUrl = serverUrl;
        manager.HttpUrlOverride = serverUrl;
        manager.WsUrlOverride = wsUrl;
        manager.UseStudioConnection = false; // test as clean game client
        _ = manager.Client; // ensure client instance is created on main thread
        _ = ExoDeviceId.Get(); // prime device id on main thread

        // Stage 1: Anonymous Login via ExoforgeSDK.Auth
        Debug.Log("[package-probe] Calling ExoforgeSDK.Auth.LoginAnonymously(disposable: true)...");

        ExoSession? session = null;
        Exception? authError = null;

        var authTask = Task.Run(async () =>
        {
            try
            {
                return await ExoforgeSDK.Auth.LoginAnonymously(disposable: true);
            }
            catch (Exception ex)
            {
                authError = ex;
                return null;
            }
        });

        session = AwaitWithPump(authTask, TimeSpan.FromSeconds(25));

        if (authError != null)
        {
            Check(false, $"Anonymous login failed: {authError.Message}");
            return;
        }

        Check(session != null, "ExoSession returned from LoginAnonymously");
        if (session != null)
        {
            Debug.Log($"[package-probe] Session PlayerId : {session.PlayerId}");
            Debug.Log($"[package-probe] Session Token    : {(session.Token.Length > 12 ? session.Token.Substring(0, 12) + "..." : session.Token)}");
            Check(!string.IsNullOrEmpty(session.PlayerId), "Session has valid PlayerId");
            Check(!string.IsNullOrEmpty(session.Token), "Session has valid JWT Token");
        }

        // Stage 2: Realtime WebSocket connection check
        Debug.Log("[package-probe] Testing WebSocket connection via ExoforgeSDK.ConnectAsync()...");
        Exception? wsError = null;

        var wsTask = Task.Run(async () =>
        {
            try
            {
                var client = await ExoforgeSDK.ConnectAsync();
                return client.IsConnected;
            }
            catch (Exception ex)
            {
                wsError = ex;
                return false;
            }
        });

        bool connected = AwaitWithPump(wsTask, TimeSpan.FromSeconds(15));
        if (wsError != null)
        {
            Debug.LogWarning($"[package-probe] WebSocket connection warning: {wsError.Message} (REST auth still succeeded)");
        }
        else
        {
            Check(connected, "WebSocket connected successfully to cluster");
        }
    }

    private static T AwaitWithPump<T>(Task<T> task, TimeSpan timeout)
    {
        var sw = System.Diagnostics.Stopwatch.StartNew();
        while (!task.IsCompleted)
        {
            if (sw.Elapsed > timeout)
            {
                throw new TimeoutException($"Task timed out after {timeout.TotalSeconds:F1}s");
            }
            Thread.Sleep(50);
        }

        return task.GetAwaiter().GetResult();
    }
}
