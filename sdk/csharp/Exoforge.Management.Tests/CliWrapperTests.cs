using System;
using System.IO;
using Xunit;

namespace Exoforge.Management.Tests;

public class CliWrapperTests : IDisposable
{
    private readonly string _tempDir;
    public CliWrapperTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), $"exo_cli_wrapper_{Guid.NewGuid():N}");
        Directory.CreateDirectory(_tempDir);
    }
    public void Dispose()
    {
        try { if (Directory.Exists(_tempDir)) Directory.Delete(_tempDir, true); } catch { }
    }

    [Fact]
    public void Install_CreatesExoAndExoCmd()
    {
        var r = ExoCliInstaller.Install(_tempDir);
        Assert.True(File.Exists(Path.Combine(_tempDir, "exo")));
        Assert.True(File.Exists(Path.Combine(_tempDir, "exo.cmd")));
    }

    [Fact]
    public void Install_CreatesNoAiFiles()
    {
        ExoCliInstaller.Install(_tempDir);
        Assert.False(Directory.Exists(Path.Combine(_tempDir, ".agents")));
        Assert.False(Directory.Exists(Path.Combine(_tempDir, ".claude")));
        Assert.False(Directory.Exists(Path.Combine(_tempDir, ".gemini")));
        Assert.False(File.Exists(Path.Combine(_tempDir, "AGENTS.md")));
    }

    [Fact]
    public void Install_IdempotentSecondRunNoChanges()
    {
        ExoCliInstaller.Install(_tempDir);
        var r2 = ExoCliInstaller.Install(_tempDir);
        Assert.Empty(r2.UpdatedFiles);
    }

    [Fact]
    public void Install_GitignoreBlockOnceAfterAgentInstall()
    {
        ExoAgentInstaller.Install(_tempDir, new[] { "all" });
        ExoCliInstaller.Install(_tempDir);
        string gi = File.ReadAllText(Path.Combine(_tempDir, ".gitignore"));
        int count = 0, idx = 0;
        while ((idx = gi.IndexOf("# >>> EXOFORGE-CLI:START", idx, StringComparison.Ordinal)) >= 0) { count++; idx += 1; }
        Assert.Equal(1, count);
    }

    [Fact]
    public void ShellWrapper_ContainsPackageCacheGlob()
    {
        ExoCliInstaller.Install(_tempDir);
        string content = File.ReadAllText(Path.Combine(_tempDir, "exo"));
        Assert.Contains("Library/PackageCache/com.exoforge.sdk@*", content);
    }
}