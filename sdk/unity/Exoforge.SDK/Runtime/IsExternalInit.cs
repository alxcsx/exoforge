#if !NET5_0_OR_GREATER
namespace System.Runtime.CompilerServices
{
    // Public, not internal: a game asmdef is a different assembly, and the compiler looks for a
    // public IsExternalInit in the references before it will emit a record or an init-only setter.
    // The guard keeps it out of a runtime that already defines one.
    public static class IsExternalInit { }
}
#endif
