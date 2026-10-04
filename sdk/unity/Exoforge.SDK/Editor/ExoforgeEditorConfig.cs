using System;
using System.IO;

#if UNITY_EDITOR
using UnityEditor;
using UnityEngine;
#endif

namespace Exoforge.Unity.Editor
{
/// <summary>
/// Persistent configuration and preferences for the Exoforge Unity Editor Studio.
/// Compiles both inside Unity (EditorPrefs) and outside it (in-memory fallback), so
/// non-Unity management tests can link this file without a Unity reference.
/// </summary>
public static class ExoforgeEditorConfig
{
    private const string ServerUrlKey = "Exoforge_ServerUrl";
    private const string AdminTokenKey = "Exoforge_AdminToken";
    private const string WorkspacePathKey = "Exoforge_WorkspacePath";
    private const string GeneratedScriptPathKey = "Exoforge_GeneratedScriptPath";
    private const string PlayerIdKey = "Exoforge_PlayerId";
    private const string ScopesKey = "Exoforge_Scopes";
    private const string LastSyncTimeKey = "Exoforge_LastSyncTime";

    public const string DefaultServerUrl = "ws://127.0.0.1:4000/ws";
    public const string DefaultAdminToken = "dev:developer";
    public const string DefaultWorkspaceRelPath = "Exoforge";
    public const string DefaultGeneratedScriptRelPath = "Assets/Exoforge/Generated/ExoforgeServices.g.cs";

    public static readonly (string Name, string Url)[] EnvironmentPresets = new[]
    {
        ("local", "ws://127.0.0.1:4000/ws"),
        ("dev", "wss://dev.exoforge.game/ws"),
        ("staging", "wss://staging.exoforge.game/ws"),
        ("production", "wss://api.exoforge.game/ws")
    };

    public static readonly (string Label, string Token)[] TokenPresets = new[]
    {
        ("Dev", "dev:developer"),
        ("Admin", "dev:admin"),
        ("Guest", "guest")
    };

    public static bool IsLocalUrl(string url)
    {
        if (string.IsNullOrEmpty(url)) return false;
        return url.Contains("127.0.0.1:4000") || url.Contains("localhost:4000");
    }

#if !UNITY_EDITOR
    private static string _fallbackServerUrl = DefaultServerUrl;
    private static string _fallbackAdminToken = DefaultAdminToken;
    private static string _fallbackWorkspacePath = DefaultWorkspaceRelPath;
    private static string _fallbackGeneratedPath = DefaultGeneratedScriptRelPath;
    private static string _fallbackPlayerId = "";
    private static string _fallbackScopes = "";
    private static string _fallbackLastSyncTime = "";
#endif

    public static string ServerUrl
    {
        get
        {
#if UNITY_EDITOR
            return EditorPrefs.GetString(ServerUrlKey, DefaultServerUrl);
#else
            return _fallbackServerUrl;
#endif
        }
        set
        {
#if UNITY_EDITOR
            EditorPrefs.SetString(ServerUrlKey, value ?? DefaultServerUrl);
#else
            _fallbackServerUrl = value ?? DefaultServerUrl;
#endif
        }
    }

    public static string AdminToken
    {
        get
        {
#if UNITY_EDITOR
            return EditorPrefs.GetString(AdminTokenKey, DefaultAdminToken);
#else
            return _fallbackAdminToken;
#endif
        }
        set
        {
            string val = value ?? string.Empty;
#if UNITY_EDITOR
            EditorPrefs.SetString(AdminTokenKey, val);
            PlayerPrefs.SetString("Exoforge.Token", val);
            PlayerPrefs.Save();
#else
            _fallbackAdminToken = val;
#endif
        }
    }

    public static string PlayerId
    {
        get
        {
#if UNITY_EDITOR
            return EditorPrefs.GetString(PlayerIdKey, string.Empty);
#else
            return _fallbackPlayerId;
#endif
        }
        set
        {
            string val = value ?? string.Empty;
#if UNITY_EDITOR
            EditorPrefs.SetString(PlayerIdKey, val);
            PlayerPrefs.SetString("Exoforge.PlayerId", val);
            PlayerPrefs.Save();
#else
            _fallbackPlayerId = val;
#endif
        }
    }

    public static string Scopes
    {
        get
        {
#if UNITY_EDITOR
            return EditorPrefs.GetString(ScopesKey, string.Empty);
#else
            return _fallbackScopes;
#endif
        }
        set
        {
            string val = value ?? string.Empty;
#if UNITY_EDITOR
            EditorPrefs.SetString(ScopesKey, val);
            PlayerPrefs.SetString("Exoforge.Scopes", val);
            PlayerPrefs.Save();
#else
            _fallbackScopes = val;
#endif
        }
    }

    public static string LastSyncTime
    {
        get
        {
#if UNITY_EDITOR
            return EditorPrefs.GetString(LastSyncTimeKey, string.Empty);
#else
            return _fallbackLastSyncTime;
#endif
        }
        set
        {
#if UNITY_EDITOR
            EditorPrefs.SetString(LastSyncTimeKey, value ?? string.Empty);
#else
            _fallbackLastSyncTime = value ?? string.Empty;
#endif
        }
    }

    public static string WorkspacePath
    {
        get
        {
#if UNITY_EDITOR
            return EditorPrefs.GetString(WorkspacePathKey, DefaultWorkspaceRelPath);
#else
            return _fallbackWorkspacePath;
#endif
        }
        set
        {
#if UNITY_EDITOR
            EditorPrefs.SetString(WorkspacePathKey, value ?? DefaultWorkspaceRelPath);
#else
            _fallbackWorkspacePath = value ?? DefaultWorkspaceRelPath;
#endif
        }
    }

    public static string GeneratedScriptPath
    {
        get
        {
#if UNITY_EDITOR
            return EditorPrefs.GetString(GeneratedScriptPathKey, DefaultGeneratedScriptRelPath);
#else
            return _fallbackGeneratedPath;
#endif
        }
        set
        {
#if UNITY_EDITOR
            EditorPrefs.SetString(GeneratedScriptPathKey, value ?? DefaultGeneratedScriptRelPath);
#else
            _fallbackGeneratedPath = value ?? DefaultGeneratedScriptRelPath;
#endif
        }
    }

    public static void SaveSession(string token, string? playerId = null, System.Collections.Generic.IEnumerable<string>? scopes = null)
    {
        AdminToken = token;
        PlayerId = playerId ?? string.Empty;
        Scopes = scopes != null ? string.Join(",", scopes) : string.Empty;
    }

    public static void ClearSession()
    {
        AdminToken = string.Empty;
        PlayerId = string.Empty;
        Scopes = string.Empty;
#if UNITY_EDITOR
        PlayerPrefs.DeleteKey("Exoforge.Token");
        PlayerPrefs.DeleteKey("Exoforge.PlayerId");
        PlayerPrefs.DeleteKey("Exoforge.Scopes");
        PlayerPrefs.Save();
#endif
    }

    /// <summary>Resolves the absolute path to the `/exoforge` workspace folder.</summary>
    public static string GetAbsoluteWorkspacePath()
    {
#if UNITY_EDITOR
        string projectRoot = Path.GetFullPath(Path.Combine(Application.dataPath, ".."));
        return Path.GetFullPath(Path.Combine(projectRoot, WorkspacePath));
#else
        return Path.GetFullPath(WorkspacePath);
#endif
    }

    /// <summary>Resolves the absolute path to the generated C# client file.</summary>
    public static string GetAbsoluteGeneratedScriptPath()
    {
#if UNITY_EDITOR
        string projectRoot = Path.GetFullPath(Path.Combine(Application.dataPath, ".."));
        return Path.GetFullPath(Path.Combine(projectRoot, GeneratedScriptPath));
#else
        return Path.GetFullPath(GeneratedScriptPath);
#endif
    }
}
}
