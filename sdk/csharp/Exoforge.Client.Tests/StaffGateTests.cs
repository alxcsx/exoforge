using Exoforge.Client;
using Xunit;

namespace Exoforge.Client.Tests;

/// <summary>
/// The staff gate the Unity Editor Studio sits behind (M33 Fix 14). The editor is staff tooling:
/// a guest or player session connects to the game, never to the window.
/// </summary>
public class StaffGateTests
{
    [Theory]
    [InlineData(new string[0], false)]
    [InlineData(new[] { "guest" }, false)]
    [InlineData(new[] { "player" }, false)]
    [InlineData(new[] { "player", "read" }, false)]
    [InlineData(new string?[] { null }, false)]
    [InlineData(new[] { "studio" }, true)]
    [InlineData(new[] { "admin" }, true)]
    [InlineData(new[] { "staff" }, true)]
    [InlineData(new[] { "player", "admin" }, true)]
    public void A_session_below_staff_is_denied_and_one_at_or_above_it_is_admitted(
        string[]? scopes,
        bool admitted)
    {
        Assert.Equal(admitted, ExoStaff.HasAccess(scopes));
        Assert.False(ExoStaff.HasAccess(null));
    }
}
