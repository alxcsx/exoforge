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
