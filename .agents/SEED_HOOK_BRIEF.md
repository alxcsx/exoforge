Implement the deferred native extension startup lifecycle hook.

Goal:
- Add an optional `OnExtensionStart()` hook for native C# extensions.
- Invoke it exactly once after the native protocol handshake, without requiring a new attribute system.
- Add the smallest wire-protocol support needed so the host can request/start the extension and receive an explicit result or error.

Files/areas to inspect and update:
- `core/lib/drivers/runtime/extension_protocol.ex`
- `core/test/drivers/runtime/extension_protocol_test.exs` (or the repository's exact protocol test path)
- `sdk/csharp/Exoforge.Plugin.SDK/` `ExtensionHost`/`HostBridge` and generator/runtime code that detects extension lifecycle methods
- `sdk/csharp/Exoforge.Plugin.SDK.Tests/HandshakeTests.cs` (or exact handshake test path)
- Update the protocol table in `AGENTS.md` only if the new frame is part of the protocol.

Constraints:
- Read existing implementations and tests before editing; preserve the current handshake and action/event behavior.
- Keep the hook optional and idempotence/documentation-oriented; do not introduce a new attribute hierarchy.
- Preserve explicit error handling and existing protocol capability/version semantics.
- Do not touch unrelated features or generated/build artifacts.
- Leave `.agents/` untracked and do not stage it.

Verification:
- Run the narrow protocol tests in `core` and the affected C# SDK test project(s). Use the repository's existing test commands and avoid live E2E.
- Ensure formatting/build/type checks relevant to changed code pass.

Commit:
- Commit the finished implementation with explicit paths only, after tests are green.
- Include the repository-required Copilot co-author trailer.
- Report back to terminal `t17` with: `REPORT: seed hook done, <tests>, <commit sha>`.
