# Phase 2 (per sample): best-practice samples on the fixed SDK, no workarounds

Arcade project /Users/alexcs/projects/exoforge-arcade (own git repo, branch master). You are a tarball user:
only the SDK in Library/PackageCache/com.exoforge.sdk@*/ and its CLI (Editor/Cli~/exo.dll), never the
exoforge repo's source. Backend http://localhost:4001 (running; admin session in Exoforge/exoforge.json).
Toolchain: prefix dotnet with `/Users/alexcs/.local/bin/mise exec --`.

Fixed in the SDK, so the sample must simply rely on it: BUG-1 a failed extension call throws
ExoActionException with the callee's code (don't catch-and-ignore; map it to a clear error); BUG-2
[ExoWebhook](WebhookPayload) gets body/headers; SEC-3 [ExoCron] is server-only; BUG-17 OnEvent is not
re-entered during host calls; CONF-9 ExoTestHost is parallel-safe (drop DisableTestParallelization);
BUG-14 records compile without a shim (already removed); service accounts may name player_id.
Remove anything that only existed to dodge those. Background: README.md "What red means".

BUILD GATE: until t7 sends you "SDK READY", extension builds fail with NU1301 (a stale feed path, being
fixed in the SDK). Read and edit meanwhile; never hand-edit any nuget.config. After "SDK READY":
  mise exec -- dotnet test Exoforge/extensions/<ext>.Tests   (each of your extensions)
  exo extension push <ext>                                    (tarball CLI)
  bash tools/smoke/<sample>.sh                                 (must ASSERT: exit non-zero on a wrong result,
                                                                not just print; fix the script if it only echoes)
Only touch your own files (listed in your task). Do not edit README.md, Packages/, Assets/Samples/Common,
or another sample's files; put README notes in your report. Unity runs only via tools/unity.sh (it locks).
If a result is still wrong because Exoforge is wrong, do NOT patch around it: leave the test failing and
append it to /Users/alexcs/projects/exoforge/.agents/samples-findings/phase2.md (id, repro, evidence).
Never commit Exoforge/exoforge.json or Exoforge/mock-game-server.token. Commit only your paths
(git commit -- <paths>), "fix(<sample>): ...". Report <=15 lines with test/smoke output via the reply cmd.
