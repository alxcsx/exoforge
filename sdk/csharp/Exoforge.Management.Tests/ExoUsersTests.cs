using System;
using Xunit;
using Exoforge.Management;

namespace Exoforge.Management.Tests;

public class ExoUsersTests
{
    [Theory]
    [InlineData("player", "player")]
    [InlineData(" Service ", "service")]
    [InlineData("ADMIN", "admin")]
    [InlineData(null, "player")]
    [InlineData("", "player")]
    public void NormalizeRole_accepts_known_roles_and_defaults_to_player(string? input, string expected) =>
        Assert.Equal(expected, ExoUsers.NormalizeRole(input));

    [Theory]
    [InlineData("guest")]
    [InlineData("root")]
    public void NormalizeRole_rejects_anything_else(string input) =>
        Assert.Throws<ArgumentException>(() => ExoUsers.NormalizeRole(input));

    [Fact]
    public void CreatePayload_carries_email_password_name_and_the_role_as_scopes()
    {
        var payload = ExoUsers.CreatePayload(" game@arcade.local ", "pw", " Game Server ", "service");

        Assert.Equal("game@arcade.local", (string?)payload["email"]);
        Assert.Equal("pw", (string?)payload["password"]);
        Assert.Equal("Game Server", (string?)payload["name"]);
        Assert.Equal("service", (string?)payload["scopes"]![0]);
        Assert.Single(payload["scopes"]!.AsArray());
    }

    [Fact]
    public void CreatePayload_names_a_fresh_id_so_the_callers_own_is_never_used()
    {
        string first = (string)ExoUsers.CreatePayload("a@b.c", "pw", null, null)["user_id"]!;
        string second = (string)ExoUsers.CreatePayload("a@b.c", "pw", null, null)["user_id"]!;

        Assert.StartsWith("usr_", first);
        Assert.NotEqual(first, second);
    }

    [Fact]
    public void CreatePayload_leaves_the_name_to_the_server_when_none_is_given() =>
        Assert.False(ExoUsers.CreatePayload("a@b.c", "pw", null, null).ContainsKey("name"));

    [Theory]
    [InlineData("", "pw")]
    [InlineData("not-an-email", "pw")]
    [InlineData("a@b.c", "")]
    public void CreatePayload_requires_an_email_and_a_password(string email, string password) =>
        Assert.Throws<ArgumentException>(() => ExoUsers.CreatePayload(email, password, null, null));

    [Fact]
    public void RolePayload_names_the_user_and_the_role()
    {
        var payload = ExoUsers.RolePayload(" u1 ", "studio");

        Assert.Equal("u1", (string?)payload["user_id"]);
        Assert.Equal("studio", (string?)payload["role"]);
    }

    [Fact]
    public void RolePayload_requires_a_known_role()
    {
        Assert.Throws<ArgumentException>(() => ExoUsers.RolePayload("u1", null));
        Assert.Throws<ArgumentException>(() => ExoUsers.RolePayload("u1", "root"));
    }

    [Fact]
    public void UserPayload_requires_an_id()
    {
        Assert.Equal("u1", (string?)ExoUsers.UserPayload("u1")["user_id"]);
        Assert.Throws<ArgumentException>(() => ExoUsers.UserPayload(" "));
    }

    [Fact]
    public void UserPayload_does_not_choose_scopes_so_a_token_carries_the_account_s_own()
    {
        Assert.False(ExoUsers.UserPayload("u1").ContainsKey("scopes"));
    }

    [Fact]
    public void ListPayload_sends_only_what_was_asked()
    {
        Assert.Empty(ExoUsers.ListPayload(null, null));
        Assert.Empty(ExoUsers.ListPayload(" ", 0));

        var payload = ExoUsers.ListPayload("arcade", 5);
        Assert.Equal("arcade", (string?)payload["search"]);
        Assert.Equal(5, (int?)payload["limit"]);
    }

    [Theory]
    [InlineData("admin,service,studio,player,write,read", "admin")]
    [InlineData("studio,write,read", "studio")]
    [InlineData("service,write,read", "service")]
    [InlineData("player,read,write", "player")]
    [InlineData("read", "guest")]
    public void RoleOf_names_the_highest_role(string scopes, string expected) =>
        Assert.Equal(expected, ExoUsers.RoleOf(scopes));
}
