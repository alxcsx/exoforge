using System.Collections.Generic;

namespace Exoforge.Client.Unity
{
    /// <summary>
    /// A signed-in player. Returned by <see cref="ExoforgeAuth"/> and safe to hold for the
    /// lifetime of the session.
    /// </summary>
    public sealed record ExoSession(
        string PlayerId,
        string DisplayName,
        string Token,
        IReadOnlyList<string> Scopes,
        bool IsNew);
}
