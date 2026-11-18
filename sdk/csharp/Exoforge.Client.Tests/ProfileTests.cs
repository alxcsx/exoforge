using Exoforge.Client;
using Xunit;

public class ProfileTests
{
    [Fact]
    public void Default_Keeps_Legacy_Suffix_Empty()
    {
        var p = ExoProfileResolver.Resolve(new string[0], "/proj");
        Assert.Equal("default", p);
        Assert.Equal(string.Empty, ExoProfileResolver.SuffixFor(p));
    }

    [Fact]
    public void ExoProfile_Arg_Wins()
    {
        var p = ExoProfileResolver.Resolve(new[] { "-exoProfile", "alice" }, "/proj/Library/VP/abc");
        Assert.Equal("alice", p);
    }

    [Fact]
    public void Mppm_Clone_Folder_Gives_Id()
    {
        var p = ExoProfileResolver.Resolve(new string[0], "/proj/Library/VP/clone2");
        Assert.Equal("clone2", p);
    }

    [Fact]
    public void Invalid_Name_Rejected()
    {
        Assert.False(ExoProfileResolver.IsValid("a b"));
        Assert.False(ExoProfileResolver.IsValid(""));
        var p = ExoProfileResolver.Resolve(new[] { "-exoProfile", "bad name" }, "/proj");
        Assert.Equal("default", p);
    }

    [Fact]
    public void Suffix_Differs_By_Profile()
    {
        Assert.Equal(".a", ExoProfileResolver.SuffixFor("a"));
        Assert.NotEqual(ExoProfileResolver.SuffixFor("a"), ExoProfileResolver.SuffixFor("b"));
    }

    [Fact]
    public void DeviceSeed_Differs_By_Profile_And_Default_Is_Legacy()
    {
        Assert.Equal("hw1", ExoProfileResolver.DeviceSeed("hw1", "default"));
        var a = ExoProfileResolver.DeviceSeed("hw1", "alice");
        var b = ExoProfileResolver.DeviceSeed("hw1", "bob");
        Assert.NotEqual("hw1", a);
        Assert.NotEqual(a, b);
    }

    [Fact]
    public void MaxLength_And_Allowed_Chars_Validated()
    {
        Assert.True(ExoProfileResolver.IsValid("player_1-test"));
        Assert.True(ExoProfileResolver.IsValid(new string('a', ExoProfileResolver.MaxNameLength)));
        Assert.False(ExoProfileResolver.IsValid(new string('a', ExoProfileResolver.MaxNameLength + 1)));
    }

    [Fact]
    public void NonAscii_Letters_And_Digits_Are_Rejected()
    {
        Assert.False(ExoProfileResolver.IsValid("café"));
        Assert.False(ExoProfileResolver.IsValid("player١"));
        Assert.False(ExoProfileResolver.IsValid("üser"));
    }
}