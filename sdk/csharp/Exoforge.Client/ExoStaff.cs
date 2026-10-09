using System.Collections.Generic;
using System.Linq;

namespace Exoforge.Client;

/// <summary>
/// The staff gate the Unity Editor Studio sits behind. Its tools read users, tokens, plugins and
/// telemetry, so a session scoped below staff — player or guest — never reaches them (M33 Fix 14).
/// Pure, so the client test suite can pin it without Unity.
/// </summary>
public static class ExoStaff
{
    public static bool HasAccess(IEnumerable<string>? scopes) =>
        scopes?.Any(s => s is "admin" or "studio" or "staff") == true;
}
