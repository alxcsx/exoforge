using System;
using System.IO;
using Xunit;
using Exoforge.Management;

namespace Exoforge.Management.Tests;

public class FeedTests : IDisposable
{
    private readonly string _tempDir;
    public FeedTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), $"exo_feed_{Guid.NewGuid():N}");
        Directory.CreateDirectory(_tempDir);
    }
    public void Dispose()
    {
        try { if (Directory.Exists(_tempDir)) Directory.Delete(_tempDir, true); } catch { }
    }

    [Fact]
    public void EnsureProjectFeed_Copies_Sdk_Nupkg_When_Missing()
    {
        string workspace = Path.Combine(_tempDir, "ws");
        string source = Path.Combine(_tempDir, "source");
        Directory.CreateDirectory(source);
        File.WriteAllText(Path.Combine(source, "Exoforge.Plugin.SDK.1.2.3.nupkg"), "pkg");

        string? version = ExoScaffolder.EnsureProjectFeed(workspace, source);
        Assert.Equal("1.2.3", version);
        string copied = Path.Combine(workspace, ".feed", "Exoforge.Plugin.SDK.1.2.3.nupkg");
        Assert.True(File.Exists(copied));
    }

    [Fact]
    public void EnsureProjectFeed_Leaves_Existing_Copy_Alone()
    {
        string workspace = Path.Combine(_tempDir, "ws");
        string source = Path.Combine(_tempDir, "source");
        Directory.CreateDirectory(source);
        File.WriteAllText(Path.Combine(source, "Exoforge.Plugin.SDK.1.2.3.nupkg"), "pkg");

        ExoScaffolder.EnsureProjectFeed(workspace, source);
        string copied = Path.Combine(workspace, ".feed", "Exoforge.Plugin.SDK.1.2.3.nupkg");
        File.WriteAllText(copied, "tampered");

        ExoScaffolder.EnsureProjectFeed(workspace, source);
        Assert.Equal("tampered", File.ReadAllText(copied));
    }

    [Fact]
    public void EnsureProjectFeed_Writes_NugetConfig_With_Feed_Value()
    {
        string workspace = Path.Combine(_tempDir, "ws");
        ExoScaffolder.EnsureProjectFeed(workspace);
        string cfg = Path.Combine(workspace, "nuget.config");
        Assert.True(File.Exists(cfg));
        Assert.Contains("value=\".feed\"", File.ReadAllText(cfg));
    }

    [Fact]
    public void EnsureProjectFeed_Does_Not_Rewrite_Identical_NugetConfig()
    {
        string workspace = Path.Combine(_tempDir, "ws");
        Directory.CreateDirectory(workspace);
        File.WriteAllText(Path.Combine(workspace, "nuget.config"), ExoScaffolder.NugetConfigContent);
        var before = File.GetLastWriteTimeUtc(Path.Combine(workspace, "nuget.config"));
        System.Threading.Thread.Sleep(50);
        ExoScaffolder.EnsureProjectFeed(workspace);
        var after = File.GetLastWriteTimeUtc(Path.Combine(workspace, "nuget.config"));
        Assert.Equal(before, after);
    }

    [Fact]
    public void EnsureBuildFeed_Deletes_Stale_PerExtension_NugetConfig()
    {
        string workspace = Path.Combine(_tempDir, "ws");
        string ext = Path.Combine(_tempDir, "ext");
        Directory.CreateDirectory(ext);
        File.WriteAllText(Path.Combine(ext, "nuget.config"), "<configuration><packageSources><add key=\"exoforge\" value=\"/some/other\" /></packageSources></configuration>");

        ExoScaffolder.EnsureBuildFeed(workspace, ext);
        Assert.False(File.Exists(Path.Combine(ext, "nuget.config")));
    }

    [Fact]
    public void EnsurePackageReference_Moves_Version()
    {
        string ext = Path.Combine(_tempDir, "ext");
        string src = Path.Combine(ext, "src");
        Directory.CreateDirectory(src);
        File.WriteAllText(Path.Combine(src, "foo.csproj"), "<Project><ItemGroup><PackageReference Include=\"Exoforge.Plugin.SDK\" Version=\"0.0.1\" /></ItemGroup></Project>");

        bool changed = ExoScaffolder.EnsurePackageReference(ext, "9.9.9");
        Assert.True(changed);
        Assert.Contains("Version=\"9.9.9\"", File.ReadAllText(Path.Combine(src, "foo.csproj")));
    }
}
