# B1: a broken extension must not break the system (core + Studio)

Decision (user): boot failures are isolated per extension. A failed extension is reported on the web dashboard; everything else keeps running.
Later, clients may block player login based on it; that is out of scope, but the status must be readable.

## Today
- `ElixirExtensionRunner.load/1` raises on start failure ("fail the boot loudly", elixir_extension_runner.ex:38) and
  `ExtensionBootstrapper.run/2` has no rescue, so one bad extension aborts the rest of boot.
- Reusable: `ExtensionRegistry.mark_crashed/2`, `get_crash_info/1`, `clear_crash_status/1`; Studio already renders `:crashed`.

## Behaviour
1. Each extension's load is isolated: `{:error, reason}` returns, raises, exits and throws from `runner.load` (Elixir and native: handshake refused,
   lifecycle/`[ExoSeed]` failure, database provisioning or schema failure) are caught per extension. Partial processes are cleaned up
   (`terminate_extension_processes`), the extension is NOT left registered as a provider, and boot continues with the next one.
2. Status: `mark_crashed(id, %{kind: :boot_failed, stage: atom, message: string, detail: inspected term, at: unix})`. Reload/redeploy (the existing
   ExtensionManager path) clears it on success and records a new one on failure.
3. Dependents: if a declared dependency (manifest `dependencies`, which includes `db_read` targets) is failed or blocked, the dependent is not started and is
   marked `%{kind: :blocked, message: "dependency <id> failed", detail: ...}`. Independent extensions are unaffected. The dashboard extension has no
   dependencies, so it keeps serving and shows the failure.
4. Calls to a failed or blocked extension's service return `{:error, {:extension_unavailable, id}}` (structured, with the reason available) instead of
   `service_not_found`; the HTTP/WS transports already map unknown errors, do not change them here.
5. Visibility: an `extension.boot_failed` event on the kernel event bus (id, kind, stage, message), an error line in `ExtensionLogs` for the extension, and a
   boot-banner line marked FAILED. `extension_manager` list/info includes `status` and `failure` for each extension, so a client or CI can read them.
6. Studio: a failed/blocked extension shows a clear badge and its message in the extensions list and in the extension inspector (Overview), plus one
   cluster-level notice "N extensions failed to start" on the overview with a link to them and a Retry (reload) action. Follow
   docs/design/ui-standard.md exactly (remap in exoforge-studio.css, no `dark:` variants, allowed hues, four radii); run `test/ui_standard_test.exs`.
7. The kernel never stops for this: `boot/0` returns normally and the application starts with zero, some or all extensions failed.

## Not in scope
Client-side handling (blocking logins), automatic retries/backoff, partial service availability inside one extension.

## Tests (fail before)
core/test: a fake Elixir extension whose `init` returns `{:error, :boom}` between two healthy ones: the third still boots; failure info readable;
`extension.boot_failed` emitted; a dependent is `:blocked` and not started; an independent one works; dispatch to the failed one returns
`extension_unavailable`; reload after the cause is fixed clears the status. Same for a native extension with a refused handshake (existing runner test
helpers). Dashboard test: badge and overview notice render for a failed extension. `mix test` for core and the dashboard extension.

## Accept
core and dashboard tests green; the existing boot tests unchanged; `git grep -n "Extension Start Failed"` shows the raise is gone.
