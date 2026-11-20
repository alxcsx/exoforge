using Xunit;

namespace Exoforge.Management.Tests;

/// <summary>Which published file is staged for upload: the one built for the target runtime, never a leftover for another.</summary>
public class PublishedBinaryTests
{
    [Theory]
    [InlineData("/w/items/bin/Release/net9.0/linux-musl-x64/publish/items", "linux-musl-x64", true)]
    [InlineData("/w/items/bin/Release/net9.0/win-x64/publish/items.exe", "linux-musl-x64", false)]
    [InlineData("/w/items/bin/Release/net9.0/win-x64/publish/items.exe", "win-x64", true)]
    [InlineData("/w/items/bin/Release/net9.0/linux-musl-x64/publish/items.dll", "linux-musl-x64", false)]
    [InlineData("/w/items/bin/Release/net9.0/linux-musl-x64/items", "linux-musl-x64", false)]
    public void Only_the_target_runtimes_publish_output_is_a_candidate(string path, string rid, bool expected) =>
        Assert.Equal(expected, ExoDeployer.IsPublishedBinary(path, "items", rid));
}
