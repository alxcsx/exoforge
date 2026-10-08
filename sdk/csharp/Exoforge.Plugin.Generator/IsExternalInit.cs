using System.Runtime.CompilerServices;

namespace System.Runtime.CompilerServices
{
    /// <summary>Polyfill so records/init-only setters compile on netstandard2.0.</summary>
    internal static class IsExternalInit
    {
    }
}
