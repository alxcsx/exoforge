#if !NET5_0_OR_GREATER
namespace System.Runtime.CompilerServices
{
    // Internal on purpose: the type only has to be visible to this assembly. A game asmdef is a
    // different assembly and needs its own copy (the Studio generates Assets/Exoforge/IsExternalInit.cs);
    // a public copy here would also collide with another package's public copy.
    internal static class IsExternalInit { }
}
#endif
