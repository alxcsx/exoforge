using System.IO;
using Exoforge.Management;
using Xunit;

namespace Exoforge.Management.Tests;

public class ExtensionVisibilityTests
{
    [Theory]
    [InlineData(".feed", false)]
    [InlineData("wallet.Tests", false)]
    [InlineData("wallet", true)]
    public void IsExtensionFolder_skips_hidden_and_dotted(string name, bool expected) =>
        Assert.Equal(expected, ExoWorkspace.IsExtensionFolder(name));

    [Fact]
    public void IsTestExtension_by_name_and_manifest()
    {
        string root = Path.Combine(Path.GetTempPath(), "exo_vis_" + Path.GetRandomFileName());
        try
        {
            foreach (var n in new[] { "test_wallet", "wallet_tests", "plain", "flagged", "cat" }) Directory.CreateDirectory(Path.Combine(root, n));
            File.WriteAllText(Path.Combine(root, "flagged", "manifest.json"), "{\"test\":true}");
            File.WriteAllText(Path.Combine(root, "cat", "manifest.json"), "{\"category\":\"Test\"}");
            Assert.True(ExoWorkspace.IsTestExtension(Path.Combine(root, "test_wallet")));
            Assert.True(ExoWorkspace.IsTestExtension(Path.Combine(root, "wallet_tests")));
            Assert.True(ExoWorkspace.IsTestExtension(Path.Combine(root, "flagged")));
            Assert.True(ExoWorkspace.IsTestExtension(Path.Combine(root, "cat")));
            Assert.False(ExoWorkspace.IsTestExtension(Path.Combine(root, "plain")));
        }
        finally { Directory.Delete(root, true); }
    }
}

public class ExternalExtensionsFeedTests
{
    [Fact]
    public void EnsureBuildFeed_puts_the_feed_beside_extensions_outside_the_workspace()
    {
        string root = Path.Combine(Path.GetTempPath(), "exo_feed_" + Path.GetRandomFileName());
        try
        {
            string ws = Path.Combine(root, "game", "Exoforge");
            string ext = Path.Combine(root, "extensions", "items");
            Directory.CreateDirectory(Path.Combine(ws, ".feed"));
            Directory.CreateDirectory(Path.Combine(ext, "src"));
            File.WriteAllText(Path.Combine(ws, ".feed", "Exoforge.Plugin.SDK.0.1.71.nupkg"), "x");
            string csproj = Path.Combine(ext, "src", "items.csproj");
            File.WriteAllText(csproj, "<Project><ItemGroup><PackageReference Include=\"Exoforge.Plugin.SDK\" Version=\"0.1.52\" /></ItemGroup></Project>");

            ExoScaffolder.EnsureBuildFeed(ws, ext);

            Assert.True(File.Exists(Path.Combine(root, "extensions", ".feed", "Exoforge.Plugin.SDK.0.1.71.nupkg")));
            Assert.Contains("0.1.71", File.ReadAllText(csproj));
        }
        finally { Directory.Delete(root, true); }
    }
}

public class BinaryOsTests
{
    [Theory]
    [InlineData(new byte[] { 0xCF, 0xFA, 0xED, 0xFE }, "linux-musl-x64", false)]
    [InlineData(new byte[] { 0xCF, 0xFA, 0xED, 0xFE }, "osx-arm64", true)]
    [InlineData(new byte[] { 0x7F, (byte)'E', (byte)'L', (byte)'F' }, "linux-musl-x64", true)]
    [InlineData(new byte[] { 0x7F, (byte)'E', (byte)'L', (byte)'F' }, "win-x64", false)]
    public void BinaryMatchesRid_reads_the_executable_format(byte[] head, string rid, bool expected)
    {
        string path = Path.GetTempFileName();
        try { File.WriteAllBytes(path, head); Assert.Equal(expected, ExoDeployer.BinaryMatchesRid(path, rid)); }
        finally { File.Delete(path); }
    }
}
