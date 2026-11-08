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
    private static string SelectedEnvironmentKey => Scoped("Exoforge_Environment");
    /// <summary>
    /// Which environment in exoforge.json the editor is pointed at.
    ///
    /// Only the *selection* is editor-local. The URLs and the token live in the workspace config,
    /// which is the source of truth — they used to be mirrored into EditorPrefs and into the token
    /// store, which is three places to configure one thing and three ways for them to disagree.
    /// </summary>
    public static string SelectedEnvironment
    {
        get
        {
#if UNITY_EDITOR
            return EditorPrefs.GetString(SelectedEnvironmentKey, "local");
#else
            return _fallbackSelectedEnvironment;
#endif
        }
        set
        {
#if UNITY_EDITOR
            EditorPrefs.SetString(SelectedEnvironmentKey, value ?? "local");
#else
            _fallbackSelectedEnvironment = value ?? "local";
#endif
        }
    }

    private static string WorkspacePathKey => Scoped("Exoforge_WorkspacePath");
    private static string GeneratedScriptPathKey => Scoped("Exoforge_GeneratedScriptPath");
    private static string LastSyncTimeKey => Scoped("Exoforge_LastSyncTime");
    private static string AutoGenerateStubsOnBuildKey => Scoped("Exoforge_AutoGenerateStubsOnBuild");
    private static string LoginEmailKey => Scoped("Exoforge_LoginEmail");
    private static string LoginPasswordKey => Scoped("Exoforge_LoginPassword");
    private static string InitialSetupCompletedKey => Scoped("Exoforge_InitialSetupCompleted");

    /// <summary>
    /// Whether initial cluster setup has been completed (prompting for Base URL on first install).
    /// </summary>
    public static bool HasCompletedInitialSetup
    {
        get
        {
#if UNITY_EDITOR
            return EditorPrefs.GetBool(InitialSetupCompletedKey, false);
#else
            return _fallbackInitialSetupCompleted;
#endif
        }
        set
        {
#if UNITY_EDITOR
            EditorPrefs.SetBool(InitialSetupCompletedKey, value);
#else
            _fallbackInitialSetupCompleted = value;
#endif
        }
    }

    public const string DefaultLoginEmail = "";
    public const string DefaultWorkspaceRelPath = "Exoforge";
    public const string DefaultGeneratedScriptRelPath = "Assets/Exoforge/Generated/ExoforgeServices.g.cs";

    // No Guest preset (M33 Fix 14): the Studio is staff tooling, and a guest token is a session
    // a player mints for itself - never one the editor signs in with.
    public static readonly (string Label, string Token)[] TokenPresets = Array.Empty<(string Label, string Token)>();

    /// <summary>True when the endpoint is on this machine. Uses the URI rather than a port literal.</summary>
    public static bool IsLocalUrl(string url)
    {
        return Uri.TryCreate(url, UriKind.Absolute, out var uri) && uri.IsLoopback;
    }

    /// <summary>
    /// Infers WebSocket and HTTP REST endpoints from a single Base URL or hostname (e.g. "exof1.alexcs.me" or "localhost").
    /// </summary>
    public static void DeriveEndpoints(string? input, out string wsUrl, out string httpUrl)
    {
        if (string.IsNullOrWhiteSpace(input))
        {
            wsUrl = "";
            httpUrl = "";
            return;
        }

        string trimmed = input.Trim().TrimEnd('/');
        string raw = trimmed;

        bool hasExplicitScheme = raw.Contains("://");
        string scheme = "";
        if (hasExplicitScheme)
        {
            int idx = raw.IndexOf("://", StringComparison.Ordinal);
            scheme = raw.Substring(0, idx).ToLowerInvariant();
            raw = raw.Substring(idx + 3);
        }

        bool isLoopback = raw.StartsWith("localhost", StringComparison.OrdinalIgnoreCase) ||
                          raw.StartsWith("127.0.0.1", StringComparison.OrdinalIgnoreCase) ||
                          raw.StartsWith("[::1]", StringComparison.OrdinalIgnoreCase);

        if (string.IsNullOrEmpty(scheme))
        {
            scheme = isLoopback ? "http" : "https";
        }

        bool isSecure = scheme.Equals("https", StringComparison.OrdinalIgnoreCase) ||
                        scheme.Equals("wss", StringComparison.OrdinalIgnoreCase);

        string httpScheme = isSecure ? "https" : "http";
        string wsScheme = isSecure ? "wss" : "ws";

        if (!Uri.TryCreate($"{httpScheme}://{raw}", UriKind.Absolute, out var uri))
        {
            wsUrl = $"{(isSecure ? "wss" : "ws")}://{trimmed}/ws";
            httpUrl = $"{(isSecure ? "https" : "http")}://{trimmed}";
            return;
        }

        string host = uri.Host;
        int port = uri.Port;
        string path = uri.AbsolutePath.TrimEnd('/');
        if (path.EndsWith("/ws", StringComparison.OrdinalIgnoreCase))
        {
            path = path.Substring(0, path.Length - 3).TrimEnd('/');
        }
        if (path.EndsWith("/api", StringComparison.OrdinalIgnoreCase))
        {
            path = path.Substring(0, path.Length - 4).TrimEnd('/');
        }

        if (isLoopback)
        {
            int wsPort = (port == 4001) ? 4000 : (uri.IsDefaultPort ? 4000 : port);
            int httpPort = (port == 4000) ? 4001 : (uri.IsDefaultPort ? 4001 : port);

            wsUrl = $"{wsScheme}://{host}:{wsPort}{path}/ws";
            httpUrl = $"{httpScheme}://{host}:{httpPort}{path}";
            return;
        }

        string portPart = uri.IsDefaultPort ? "" : $":{port}";
        httpUrl = $"{httpScheme}://{host}{portPart}{path}";
        wsUrl = $"{wsScheme}://{host}{portPart}{path}/ws";
    }

    /// <summary>
    /// Infers the cluster Base URL from existing HTTP or WebSocket endpoints.
    /// </summary>
    public static string DeriveBaseUrl(string? wsUrl, string? httpUrl)
    {
        string candidate = !string.IsNullOrWhiteSpace(httpUrl) ? httpUrl! : (wsUrl ?? "");
        if (string.IsNullOrWhiteSpace(candidate)) return "";

        if (Uri.TryCreate(candidate, UriKind.Absolute, out var uri))
        {
            string portPart = uri.IsDefaultPort ? "" : $":{uri.Port}";
            string path = uri.AbsolutePath.TrimEnd('/');
            if (path.EndsWith("/ws", StringComparison.OrdinalIgnoreCase))
            {
                path = path.Substring(0, path.Length - 3).TrimEnd('/');
            }
            if (path.EndsWith("/api", StringComparison.OrdinalIgnoreCase))
            {
                path = path.Substring(0, path.Length - 4).TrimEnd('/');
            }
            return $"{uri.Host}{portPart}{path}";
        }

        return candidate;
    }

#if !UNITY_EDITOR
    private static string _fallbackSelectedEnvironment = "local";
    private static string _fallbackWorkspacePath = DefaultWorkspaceRelPath;
    private static string _fallbackGeneratedPath = DefaultGeneratedScriptRelPath;
    private static string _fallbackLastSyncTime = "";
    private static bool _fallbackAutoGenerateStubsOnBuild = true;
    private static bool _fallbackInitialSetupCompleted = false;
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

    /// <summary>Whether to automatically regenerate typed C# plugin stubs when an extension is rebuilt.</summary>
    public static bool AutoGenerateStubsOnBuild
    {
        get
        {
#if UNITY_EDITOR
            return EditorPrefs.GetBool(AutoGenerateStubsOnBuildKey, true);
#else
            return _fallbackAutoGenerateStubsOnBuild;
#endif
        }
        set
        {
#if UNITY_EDITOR
            EditorPrefs.SetBool(AutoGenerateStubsOnBuildKey, value);
#else
            _fallbackAutoGenerateStubsOnBuild = value;
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

    private static string TargetBuildRidKey => Scoped("Exoforge_TargetBuildRid");
    private static string _fallbackTargetBuildRid = "";

    /// <summary>
    /// Explicit target RID for extension compilation (e.g. "linux-x64", "win-x64").
    /// Empty or "auto" means automatic selection (linux-x64 for cluster deploy, host RID for local).
    /// </summary>
    public static string TargetBuildRid
    {
        get
        {
#if UNITY_EDITOR
            return EditorPrefs.GetString(TargetBuildRidKey, "");
#else
            return _fallbackTargetBuildRid;
#endif
        }
        set
        {
#if UNITY_EDITOR
            EditorPrefs.SetString(TargetBuildRidKey, value ?? "");
#else
            _fallbackTargetBuildRid = value ?? "";
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
    /// Last password used in the Control Center's <c>auth.login</c> form, persisted in per-user
    /// EditorPrefs.
    /// </summary>
    public static string LastLoginPassword
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
    public static string ProjectRoot
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
    /// Path to the offline NuGet package feed bundled inside this SDK package (Editor/Plugins/NuGet~).
    /// </summary>
    public static string? BundledFeedPath
    {
        get
        {
            string? root = PackageRoot;
            if (string.IsNullOrEmpty(root)) return null;
            string candidate = Path.Combine(root!, "Editor", "Plugins", "NuGet~");
            return Directory.Exists(candidate) ? candidate : null;
        }
    }

    /// <summary>
    /// The source generator or SDK package shipped inside this SDK, or null when it is missing.
    /// </summary>
    public static string? GeneratorPath
    {
        get
        {
            string? feed = BundledFeedPath;
            if (feed != null)
            {
                string[] nupkgs = Directory.GetFiles(feed, "Exoforge.Plugin.SDK.*.nupkg");
                if (nupkgs.Length > 0) return nupkgs[0];
            }

            string? root = PackageRoot;
            if (string.IsNullOrEmpty(root))
            {
                return null;
            }

            // Tools~ fallback
            string candidate = Path.Combine(
                root!, "Editor", "Plugins", "Tools~", "Exoforge.Plugin.Generator", "Exoforge.Plugin.Generator.dll");

            return File.Exists(candidate) ? candidate : null;
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
