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
        bool IsNew)
    {
        /// <summary>False for a freshly registered account — prompt for a name before playing.</summary>
        public bool HasDisplayName => !string.IsNullOrEmpty(DisplayName);
    }
}
