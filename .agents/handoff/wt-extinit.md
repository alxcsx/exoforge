# wt/extinit: IsExternalInit as an explicit, generated one-line file  (worktree /Users/alexcs/projects/exoforge-wt/extinit)
Read wt-common.md first. Unity's profile lacks System.Runtime.CompilerServices.IsExternalInit, so `record`/`init`
in a game assembly fails CS0518. 4433c7e made sdk/unity/Exoforge.SDK/Runtime/IsExternalInit.cs public, which
only helps assemblies referencing the SDK and can clash (CS0433) with another package's public copy.
The user decided: no source generator. Instead:
- Revert the SDK's copy to `internal`.
- Exoforge Studio (Unity editor window) gets an explicit button, and the setup wizard a step, that creates
  `Assets/Exoforge/IsExternalInit.cs` (one line, internal, in namespace System.Runtime.CompilerServices,
  guarded `#if !NET5_0_OR_GREATER`) when the project has none. "Has none" = no type with that full name in
  any of the project's own (Assets/) scripts; show it as already present otherwise. Note in the UI that
  an asmdef needs its own copy (internal is per assembly) and let the button target a chosen asmdef folder.
- Docs/skills that mention records in game code say this; remove the "public shim" claim from 4433c7e docs.
- Snake sample's game-assembly record keeps compiling (give its assembly the file).
Tests: an editor test or Management-level test for the "missing -> create / present -> no-op" logic; a
throwaway netstandard2.1 compile proving an assembly with its own internal copy builds records while the SDK's
copy is internal.
