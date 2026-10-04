using System.Runtime.CompilerServices;

// The Editor tooling (Control Center, behaviour inspector) shares the SDK's internal
// session/token plumbing. Game code does not — use ExoforgeSDK.Auth instead.
[assembly: InternalsVisibleTo("Exoforge.SDK.Editor")]
