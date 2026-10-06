#if !NET5_0_OR_GREATER
// netstandard2.1 does not expose IsExternalInit, which `record` and `init` need. This assembly is
// multi-targeted so Unity tooling can consume it, so provide it locally. Compile-time only.
namespace System.Runtime.CompilerServices
{
    internal static class IsExternalInit { }
}
#endif
