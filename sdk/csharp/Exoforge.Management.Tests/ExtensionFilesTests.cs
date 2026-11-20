using System.Linq;
using System;
using System.IO;
using Exoforge.Management;
using Xunit;

namespace Exoforge.Management.Tests;

/// <summary>What <c>exo extension push</c> ships beside the binary: assets and the extension's own docs pages.</summary>
public class ExtensionFilesTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "exo_files_" + Guid.NewGuid().ToString("N"));

    public ExtensionFilesTests() => Directory.CreateDirectory(_dir);

    public void Dispose() => Directory.Delete(_dir, recursive: true);

    private void Write(string rel, string text)
    {
        string path = Path.Combine(_dir, rel);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, text);
    }

    [Fact]
    public void Nothing_to_ship_is_null()
    {
        Write("src/Thing.cs", "class Thing {}");

        Assert.Null(ExoDeployer.CollectExtensionFiles(_dir));
    }

    [Fact]
    public void Docs_pages_and_assets_are_shipped_and_other_files_are_not()
    {
        Write("docs/overview.md", "# Wallet");
        Write("docs/refunds.md", "# Refunds");
        Write("docs/notes.txt", "not a page");
        Write("docs/nested/deep.md", "# not gathered");
        Write("assets/view.js", "export {}");
        Write("manifest.json", "{}");

        var files = ExoDeployer.CollectExtensionFiles(_dir)!;

        Assert.Equal(new[] { "assets/view.js", "docs/overview.md", "docs/refunds.md" }, files.Keys.OrderBy(k => k, StringComparer.Ordinal));
    }
}
