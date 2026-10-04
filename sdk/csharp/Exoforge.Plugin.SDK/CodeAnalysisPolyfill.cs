#if !NET5_0_OR_GREATER
// netstandard2.1 does not expose the trimmer annotations publicly. The .NET SDK multi-targets
// this assembly so Management/Unity tooling can consume it, so provide the attributes locally.
// They are compile-time only; the trimmer ignores them outside a trim/AOT build.
namespace System.Diagnostics.CodeAnalysis
{
    [AttributeUsage(
        AttributeTargets.Class | AttributeTargets.Struct | AttributeTargets.Constructor |
        AttributeTargets.Method | AttributeTargets.Property | AttributeTargets.Field |
        AttributeTargets.Interface | AttributeTargets.Parameter | AttributeTargets.ReturnValue |
        AttributeTargets.GenericParameter,
        Inherited = false)]
    internal sealed class DynamicallyAccessedMembersAttribute : Attribute
    {
        public DynamicallyAccessedMembersAttribute(DynamicallyAccessedMemberTypes memberTypes) => MemberTypes = memberTypes;

        public DynamicallyAccessedMemberTypes MemberTypes { get; }
    }

    [Flags]
    internal enum DynamicallyAccessedMemberTypes
    {
        None = 0,
        PublicParameterlessConstructor = 0x0001,
        PublicConstructors = 0x0002 | PublicParameterlessConstructor,
        NonPublicConstructors = 0x0004,
        PublicMethods = 0x0008,
        NonPublicMethods = 0x0010,
        PublicFields = 0x0020,
        NonPublicFields = 0x0040,
        PublicNestedTypes = 0x0080,
        NonPublicNestedTypes = 0x0100,
        PublicProperties = 0x0200,
        NonPublicProperties = 0x0400,
        PublicEvents = 0x0800,
        NonPublicEvents = 0x1000,
        Interfaces = 0x2000,
        All = ~None
    }
}
#endif
