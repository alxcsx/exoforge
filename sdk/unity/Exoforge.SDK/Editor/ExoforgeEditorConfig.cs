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
    private const string DotnetPathKey = "Exoforge_DotnetPath"; // machine-global, not per-project

    // Per-project keys: suffixed with the project name so separate projects don't share
    // session/credentials. Keyed by product name (not folder path) so duplicated copies of the
    // same project share one login.
    private static string ServerUrlKey => Scoped("Exoforge_ServerUrl");
    private static string AdminTokenKey => Scoped("Exoforge_AdminToken");
    private static string WorkspacePathKey => Scoped("Exoforge_WorkspacePath");
    private static string GeneratedScriptPathKey => Scoped("Exoforge_GeneratedScriptPath");
    private static string PlayerIdKey => Scoped("Exoforge_PlayerId");
    private static string ScopesKey => Scoped("Exoforge_Scopes");
    private static string LastSyncTimeKey => Scoped("Exoforge_LastSyncTime");
    private static string LoginEmailKey => Scoped("Exoforge_LoginEmail");
    private static string LoginPasswordKey => Scoped("Exoforge_LoginPassword");

    public const string DefaultServerUrl = "ws://127.0.0.1:4000/ws";
    public const string DefaultAdminToken = "dev:developer";
    public const string DefaultLoginEmail = "dev@exoforge.game";
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
    private static string _fallbackDotnetPath = "dotnet";
    private static string _fallbackLoginEmail = DefaultLoginEmail;
    private static string _fallbackLoginPassword = "";

    private static string Scoped(string key) => key;
#else
    private static string? _projectScope;

    /// <summary>
    /// One login per project name. Multiple copies of the same project (same product name) share it;
    /// different projects don't bleed credentials into each other.
    /// </summary>
    private static string ProjectScope
    {
        get
        {
            if (_projectScope == null)
            {
                string name = Application.productName;
                if (string.IsNullOrWhiteSpace(name))
                {
                    name = Path.GetFileName(Path.GetFullPath(Path.Combine(Application.dataPath, "..")));
                }

                char[] chars = name.ToCharArray();
                for (int i = 0; i < chars.Length; i++)
                {
                    if (!char.IsLetterOrDigit(chars[i])) chars[i] = '_';
                }

                _projectScope = new string(chars);
            }

            return _projectScope;
        }
    }

    private static string Scoped(string key) => $"{key}_{ProjectScope}";
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

    /// <summary>Path to the dotnet CLI used for native plugin builds. May be absolute if it is not on PATH.</summary>
    public static string DotnetPath
    {
        get
        {
#if UNITY_EDITOR
            return EditorPrefs.GetString(DotnetPathKey, "dotnet");
#else
            return _fallbackDotnetPath;
#endif
        }
        set
        {
#if UNITY_EDITOR
            EditorPrefs.SetString(DotnetPathKey, string.IsNullOrWhiteSpace(value) ? "dotnet" : value);
#else
            _fallbackDotnetPath = string.IsNullOrWhiteSpace(value) ? "dotnet" : value;
#endif
        }
    }

    /// <summary>
    /// Last email used in the Control Center's <c>auth.login</c> form, persisted in per-user
    /// EditorPrefs so the form does not reset (and is never committed to the project).
    /// </summary>
    public static string LastLoginEmail
    {
        get
        {
#if UNITY_EDITOR
            return EditorPrefs.GetString(LoginEmailKey, DefaultLoginEmail);
#else
            return _fallbackLoginEmail;
#endif
        }
        set
        {
#if UNITY_EDITOR
            EditorPrefs.SetString(LoginEmailKey, value ?? DefaultLoginEmail);
#else
            _fallbackLoginEmail = value ?? DefaultLoginEmail;
#endif
        }
    }

    /// <summary>
    /// Dev login password, kept in per-user EditorPrefs (plaintext, outside the repo) so the
    /// Control Center can reconnect without retyping. Cleared on log out.
    /// </summary>
    public static string RememberedPassword
    {
        get
        {
#if UNITY_EDITOR
            return EditorPrefs.GetString(LoginPasswordKey, string.Empty);
#else
            return _fallbackLoginPassword;
#endif
        }
        set
        {
#if UNITY_EDITOR
            EditorPrefs.SetString(LoginPasswordKey, value ?? string.Empty);
#else
            _fallbackLoginPassword = value ?? string.Empty;
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
        RememberedPassword = string.Empty;
#if UNITY_EDITOR
        PlayerPrefs.DeleteKey("Exoforge.Token");
        PlayerPrefs.DeleteKey("Exoforge.PlayerId");
        PlayerPrefs.DeleteKey("Exoforge.Scopes");
        PlayerPrefs.Save();
#endif
    }

    /// <summary>
    /// The Unity project root, always absolute.
    ///
    /// `Application.dataPath` is documented as absolute but is relative in some batchmode
    /// launches, and when it is, `Path.GetFullPath` keeps it relative (it resolves against the
    /// current directory, which is relative too). Every path derived from it then depends on the
    /// process's working directory: `Directory.Exists` checks pass against one base and the
    /// `dotnet` subprocess resolves against another, so a plugin build fails with
    /// "The provided file path does not exist".
    ///
    /// This assembly's own location is always absolute, so it is the reliable anchor.
    /// </summary>
    private static string ProjectRoot
    {
        get
        {
#if UNITY_EDITOR
            // Candidate project roots, best first. <project>/Library/ScriptAssemblies/<assembly>.dll
            // and Application.dataPath are both "<project>/...", so their parents are the root.
            string assemblyDir = Path.GetDirectoryName(typeof(ExoforgeEditorConfig).Assembly.Location) ?? "";

            var candidates = new[]
            {
                Path.Combine(assemblyDir, "..", ".."),
                Path.Combine(Application.dataPath, ".."),
            };

            // Validate by existence rather than by Path.IsPathRooted: Unity's Mono reports a bare
            // relative path as rooted, so rootedness says nothing, and Path.GetFullPath then returns
            // the path unchanged. Whichever candidate actually contains this project's Assets folder
            // is the one whose paths will resolve consistently.
            foreach (string candidate in candidates)
            {
                string root = Path.GetFullPath(candidate);

                if (Directory.Exists(Path.Combine(root, "Assets")))
                {
                    return root;
                }
            }

            return Path.GetFullPath(Path.Combine(Application.dataPath, ".."));
#else
            return Path.GetFullPath(".");
#endif
        }
    }

    /// <summary>
    /// The directory this SDK was installed into — a UPM package, a local `file:` package, or a
    /// package-cache entry.
    ///
    /// Asked of Unity rather than searched for, so it is correct for every installation: a package
    /// installed from a tarball has no Exoforge checkout near it, and the editor assembly itself
    /// lives in <c>Library/ScriptAssemblies</c>, not in the package.
    /// </summary>
    public static string? PackageRoot
    {
        get
        {
#if UNITY_EDITOR
            var info = UnityEditor.PackageManager.PackageInfo.FindForAssembly(typeof(ExoforgeEditorConfig).Assembly);
            return info?.resolvedPath;
#else
            return null;
#endif
        }
    }

    /// <summary>
    /// The manifest generator shipped inside this SDK, or null when it is missing.
    ///
    /// A native plugin build needs it; when it is null the build says so rather than failing inside
    /// `dotnet` with a path that does not exist.
    /// </summary>
    public static string? ManifestGenPath
    {
        get
        {
            string? root = PackageRoot;

            if (string.IsNullOrEmpty(root))
            {
                return null;
            }

            string candidate = Path.Combine(root!, "Editor", "Management", "Tools~", "ManifestGen");
            return File.Exists(Path.Combine(candidate, "ManifestGen.csproj")) ? candidate : null;
        }
    }

    /// <summary>Resolves the absolute path to the `/exoforge` workspace folder.</summary>
    public static string GetAbsoluteWorkspacePath() =>
        Path.GetFullPath(Path.Combine(ProjectRoot, WorkspacePath));

    /// <summary>Resolves the absolute path to the generated C# client file.</summary>
    public static string GetAbsoluteGeneratedScriptPath() =>
        Path.GetFullPath(Path.Combine(ProjectRoot, GeneratedScriptPath));
}
}
