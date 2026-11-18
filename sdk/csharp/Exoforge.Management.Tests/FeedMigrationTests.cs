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
            "<configuration><packageSources><add key=\"exoforge\" value=\"/proj/Library/PackageCache/com.exoforge.sdk/Editor/Plugins/NuGet~\" /></packageSources></configuration>");

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
            "<configuration><packageSources><add key=\"exoforge\" value=\"/proj/Library/PackageCache/com.exoforge.sdk/Editor/Plugins/NuGet~\" /></packageSources></configuration>");

        Assert.True(ExoScaffolder.NeedsFeedMigration(workspace));

        ExoScaffolder.EnsureBuildFeed(workspace, ext);

        Assert.False(ExoScaffolder.NeedsFeedMigration(workspace));
    }

    [Fact]
    public void NeedsFeedMigration_IgnoresUserPrivateNugetConfigs_AndStaysFalseAcrossConsecutiveChecks()
    {
        string workspace = Path.Combine(_tempDir, "Exoforge");
        string ext = Path.Combine(workspace, "extensions", "snake_game");
        string nested = Path.Combine(ext, "src");
        Directory.CreateDirectory(nested);
        File.WriteAllText(Path.Combine(workspace, "nuget.config"), "<configuration />");

        // User's private feed at extension root (no key="exoforge") and deeper nuget.config
        string privateConfig = "<configuration><packageSources><add key=\"my-private\" value=\"https://pkgs.example.com\" /></packageSources></configuration>";
        string topPrivatePath = Path.Combine(ext, "nuget.config");
        string deepConfigPath = Path.Combine(nested, "nuget.config");
        File.WriteAllText(topPrivatePath, privateConfig);
        File.WriteAllText(deepConfigPath, privateConfig);

        ExoScaffolder.EnsureBuildFeed(workspace, ext);

        Assert.True(File.Exists(topPrivatePath));
        Assert.True(File.Exists(deepConfigPath));
        Assert.False(ExoScaffolder.NeedsFeedMigration(workspace));
        Assert.False(ExoScaffolder.NeedsFeedMigration(workspace));
    }

    [Fact]
    public void NeedsFeedMigration_IgnoresCrlfLineEndingsInWorkspaceNugetConfig()
    {
        string workspace = Path.Combine(_tempDir, "Exoforge");
        Directory.CreateDirectory(workspace);
        File.WriteAllText(
            Path.Combine(workspace, "nuget.config"),
            ExoScaffolder.NugetConfigContent.Replace("\n", "\r\n"));

        Assert.False(ExoScaffolder.NeedsFeedMigration(workspace));
    }

    [Fact]
    public void NeedsFeedMigration_IgnoresCustomExoforgeSourceNotInPackageCacheOrPluginsNuGet()
    {
        string workspace = Path.Combine(_tempDir, "Exoforge");
        string ext = Path.Combine(workspace, "extensions", "snake_game");
        Directory.CreateDirectory(ext);
        File.WriteAllText(Path.Combine(workspace, "nuget.config"), ExoScaffolder.NugetConfigContent);
        string customConfig = "<configuration><packageSources><add key=\"exoforge\" value=\"https://custom.example.com/nuget/v3/index.json\" /></packageSources></configuration>";
        string extConfigPath = Path.Combine(ext, "nuget.config");
        File.WriteAllText(extConfigPath, customConfig);

        Assert.False(ExoScaffolder.NeedsFeedMigration(workspace));
        ExoScaffolder.EnsureBuildFeed(workspace, ext);
        Assert.True(File.Exists(extConfigPath));
    }

    [Fact]
    public void NeedsFeedMigration_Returns_True_When_An_Extension_Config_Names_A_Feed_Folder_That_Is_Gone()
    {
        string workspace = Path.Combine(_tempDir, "Exoforge");
        string ext = Path.Combine(workspace, "extensions", "loja_itens");
        Directory.CreateDirectory(ext);
        File.WriteAllText(Path.Combine(workspace, "nuget.config"), ExoScaffolder.NugetConfigContent);
        File.WriteAllText(
            Path.Combine(ext, "nuget.config"),
            "<configuration><packageSources><add key=\"exoforge\" value=\"/Users/someone/old-checkout/dist/nuget\" /></packageSources></configuration>");

        Assert.True(ExoScaffolder.NeedsFeedMigration(workspace));
    }

    [Fact]
    public void NeedsFeedMigration_Leaves_A_User_Feed_That_Exists_Or_Is_A_Url()
    {
        string workspace = Path.Combine(_tempDir, "Exoforge");
        string ext = Path.Combine(workspace, "extensions", "shop");
        string privateFeed = Path.Combine(_tempDir, "private-feed");
        Directory.CreateDirectory(ext);
        Directory.CreateDirectory(privateFeed);
        File.WriteAllText(Path.Combine(workspace, "nuget.config"), ExoScaffolder.NugetConfigContent);
        File.WriteAllText(
            Path.Combine(ext, "nuget.config"),
            $"<configuration><packageSources><add key=\"exoforge\" value=\"{privateFeed}\" /></packageSources></configuration>");

        Assert.False(ExoScaffolder.NeedsFeedMigration(workspace));

        File.WriteAllText(
            Path.Combine(ext, "nuget.config"),
            "<configuration><packageSources><add key=\"exoforge\" value=\"https://nuget.example.com/v3/index.json\" /></packageSources></configuration>");

        Assert.False(ExoScaffolder.NeedsFeedMigration(workspace));
    }
}
