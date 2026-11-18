using System;
using System.IO;
using Xunit;
using Exoforge.Management;

namespace Exoforge.Management.Tests;

public class ExoWorkspacePathTests : IDisposable
{
    private readonly string _tempDir;

    public ExoWorkspacePathTests()
    {
        _tempDir = Path.Combine(Path.GetTempPath(), $"exo_wp_{Guid.NewGuid():N}");
        Directory.CreateDirectory(_tempDir);
    }

    public void Dispose()
    {
        try { if (Directory.Exists(_tempDir)) Directory.Delete(_tempDir, true); } catch { }
    }

    private ExoWorkspace Make(string extensionsDir)
    {
        var cfg = new ExoProjectConfig { ExtensionsDir = extensionsDir };
        return new ExoWorkspace(_tempDir, cfg);
    }

    private static string Norm(string p) => Path.GetFullPath(p);

    [Theory]
    [InlineData("../../extensions")]
    [InlineData("../extensions")]
    [InlineData("extensions")]
    [InlineData("..\\..\\extensions")]
    public void ExtensionsPath_Resolves_Relative_To_Workspace_Root(string dir)
    {
        var ws = Make(dir);
        var expected = Path.GetFullPath(Path.Combine(_tempDir, dir.Replace('\\', Path.DirectorySeparatorChar)));
        Assert.Equal(Norm(expected), Norm(ws.ExtensionsPath));
        Assert.False(ws.ExtensionsPath.Contains(".."));
    }

    [Fact]
    public void ExtensionsPath_Absolute_Unchanged()
    {
        var abs = Path.Combine(Path.GetTempPath(), "abs_ext");
        var ws = Make(abs);
        Assert.Equal(Norm(abs), Norm(ws.ExtensionsPath));
    }
}