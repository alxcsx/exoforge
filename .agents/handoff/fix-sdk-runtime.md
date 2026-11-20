# Fix: SDK runtime bugs found by the arcade samples

Repo /Users/alexcs/projects/exoforge, branch projetao_mvp. Full entries: .agents/SAMPLES_REPORT.md
(search the ids). Toolchain: prefix mix/dotnet/just with `/Users/alexcs/.local/bin/mise exec --`.
Do NOT touch extensions/exoforge_std_file_bucket, the dashboard, or exoforge-arcade (another worker owns them).
Fix the root cause in the SDK/kernel; no workaround in samples. Each fix gets a regression test that
fails before the fix. Follow AGENTS.md (shortest diff, match surrounding style).

1. BUG-17 (PluginHost.cs host-call wait loop ~L780-800): an `event` frame read while a host call is pending
   is dispatched inline (re-entrant OnEvent; nested wait drops the outer host_call_result).
   Fix: queue events like BufferedActions and dispatch them from the main loop after the current
   action/event finishes; never drop a host_call_result for another id.
   Test: Plugin.SDK test where an event arrives mid host call -> handled after, outer call completes.
2. BUG-1: a failed extension->extension call (CallActionAsync<T>/HostBridge.CallAction*) returns null/default
   instead of throwing. native_extension_runner.ex ~L678 returns `%{error: inspect(reason)}`.
   Fix: host returns a structured error {code, message} and the SDK throws ExoActionException(code, message)
   (keep the code the callee threw, e.g. "insufficient_funds"). Test on both sides
   (native_extension_runner/extension_protocol test + Plugin.SDK test).
3. BUG-2: [ExoWebhook] method `(WebhookPayload payload)` gets null; router.ex sends top-level
   {body, raw_body, json, headers, method, query}. Fix: bind a WebhookPayload parameter to the whole payload.
   Test in Plugin.SDK.
4. SEC-3: [ExoCron] methods are registered as player-callable actions (a player can POST
   /api/<svc>/tick_prices). Fix: cron-invoked actions get scope "server" (internal only) by default in
   the generator/manifest; the cron runner must still be able to invoke them. Test: generator/manifest test
   + Elixir test that a player caller is refused while cron dispatch works.
5. CONF-9: ExoTestHost / ExoServices.* overrides are process-wide statics, so parallel xunit classes
   collide. Fix with AsyncLocal for the test context and stub overrides (prod path unchanged).
   Test: two concurrent ExoTestHost contexts don't see each other's data/stubs.
6. BUG-14: sdk/unity/Exoforge.SDK/Runtime/IsExternalInit.cs is internal, so a game asmdef with a `record`
   fails CS0518. Make it public (guard so it doesn't clash on runtimes that define it).
7. Bump SDK version 0.1.42 -> 0.1.43 in sdk/unity/Exoforge.SDK/package.json and Editor/ExoforgePackageVersion.cs.
   Fix any doc that states the old behaviour (skills under sdk/unity/Exoforge.SDK/Agents~, docs/).

Proof (run, paste results):
  mise exec -- dotnet test sdk/csharp/Exoforge.Plugin.SDK.Tests   (and Generator.Tests, whichever exist)
  mise exec -- mix test <the exact elixir test files you touched>   (run `mix deps.compile --force` in an
  extension dir if it uses a changed core macro)
Commit each bug as its own commit ("fix(sdk): ..."). Do not push.
Report: <=15 lines, file:line refs, commits, test results.
