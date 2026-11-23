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
| `extension_unavailable` | The extension that handles the call is not running (it crashed or never started). Players see only this; the reason is in the Studio. | Open **Extension Manager**: a crashed extension shows *Crashed* with what happened and the process's last output. Fix it and deploy again. |
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
| `wrong_binary_format` | The extension was built for another operating system than the server runs (a Windows build sent to a Linux server). Nothing was stopped or replaced. Build with the target on **Auto**, or pass the server's runtime to `exo extension build --rid`, and deploy again. |

## Signing in again

The Unity window tells a refused session apart from a server that is down:

- **"Sign in again"** means the server answered and did not accept the saved session. It expired or was revoked. Use the **Account** button and sign in; nothing else needs fixing.
- **"Server offline"** means nothing answered. Check that the server is running and that the environment's address is right.
- **A player that is not signed in** (the console says the server refused this player's saved session): choose **Exoforge ▸ Sessions ▸ Reset Anonymous Player Session**, or call `ExoforgeSDK.Auth.ResetSession()`, and play again. A new anonymous player is created.

## Deploying several extensions

When one extension calls a service another one provides, deploy the provider first. **Build & Deploy All** in the Unity window does this for you: it reads each extension's `manifest.json`, puts providers before the extensions that call them, and shows a warning if two extensions depend on each other in a circle. A service that nothing in your project provides is expected to be one of the server's own.

A project can leave extensions out with `"excluded_extensions": ["name", ...]` in `exoforge.json` (`exo extension exclude <name>` and `include <name>` edit it, and the Unity window has an Include toggle per extension). `exo extension push --all` and Build & Deploy All skip them, and refuse to run, naming the pair, when an included extension needs an excluded one (for example `daily_rewards needs wallet, which is excluded`). In the Unity window, excluded extensions sit under a *Not included* fold. Folders that are not extensions never appear there: hidden ones (`.feed`) and dotted project folders (`wallet.Tests`). Test extensions are hidden too: a name of `test_*`, `*_test` or `*_tests`, or `"test": true` / `Category = "Test"` in the manifest.

## Starting over: Danger zone

Studio ▸ Settings ▸ **Danger zone** wipes the server so you can try a different sample. Each button asks you to type the project name first, and both need an admin account. A message at the bottom says what was removed. There is no undo.

- **Reset extensions** removes every extension you deployed, with its tables, stored data and files. The standard extensions, players, accounts, service tokens and game versions stay.
- **Delete everything** does that and also removes players, accounts (the admin and Studio accounts stay), service tokens, game versions, file buckets and Studio settings. Game servers that use a service token must be given a new one afterwards.

After a reset, deploy the extensions of the sample you want to try.

## Where to look

1. **The request id.** Every failure carries it (`ExoActionException.RequestId`, the `x-exoforge-rid` header). Paste it into the Studio's timeline to see the calls, events, queries and logs of that one request.
2. **The extension's Logs tab** in the inspector. For a C# extension it shows what the extension writes with `Exo.Logger`, anything it prints with `Console.WriteLine` (marked `[stdout]`) or `Console.Error` (marked `[stderr]`), and how its process ended. History is kept across a server restart. An extension may write 100 lines a second: past that, info and debug lines are dropped and counted in one "N log lines were dropped" line, while warnings and errors are always kept. The standard extensions that run inside the server log to the server console instead.
3. **The client's last calls.** `ExoforgeSDK.ExportDiagnostics()` returns the last 50 calls as JSON, with service, action, rid, status and duration.
4. **Deep capture.** For a problem you cannot reproduce, turn on capture for one player in the timeline and replay the captured request.
