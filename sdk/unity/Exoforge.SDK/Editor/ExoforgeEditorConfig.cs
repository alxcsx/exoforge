using System;
using System.IO;

#if UNITY_EDITOR
using UnityEditor;
using UnityEngine;
#endif

namespace Exoforge.Unity.Editor;

/// <summary>
/// Manages persistent configuration and preferences for the Exoforge Unity Editor Studio.
/// </summary>
public static class ExoforgeEditorConfig
{
    private const string ServerUrlKey = "Exoforge_ServerUrl";
    private const string AdminTokenKey = "Exoforge_AdminToken";
    private const string WorkspacePathKey = "Exoforge_WorkspacePath";
    private const string GeneratedScriptPathKey = "Exoforge_GeneratedScriptPath";

    public const string DefaultServerUrl = "ws://localhost:4000/ws";
    public const string DefaultAdminToken = "admin";
    public const string DefaultWorkspaceRelPath = "exoforge";
    public const string DefaultGeneratedScriptRelPath = "Assets/Exoforge/Generated/ExoforgeServices.g.cs";

    private static string _fallbackServerUrl = DefaultServerUrl;
    private static string _fallbackAdminToken = DefaultAdminToken;
    private static string _fallbackWorkspacePath = DefaultWorkspaceRelPath;
    private static string _fallbackGeneratedPath = DefaultGeneratedScriptRelPath;

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
            EditorPrefs.SetString(ServerUrlKey, value);
#else
            _fallbackServerUrl = value;
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
#if UNITY_EDITOR
            EditorPrefs.SetString(AdminTokenKey, value);
#else
            _fallbackAdminToken = value;
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
            EditorPrefs.SetString(WorkspacePathKey, value);
#else
            _fallbackWorkspacePath = value;
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
            EditorPrefs.SetString(GeneratedScriptPathKey, value);
#else
            _fallbackGeneratedPath = value;
#endif
        }
    }

    /// <summary>
    /// Resolves the absolute path to the `/exoforge` workspace folder.
    /// </summary>
    public static string GetAbsoluteWorkspacePath()
    {
#if UNITY_EDITOR
        string projectRoot = Path.GetFullPath(Path.Combine(Application.dataPath, ".."));
        return Path.GetFullPath(Path.Combine(projectRoot, WorkspacePath));
#else
        return Path.GetFullPath(WorkspacePath);
#endif
    }

    /// <summary>
    /// Resolves the absolute path to the generated C# client file.
    /// </summary>
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
