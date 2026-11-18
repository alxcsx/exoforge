using System;
using System.IO;
using Xunit;
using Exoforge.Management;

namespace Exoforge.Management.Tests;

public class FeedMigrationTests : IDisposable
{
    private readonly string _tempDir;

    public FeedMigrationTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), $"exo_feed_mig_{Guid.NewGuid():N}");
        Directory.CreateDirectory(_tempDir);
    }

    public void Dispose()
    {
        try { if (Directory.Exists(_tempDir)) Directory.Delete(_tempDir, true); } catch { }
    }

    [Fact]
    public void NeedsFeedMigration_Returns_True_When_Root_NugetConfig_Is_Not_Static_Feed()
    {
        string workspace = Path.Combine(_tempDir, "Exoforge");
        Directory.CreateDirectory(workspace);
        File.WriteAllText(
            Path.Combine(workspace, "nuget.config"),
            "<configuration><packageSources><add key=\"exoforge\" value=\"/old/cache/path\" /></packageSources></configuration>");

        Assert.True(ExoScaffolder.NeedsFeedMigration(workspace));
    }

    [Fact]
    public void NeedsFeedMigration_Returns_True_When_Extension_NugetConfig_Exists()
    {
        string workspace = Path.Combine(_tempDir, "Exoforge");
        string ext = Path.Combine(workspace, "extensions", "snake_game");
        Directory.CreateDirectory(ext);
        File.WriteAllText(Path.Combine(workspace, "nuget.config"), ExoScaffolder.NugetConfigContent);
        File.WriteAllText(
            Path.Combine(ext, "nuget.config"),
            "<configuration><packageSources><add key=\"exoforge\" value=\"/old/cache/path\" /></packageSources></configuration>");

        Assert.True(ExoScaffolder.NeedsFeedMigration(workspace));
    }

    [Fact]
    public void NeedsFeedMigration_Returns_False_For_Clean_Feed_Workspace()
    {
        string workspace = Path.Combine(_tempDir, "Exoforge");
        string extSrc = Path.Combine(workspace, "extensions", "snake_game", "src");
        Directory.CreateDirectory(extSrc);
        File.WriteAllText(Path.Combine(workspace, "nuget.config"), ExoScaffolder.NugetConfigContent);

        Assert.False(ExoScaffolder.NeedsFeedMigration(workspace));
    }

    [Fact]
    public void NeedsFeedMigration_Returns_False_When_Workspace_Does_Not_Exist()
    {
        string workspace = Path.Combine(_tempDir, "missing");
        Assert.False(ExoScaffolder.NeedsFeedMigration(workspace));
    }

    [Fact]
    public void NeedsFeedMigration_Becomes_False_After_Feed_Migration()
    {
        string workspace = Path.Combine(_tempDir, "Exoforge");
        string ext = Path.Combine(workspace, "extensions", "snake_game");
        Directory.CreateDirectory(ext);
        File.WriteAllText(Path.Combine(workspace, "nuget.config"), "<configuration />");
        File.WriteAllText(
            Path.Combine(ext, "nuget.config"),
            "<configuration><packageSources><add key=\"exoforge\" value=\"/old/cache/path\" /></packageSources></configuration>");

        Assert.True(ExoScaffolder.NeedsFeedMigration(workspace));

        ExoScaffolder.EnsureBuildFeed(workspace, ext);

        Assert.False(ExoScaffolder.NeedsFeedMigration(workspace));
    }
}
