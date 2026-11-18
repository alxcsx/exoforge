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
        Assert.NotEqual(ExoProfileResolver.SuffixFor("a"), ExoProfileResolver.SuffixFor("b"));
    }
}