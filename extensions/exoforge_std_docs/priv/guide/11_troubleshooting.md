---
nav: Troubleshooting
group: Operate
icon: alert
summary: Error codes, what they mean and where to look.
---
# Troubleshooting

When a call fails, the error carries a code, a message and the request id (`rid`) that the server logged. Start with the code.

---

## Error codes

| Code | Meaning | What to do |
|---|---|---|
| `upgrade_required` | The client's game version is blocked or unknown (HTTP 426, WebSocket close 4001). | Ship a newer client, or register and promote the game version. See [Versions & Migrations](guide:04_versions_and_migrations). |
| `client_outdated` | The data was already migrated past what this client's game version understands. | The player must update the game. |
| `token_expired` | The access token ran out. | The client renews it and retries by itself; if it keeps happening, sign in again. |
| `unauthorized` | The call needs a signed-in caller. | Sign in first with `ExoforgeSDK.Auth`. |
| `forbidden_scope` | The caller's role is below the action's scope. | Check the scope in [Authentication & Scopes](guide:10_auth_and_scopes). |
| `service_not_found` | No running extension provides that service. | Check the extension is running in the Studio's **Extensions** tab, then sync the client. |
| `action_not_found`, `unknown_action` | The service has no such action. | Rebuild and redeploy the extension, then **Sync Client**. |
| `startup_failed` | The extension's `OnExtensionStart()` or `[ExoSeed]` threw. | Read the extension's **Logs** tab for the exception. |

## Deploy refusals

A deploy that would change a table unsafely fails that extension alone and changes nothing:

| Code | Meaning |
|---|---|
| `unsafe_schema_change` | A rename, drop or narrowing with no migration declared. |
| `migration_missing` | The declaration changed in a way that needs an `[ExoMigration]` for this version. |
| `rows_below_version` | A drop is refused while rows are still stamped below the migration. |
| `game_versions_lock_older` | A drop is refused while a served game version still locks the extension below the migration. |
| `game_versions_unavailable` | The `versioning` extension is installed but did not answer, so the drop was refused. |
| `schema_drift` | A `Manual` table does not match its declaration. |
| `version_downgrade` | The deployed extension has a lower version than the table was last reconciled at. |
| `migration_incomplete` | After the migration the table still did not match; everything was rolled back. |

## Where to look

1. **The request id.** Every failure carries it (`ExoActionException.RequestId`, the `x-exoforge-rid` header). Paste it into the Studio's timeline to see the calls, events, queries and logs of that one request.
2. **The extension's Logs tab** in the inspector. For a C# extension it shows what the extension writes with `Exo.Logger`, anything it prints with `Console.WriteLine` (marked `[stdout]`) or `Console.Error` (marked `[stderr]`), and how its process ended. History is kept across a server restart. An extension may write 100 lines a second: past that, info and debug lines are dropped and counted in one "N log lines were dropped" line, while warnings and errors are always kept. The standard extensions that run inside the server log to the server console instead.
3. **The client's last calls.** `ExoforgeSDK.ExportDiagnostics()` returns the last 50 calls as JSON, with service, action, rid, status and duration.
4. **Deep capture.** For a problem you cannot reproduce, turn on capture for one player in the timeline and replay the captured request.
