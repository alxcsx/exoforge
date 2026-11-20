# Fix: player-facing error replies (SEC-5 + unreadable codes)

Repo /Users/alexcs/projects/exoforge, branch projetao_mvp. Toolchain `/Users/alexcs/.local/bin/mise exec --`.
Live repro (backend on :4001), a player calling a native action that throws ExoActionException("invalid_png", ...):
  {"error":"{:invalid_png, \"Not a PNG image.\"}","status":"error","logs":["[ERROR] ...ExoActionException
   ... at ...LevelShareExtension.cs:line 168 ..."],"rid":"..."}
1. Error shape: an action error that carries a code and message (native {code,message} map, `{atom, binary}`
   tuple from defaction, plain atom) must reach HTTP and WS clients as
   {"status":"error","error":"<code>","message":"<message>", ...} - never an inspect/1 string. Keep existing
   codes (forbidden_scope, service_not_found, ...) and their extra fields unchanged. HTTP:
   extensions/exoforge_std_http/lib/exoforge/std/http/router.ex ~L320-400; WS:
   extensions/exoforge_std_ws/lib/exoforge/std/ws/socket_handler.ex ~L300-450; share the mapping in
   exoforge_std_transport (format_action_result) rather than duplicating it if that's the shorter diff.
   C# Exoforge.Client: ExoActionException must expose Code and Message from that shape
   (sdk/csharp/Exoforge.Client); keep reading the old string shape if trivial.
2. SEC-5 (.agents/SAMPLES_REPORT.md:108): `logs` (Exoforge.ExtensionLogs.for_rid) goes only to staff callers
   (admin/studio scope). Players/guests/webhooks get no `logs` key; the rid stays on every reply.
   Same on WS.
Tests: http_test + ws test: player error -> error/message fields, no logs; staff -> logs present; a
{code,message} from a native extension maps correctly. Client test for the new shape.
Bump SDK 0.1.44 -> 0.1.45 (package.json + ExoforgePackageVersion.cs); update docs/skills that show error
replies; then `COPYFILE_DISABLE=1 just pack-unity`, `tar tzf dist/com.exoforge.sdk-0.1.45.tgz | grep -c '/\._'` = 0.
Run only the touched test files (+ `mix deps.compile --force` in an extension dir if a path dep is stale).
Do not touch the arcade. Commit "fix(...): ..." per fix; do not push. Report <=15 lines with test output.
