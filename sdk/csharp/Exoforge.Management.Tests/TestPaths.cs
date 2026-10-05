using System;
using System.IO;

namespace Exoforge.Management.Tests;

/// <summary>Locations the tests need that are not part of the temp workspace.</summary>
internal static class TestPaths
{
    /// <summary>
    /// The SDK project a scaffolded plugin references. Found by walking up from the test binary to
    /// the repo root, so tests never depend on the silent PackageReference fallback.
    /// </summary>
    public static string PluginSdkProject { get; } = Find();

    private static string Find()
    {
        string? dir = AppContext.BaseDirectory;

        for (int i = 0; i < 12 && dir != null; i++)
        {
            string candidate = Path.Combine(dir, "sdk", "csharp", "Exoforge.Plugin.SDK", "Exoforge.Plugin.SDK.csproj");
            if (File.Exists(candidate)) return candidate;

            dir = Directory.GetParent(dir)?.FullName;
        }

        throw new InvalidOperationException("Could not locate Exoforge.Plugin.SDK from the test output directory.");
    }
}
