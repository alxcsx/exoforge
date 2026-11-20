# Exoforge Arcade — Consolidated Findings Report

Consolidated from `SAMPLES_FINDINGS.md` (`F1`–`F23`) and slice reports (`audit`, `economy`, `dungeon`, `doodle`, `achievements`, `menu`). Deduplicated and ranked by severity: **1) Security**, **2) Bugs breaking tarball users**, **3) Wrong docs**, **4) Contradictions & confusing points**, **5) Nits**. (58 entries total: 11 security, 17 bugs, 13 wrong/missing docs, 13 contradictions/confusing, 4 nits.)

## Summary Table

| ID | Sev | Kind | Title | Found by |
| :--- | :---: | :--- | :--- | :--- |
| `SEC-1` | 1 | bug (security) | `file_bucket.upload_file` `path` param lets any caller read arbitrary server files + leaks `disk_path` *(fixed in `acc8d06`/`33d0832`)* | `doodle-5`, `F20` |
| `SEC-2` | 1 | bug (security) | Any player can overwrite or delete any other player's bucket file | `doodle-14` |
| `SEC-3` | 1 | bug (security) | `[ExoCron]` methods are exposed as `player`-scoped callable actions | `economy-6` |
| `SEC-4` | 1 | missing / security | `[ExoWebhook]` routes are unauthenticated with no doc warning or signature-check guide | `F11`, `audit` |
| `SEC-5` | 1 | bug (security) | Player error replies include `logs` with server stack traces and host absolute paths *(still open)* | `menu-6`, `F21` |
| `SEC-6` | 1 | contradiction / authz | `Scope = "server"` is reachable via `exo call` (admin), contradicting `roles.ex` | `economy-2`, `F6`, `F12`, `dungeon-12` |
| `SEC-7` | 1 | missing / security | No documented per-player topic isolation; shared-topic events broadcast to all subscribers | `achievements-9`, `dungeon-11` |
| `SEC-8` | 1 | bug (security) | Elixir `defaction` ignored contract scope when omitted — 18 `:server`/`:studio` actions ran as `:player` *(fixed)* | `F22` |
| `SEC-9` | 1 | bug (security) | Studio `:4005` served every bucket file publicly *(fixed)*; dev mode treats token-less requests as `dev:admin` | `F23` |
| `SEC-10` | 1 | bug (security) | `auth.register`/`create_player` by admin without explicit id overwrote & demoted protected `admin` account *(fixed in `b5b1940`)* | orchestrator |
| `SEC-11` | 1 | bug (security) | `Exoforge.Std.Auth.Cache` was never flushed on `delete_user`/`update_user_roles`/`purge_disposable` *(fixed in `b5b1940`)* | orchestrator |
| `BUG-1` | 2 | bug | Failed extension→extension calls return `null` or empty default object instead of throwing | `economy-1`, `menu-4` |
| `BUG-2` | 2 | bug | `[ExoWebhook]` handlers always receive `null` `WebhookPayload`; `EXO004` forbids any other signature | `economy-4`, `audit-3` |
| `BUG-3` | 2 | bug | `ExoClient.UploadFileAsync(..., metadata)` causes HTTP 500 with empty body | `doodle-13` |
| `BUG-4` | 2 | bug | `Exoforge.Plugin.SDK` NuGet is pinned to `0.1.0`, so tarball upgrades are ignored by cache | `F19` |
| `BUG-5` | 2 | bug | Workspace & per-extension `nuget.config` pin absolute `PackageCache` path (14 copies; breaks CLI-only clones) | `F13`, `economy-14`, `doodle-10`, `achievements-7` |
| `BUG-6` | 2 | bug | Half of `com.exoforge.sdk-0.1.41.tgz` is macOS `._*` AppleDouble files | `F18` |
| `BUG-7` | 2 | bug | `DatabaseExtensions.Put(record)` throws at runtime when `PrimaryKey` is snake_case | `audit-5`, `F4` |
| `BUG-8` | 2 | bug | Only the first `OnEvent` overload is called, and extensions receive their own emitted events | `achievements-3` |
| `BUG-9` | 2 | bug | `Scope = "guest"` is rejected for `player`, `studio`, and `admin` callers (only literal `guest` token passes) | `F10`, `audit` |
| `BUG-10` | 2 | bug | Rapid redeploy / push causes `extension_starting` then `startup_failed` timeout with empty logs | `economy-10`, `achievements-4`, `menu-10`, `doodle-16` |
| `BUG-11` | 2 | bug | Generated response DTOs are unprefixed in `Exoforge.Client`, colliding across extensions | `doodle-8`, `economy-13` |
| `BUG-12` | 2 | bug | `ExoClient` & HTTP wrap `ExoActionException` as `"http_error"` + Elixir tuple string | `doodle-9`, `economy-9`, `menu-5` |
| `BUG-13` | 2 | bug | `exo extension new <name>` silently overwrites existing extension source | `doodle-1`, `achievements-5`, `menu-1` |
| `BUG-14` | 2 | confusing / bug | `IsExternalInit` is `internal` to `Exoforge.SDK`, breaking `record` in game asmdefs | `doodle-11` |
| `BUG-15` | 2 | bug (process) | Two different tarballs shipped with identical version `0.1.41` | `F14` |
| `BUG-16` | 2 | bug | Anonymous login with `name` fails with `:name_taken` globally | `doodle-14` |
| `BUG-17` | 2 | bug | `OnEvent` is re-entered during pending host calls, losing updates and dropping outer `host_call_result` frames | `achievements-10`, reviewer |
| `DOC-1` | 3 | doc-wrong | `exoforge-extensions` skill uses non-existent `Exo.Events.Publish` and wrong default `Scope` | `audit-1`, `F3`, `F6`, `economy-15`, `dungeon-1`, `doodle-2`, `doodle-3`, `achievements-6`, `achievements-8`, `menu-2` |
| `DOC-2` | 3 | doc-wrong | Served `[ExoWebhook]` examples fail to compile (`EventName`/`Data`/`Success()` and `EXO004`) | `audit-2`, `audit-3` |
| `DOC-3` | 3 | doc-wrong | Served blueprints omit DTOs, use undefined `PlayerDataRecord`, and misplace `Topic` | `audit-4` |
| `DOC-4` | 3 | doc-wrong | Installing tarball does not create `Exoforge/` or `./exo`; documented fallback path is wrong | `F16` |
| `DOC-5` | 3 | doc-wrong | CLI help & error messages tell tarball users to run repo-only `just` commands | `audit-6`, `dungeon-5`, `doodle-1`, `menu-1` |
| `DOC-6` | 3 | doc-wrong | `--json` is documented on `exo extension new/build/push` & errors, but ignored | `audit-7`, `economy-9` |
| `DOC-7` | 3 | doc-wrong | `exoforge-connection` skill lists non-existent `exo status --json` fields | `audit-8` |
| `DOC-8` | 3 | doc-wrong | SDK XML docs list `Name` on `[ExoCron]`/`[ExoWebhook]`, which fails with `CS0617` | `economy-5` |
| `DOC-9` | 3 | doc-wrong | `PluginServices.g.cs` header cites non-existent `exo plugin stubs` command | `economy-12` |
| `DOC-10` | 3 | missing | Scopes (`service`, `server`, `global`, `webhook`), `[ExoDependency]`, and `[ExoEvent]` subscription undocumented | `F6`, `economy-3`, `dungeon-2`, `dungeon-9`, `doodle-15`, `achievements-1`, `menu-3` |
| `DOC-11` | 3 | missing | `ExoTestHost`, `AllowPlayerRead`, HTTP routes, `file_bucket` (`get_file_info`), `issue_token`, and asmdefs undocumented | `audit-10`, `economy-7`, `economy-8`, `economy-14`, `dungeon-3`, `dungeon-4`, `dungeon-10`, `doodle-4`, `doodle-6`, `doodle-10`, `doodle-12`, `doodle-17`, `achievements-7`, `menu-9` |
| `DOC-12` | 3 | doc-wrong | Repo `ATTRIBUTES.md` §4 still cites non-existent `ExoforgeSDK.Events.Subscribe` | `F8`, `audit` |
| `DOC-13` | 3 | doc-wrong | Repo `AGENTS.md` says `ExtensionServices.g.cs` instead of `PluginServices.g.cs` | `F5`, `audit` |
| `CONF-1` | 4 | contradiction | Extension template list differs across 4 places and `new` ignores `--template` | `F7`, `audit`, `dungeon-5`, `doodle-1`, `achievements-5`, `menu-1` |
| `CONF-2` | 4 | contradiction | Scaffold targets `net10.0` while docs state `.NET 9+` | `economy-11`, `dungeon-6` |
| `CONF-3` | 4 | contradiction | `README.md` requires `Exoforge.prefab` while `01_quickstart.md` says "Zero Scene Wiring" | `audit-9` |
| `CONF-4` | 4 | bug / confusing | Snake sample swaps `name` and `playerId`, masked by `sanitize_payload` | `F1`, `F2`, `audit` |
| `CONF-5` | 4 | confusing | `Exo.*` vs `ExoServices.*` and `Database.Get(id)` vs `Get(table, key)` mixed without explanation | `F3`, `F4`, `audit`, `economy-15`, `doodle-2`, `achievements-6`, `menu-2` |
| `CONF-6` | 4 | confusing | Declaring `[ExoEvent]` to subscribe makes listener look like emitter in contracts/stubs | `achievements-2` |
| `CONF-7` | 4 | confusing | `SubscribeAsync` defaults to first topic only; nested `IReadOnlyList<T>` degrades to `JsonElement` | `economy-13`, `doodle-7` |
| `CONF-8` | 4 | confusing | `resource_store.list` returns `:resource_not_found` when unreadable; `ListAsync` convenience overload unusable | `menu-7`, `menu-8`, `economy-7` |
| `CONF-9` | 4 | confusing | `ExoTestHost` / `ExoServices.*` static state is not parallel-safe across xunit classes | `dungeon-8`, `menu-9`, `economy-14`, `achievements-7` |
| `CONF-10` | 4 | confusing | Two players on one machine share `PlayerPrefs` (`ExoDeviceId`/`ExoTokenStore`) by default | `audit` |
| `CONF-11` | 4 | contradiction | `file_bucket` has no tags feature despite `README.md` §4 | `doodle-4` |
| `CONF-12` | 4 | confusing | `exo status` reports stale build metadata; in-repo `sample_unity` masks tarball bugs | `F15`, `F17` |
| `CONF-13` | 4 | confusing | `AllowPlayerRead` exposes all rows with no per-player filter, easily misapplied to per-player tables | `economy-16`, reviewer |
| `NIT-1` | 5 | confusing | Legacy "Plugin" naming survives extension rename (`plugins_csharp/`, `Exoforge.Plugin.SDK`, etc.) | `F9`, `audit` |
| `NIT-2` | 5 | confusing | Scaffolded `.gitignore` omits `bin/` and `obj/` | `dungeon-7` |
| `NIT-3` | 5 | confusing | `PluginServices.g.cs` emits duplicate types and maps `int`→`long`, `DateTime`→`JsonElement` | `economy-12` |
| `NIT-4` | 5 | confusing | `exo stubs` aliases `sync` (Unity client), confusing users wanting `exo extension stubs` | `economy-12` |

---

## 1. Security (`SEC-1` – `SEC-7`)

### SEC-1 — `file_bucket.upload_file` `path` parameter lets any caller read arbitrary server files *(fixed in `acc8d06`/`33d0832`)*
- **Severity**: 1 (Security)
- **Kind**: bug
- **Where**: `extensions/exoforge_std_file_bucket/lib/exoforge/std/file_bucket.ex:36,40,313-322` (`defaction upload_file(payload)`, `resolve_binary_data/2`) and `action_dispatcher.ex:443`
- **What**: `upload_file` had no scope (`authorize_scope(nil, _) -> :ok`) and accepted `payload["path"]`, calling `File.read(path)`. An anonymous player token calling `POST /api/file_bucket/upload_file` with `{"bucket":"x","filename":"h.txt","path":"/etc/hosts"}` returned HTTP 200 and a file record; `GET /api/files/x/<id>/h.txt` (unauthenticated) served `/etc/hosts`. Responses also leaked `disk_path`. **Status**: fixed in `exoforge` commits `acc8d06`/`33d0832`.
- **Impact**: Arbitrary file read on the cluster host (`.env`, tokens, SQLite DBs) by any caller on any deployed cluster.
- **Suggested fix**: Drop `path` from the transport action (or restrict to `:server`/internal), give `upload_file` and other file actions explicit scopes, require auth on `GET /api/files/...` for private buckets, and omit `disk_path` from responses.
- **Found by**: `doodle-5`, `F20`

### SEC-2 — Any player can overwrite or delete any other player's bucket file
- **Severity**: 1 (Security)
- **Kind**: bug
- **Where**: `exoforge_std_file_bucket` (`update_file`, `delete_file`)
- **What**: `POST /api/file_bucket/update_file` and `delete_file` succeed with a different anonymous player's token because file records have no owner check.
- **Impact**: Any player who knows a file ID (e.g. from public `browse`) can overwrite or delete another player's assets.
- **Suggested fix**: Store the uploader's `player_id` on the file record and enforce owner-or-admin checks on `update_file`/`delete_file`.
- **Found by**: `doodle-14`

### SEC-3 — `[ExoCron]` methods are exposed as `player`-scoped callable actions
- **Severity**: 1 (Security)
- **Kind**: bug
- **Where**: `Exoforge.Plugin.Generator` / cron action registration (`POST /api/brainrot_market/tick_prices`)
- **What**: A `[ExoCron("* * * * *")]` method is registered as an action with the default `player` scope. Calling `POST /api/brainrot_market/tick_prices` with a regular player token returned `{"data":{},"status":"ok"}`.
- **Impact**: Any player can trigger background cron jobs that mutate shared game state.
- **Suggested fix**: Assign `Scope = "server"` (or internal-only) to `[ExoCron]` methods by default.
- **Found by**: `economy-6`

### SEC-4 — `[ExoWebhook]` routes are unauthenticated with no doc warning or signature-check guide
- **Severity**: 1 (Security)
- **Kind**: missing
- **Where**: `extensions/exoforge_std_http/lib/exoforge/std/http/router.ex:148-202` vs `Attributes.cs` & served `02_csharp_attributes.md`
- **What**: `/api/webhooks/:service/:action` and `/api/webhook/:service/:action` dispatch any unauthenticated HTTP request with `caller_scopes: ["webhook", "global"]`. Neither `Attributes.cs` nor the docs warn that anyone on the internet can invoke them or show how to verify HMAC signatures.
- **Impact**: Developers ship unauthenticated webhook handlers (e.g. currency/store fulfillment) open to forged requests.
- **Suggested fix**: Warn prominently in `[ExoWebhook]` docs and provide a working HMAC verification example.
- **Found by**: `F11`, `audit`

### SEC-5 — Player error replies include `logs` with server stack traces and host absolute paths *(still open)*
- **Severity**: 1 (Security)
- **Kind**: bug
- **Where**: `extensions/exoforge_std_http/lib/exoforge/std/http/router.ex:330,336-364` (`logs = Exoforge.ExtensionLogs.for_rid(rid)`)
- **What**: `router.ex` attaches `for_rid(rid)` to every HTTP action response with no role check. With an anonymous player token, failing `game_menu.claim_gift` returned `{"logs":["[ERROR] …ExoActionException: … at Exoforge.Extensions.GameMenuExtension.SaveSettings(…) in /Users/alexcs/projects/exoforge-arcade/Exoforge/extensions/game_menu/src/GameMenuExtension.cs:line 32 …"]}`, including nested frames and logs from a *different* extension (`wallet/src/WalletExtension.cs:line 15`).
- **Impact**: Any player sees server internals, developer/host filesystem paths, and cross-service log messages (including any logged secret).
- **Suggested fix**: Include `logs` only for staff scopes (or a dev flag), never for player/guest callers.
- **Found by**: `menu-6`, `F21`

### SEC-6 — `Scope = "server"` is reachable via `exo call` (admin), contradicting `roles.ex`
- **Severity**: 1 (Security)
- **Kind**: contradiction
- **Where**: `core/lib/auth/roles.ex:60-63,90-96` vs `core/lib/action_dispatcher.ex` (`authorize_scope(:server, ...)`)
- **What**: `roles.ex` states `server` means "never reachable from a transport". `Scope = "server"` rejects players (`forbidden_scope`), **but** `exo call wallet credit ...` as `admin` succeeded and credited coins. Additionally, `admin` holds `"service"` in `@role_scopes` while `studio` does not (blocking `studio` from `service` actions in Studio Action Sandbox), and extension→extension calls use `dispatch_internal` which skips all scope checks and forwards no caller identity.
- **Impact**: No documented or enforced "internal extensions only" scope exists; leaked admin/service tokens can invoke sensitive economy actions.
- **Suggested fix**: Make `authorize_scope(:server, ...)` reject all non-`:internal` callers (including `admin`), document the full scope matrix, and clarify `service` vs `server`.
- **Found by**: `economy-2`, `F6`, `F12`, `dungeon-12`

### SEC-7 — No documented per-player topic isolation; shared-topic events broadcast to all subscribers
- **Severity**: 1 (Security)
- **Kind**: missing
- **Where**: Served `02_csharp_attributes.md` (`Topic = "player:*"`, `"guild:{guild_id}"`) vs `ws` gateway / `EventDispatcher`
- **What**: Docs use `"player:*"` and `"guild:{guild_id}"` in examples without documenting whether per-player topics exist or whether a player can subscribe to another player's topic. Events emitted with `Scope = "global"` on a shared topic (e.g. `achievements:feed`) are delivered to every subscribed player.
- **Impact**: Developers either leak private notifications to all subscribers or guess topic-authorization rules.
- **Suggested fix**: Document per-player topic conventions and server-side subscription authorization rules.
- **Found by**: `achievements-9`, `dungeon-11`

### SEC-8 — Elixir `defaction` ignored contract scope when omitted — 18 `:server`/`:studio` actions ran as `:player` *(fixed)*
- **Severity**: 1 (Security)
- **Kind**: bug
- **Where**: `core/lib/extension.ex:52` (`defaction` defaulted `scope` to `:player`) and `core/lib/action_dispatcher.ex` (`fetch_action_scope/2`)
- **What**: `fetch_action_scope/2` only consulted the contract when the implementation's scope was `nil`, which it never was because `defaction` defaulted to `:player`. Consequently, 18 standard actions declared as `:server`/`:studio` in their contracts ran as `:player` (`database.execute` and `table_columns`, `lldb.connection_config`, all 7 `file_bucket` actions, `dashboard(_view).*`, `observability.error_groups`/`recent_events`). Reproduced live: an anonymous player ran `SELECT 1` via `database.execute` against `plugin: "auth"`. **Status**: fixed (`defaction` records `scope_explicit`; defaulted scope takes the contract's when stricter than `:global`; note stale `_build` requires `mix deps.compile --force`).
- **Impact**: Any player could execute arbitrary SQL against `auth` (password hashes, tokens) and call staff-only internal actions.
- **Suggested fix**: Keep `scope_explicit` enforcement and force-recompile path deps when core macros change.
- **Found by**: `F22`

### SEC-9 — Studio `:4005` served every bucket file publicly *(fixed)*; dev mode treats token-less requests as `dev:admin`
- **Severity**: 1 (Security)
- **Kind**: bug
- **Where**: `extensions/exoforge_std_dashboard/.../router.ex` (`pipeline :public_files` → `ApiController.serve_file/2`) and `ApiController.token_auth/2`
- **What**: Closing `/api/files` on `:4001` still left all bucket files open on Studio `:4005` via an empty `:public_files` pipeline. Separately, `ApiController.token_auth/2` treats any token-less request as `dev:admin` whenever dev tokens are allowed and `require_admin_auth` is off. **Status**: file route fixed (now applies public-bucket / signed-URL / staff check); dev-mode anonymous=admin remains by design for local dev.
- **Impact**: Any reachable dev cluster on a network is fully open as admin.
- **Suggested fix**: Make the dev-mode default loud in Studio header / `exo status` and never enable it when binding beyond localhost.
- **Found by**: `F23`

### SEC-10 — `auth.register`/`create_player` by admin without explicit id overwrote & demoted protected `admin` account *(fixed in `b5b1940`)*
- **Severity**: 1 (Security)
- **Kind**: bug
- **Where**: `exoforge_std_auth` (`register` / `create_player`), `exoforge_std_transport` (`sanitize_payload`), and `exo user create`
- **What**: When an admin called `auth.register` or `auth.create_player` over HTTP without an explicit `player_id`/`user_id`, `transport` `sanitize_payload` stamped the caller's `player_id` (`"admin"`), overwriting the protected `admin` account, demoting it to `player`, and changing its email (reproduced live). **Status**: fixed in `exoforge` commit `b5b1940` (`register` refuses the protected account; `exo user create` sends a fresh `user_id`).
- **Impact**: An admin creating a user via HTTP/CLI without an explicit ID locked themselves out and hijacked the `admin` record.
- **Suggested fix**: Fixed in `b5b1940`.
- **Found by**: orchestrator

### SEC-11 — `Exoforge.Std.Auth.Cache` was never flushed on `delete_user`/`update_user_roles`/`purge_disposable` *(fixed in `b5b1940`)*
- **Severity**: 1 (Security)
- **Kind**: bug
- **Where**: `extensions/exoforge_std_auth` (`Exoforge.Std.Auth.Cache`)
- **What**: `Exoforge.Std.Auth.Cache` had no TTL and was never invalidated on `delete_user`, `update_user_roles`, or `purge_disposable`, so deleted or demoted accounts' cached tokens retained their old scopes until server restart (reproduced live: a deleted user's token still authenticated). **Status**: fixed in `exoforge` commit `b5b1940`.
- **Impact**: Revoking/deleting a user or demoting an account did not take effect for cached tokens until restart.
- **Suggested fix**: Fixed in `b5b1940`.
- **Found by**: orchestrator

---

## 2. Bugs That Break a Tarball User (`BUG-1` – `BUG-16`)

### BUG-1 — Failed extension→extension calls return `null` or empty default object instead of throwing
- **Severity**: 2 (Breaks tarball user)
- **Kind**: bug
- **Where**: `PluginServices.g.cs` (`CallActionAsync<T>`), `HostBridge.CallAction*`, `core/lib/drivers/runtime/native_extension_runner.ex:678-687`
- **What**: When `wallet.debit` or `wallet.credit` throws `ExoActionException`, the runner returns `%{error: inspect(reason)}`. `CallActionAsync<WalletBalance>` does not throw — it returns `null` (when `brainrot_market` called `DebitAsync`, `buy_shares SKBD 100000` succeeded for free!) or an empty `WalletBalance` (`PlayerId == null, Coins == 0` in `game_menu`).
- **Impact**: Inter-extension calls silently swallow failures; failed debits/payments look like success.
- **Suggested fix**: Return structured `{code, message}` errors from `dispatch_internal` and throw `ExoActionException(code, message)` in `CallAction*`.
- **Found by**: `economy-1`, `menu-4`

### BUG-2 — `[ExoWebhook]` handlers always receive `null` `WebhookPayload`; `EXO004` forbids any other signature
- **Severity**: 2 (Breaks tarball user)
- **Kind**: bug
- **Where**: `PluginHost.cs:610-620`, `ExoforgePluginGenerator.cs:115-121` (`EXO004`), `router.ex:176-184`
- **What**: `router.ex` sends top-level keys `{body, raw_body, json, headers, method, query}`. `PluginHost` binds arguments by parameter name, so `HandleStripeWebhook(WebhookPayload payload)` receives `payload == null` (verified via log `webhook null=True` and `NullReferenceException`), while `EXO004` refuses any other parameter signature on `[ExoWebhook]`.
- **Impact**: `[ExoWebhook]` is completely unusable as documented; workaround requires using `[ExoAction(Scope = "webhook")]` with `(string rawBody, Dictionary<string,string> headers, JsonElement json)`.
- **Suggested fix**: Bind a `WebhookPayload` parameter to the whole incoming payload object.
- **Found by**: `economy-4`, `audit-3`

### BUG-3 — `ExoClient.UploadFileAsync(..., metadata)` causes HTTP 500 with empty body
- **Severity**: 2 (Breaks tarball user)
- **Kind**: bug
- **Where**: `Exoforge.Client.dll` (`UploadFileAsync`) vs `POST /api/files/upload` (`router.ex`)
- **What**: `UploadFileAsync` sends `metadata` as a single multipart form field containing a JSON string, whereas the server expects a map (`metadata[key]=...`). Sending a JSON string causes HTTP 500 with empty body, and `ExoClient` crashes with `JsonReaderException: The input does not contain any JSON tokens`.
- **Impact**: Uploading files with metadata from Unity fails on the first try.
- **Suggested fix**: Send `metadata[key]` form fields in `ExoClient.UploadFileAsync` (or decode JSON strings on the server) and never return an empty 500.
- **Found by**: `doodle-13`

### BUG-4 — `Exoforge.Plugin.SDK` NuGet is pinned to `0.1.0`, so tarball upgrades are ignored by cache
- **Severity**: 2 (Breaks tarball user)
- **Kind**: bug
- **Where**: `ExoScaffolder.cs:262` (`SdkPackageVersion = "0.1.0"`), `Editor/Plugins/NuGet~/Exoforge.Plugin.SDK.0.1.0.nupkg`, `~/.nuget/packages/exoforge.plugin.sdk/0.1.0/`
- **What**: NuGet treats package versions as immutable. Once any tarball's `0.1.0` is restored into `~/.nuget/packages/`, all subsequent tarball upgrades keep building extensions against the old cached `0.1.0` with no warning.
- **Impact**: Developers upgrading `com.exoforge.sdk` never get SDK or generator bugfixes in their extensions.
- **Suggested fix**: Version `Exoforge.Plugin.SDK` with the package version and scaffold `<PackageReference ... Version="<package version>" />`.
- **Found by**: `F19`

### BUG-5 — Workspace & per-extension `nuget.config` pin absolute, content-hashed `PackageCache` paths
- **Severity**: 2 (Breaks tarball user)
- **Kind**: bug
- **Where**: `Exoforge/nuget.config` (`ExoScaffolder.cs:189-214`, `ExoforgeIdeProjectGenerator.cs:98-128`), 14 per-extension copies, and `Exoforge/extensions/<name>.Tests/nuget.config`
- **What**: Writes `<add key="exoforge" value="/abs/path/.../Library/PackageCache/com.exoforge.sdk@388f2f3b4c6d/Editor/Plugins/NuGet~" />`. Although `ExoforgeIdeProjectGenerator.cs:98-128` rewrites the workspace and per-extension `nuget.config` files on Editor load (so Unity self-heals), the files are machine-specific yet live where a team commits them (churning on every machine across 14+ copies), a CLI-only clone that has never opened Unity has no `nuget.config` (so the first `exo extension build` fails to restore), and sibling `.Tests/` projects need their own copy.
- **Impact**: CLI-only clones fail to restore, committed `nuget.config` churns across machines, and `.Tests/` projects break without manual copies.
- **Suggested fix**: Use one workspace `nuget.config` pointing to a workspace-relative feed (e.g. copy the nupkg into `Exoforge/.packages/` on load), or have `exo` write it on demand, and document whether to commit it.
- **Found by**: `F13`, `economy-14`, `doodle-10`, `achievements-7`

### BUG-6 — Half of `com.exoforge.sdk-0.1.41.tgz` is macOS `._*` AppleDouble files
- **Severity**: 2 (Breaks tarball user)
- **Kind**: bug
- **Where**: `Justfile` `pack-unity` (`tar -czf` without `COPYFILE_DISABLE=1`)
- **What**: `com.exoforge.sdk-0.1.41.tgz` contains 266 entries, 133 of which are `._*`. `exo agents install` copies `._SKILL.md` into `.agents/`, `.claude/`, and `.gemini/` in the user's project.
- **Impact**: Pollutes project repositories and agent skill directories with binary AppleDouble files.
- **Suggested fix**: Build tarballs with `COPYFILE_DISABLE=1` and fail `pack-unity` if any `._` entry is present.
- **Found by**: `F18`

### BUG-7 — `DatabaseExtensions.Put(record)` throws at runtime when `PrimaryKey` is snake_case
- **Severity**: 2 (Breaks tarball user)
- **Kind**: bug
- **Where**: `sdk/csharp/Exoforge.Plugin.SDK/DatabaseExtensions.cs:256` (`EntityMetadata<T>`)
- **What**: `EntityMetadata<T>` resolves `resAttr.PrimaryKey` via `type.GetProperty(resAttr.PrimaryKey, BindingFlags.Public | BindingFlags.Instance | BindingFlags.IgnoreCase)`. For `[ExoResource("leaderboard_entries", PrimaryKey = "player_id")]` with C# property `PlayerId` (as shown in `exoforge-resources/SKILL.md`), `GetProperty("player_id")` returns `null` and `db.Put(record)` throws `InvalidOperationException: Cannot determine primary key`.
- **Impact**: `Put(record)` crashes at runtime unless `[ExoColumn(PrimaryKey = true)]` is also added or `Put(key, record)` is used.
- **Suggested fix**: Match `ExoNaming.ToSnakeCase(prop.Name)` against `resAttr.PrimaryKey` in `EntityMetadata<T>`.
- **Found by**: `audit-5`, `F4`

### BUG-8 — Only the first `OnEvent` overload is called, and extensions receive their own emitted events
- **Severity**: 2 (Breaks tarball user)
- **Kind**: bug
- **Where**: `sdk/csharp/Exoforge.Plugin.SDK/PluginHost.cs:242-257` (`FindEventHandler`)
- **What**: `FindEventHandler` returns the first method named `OnEvent`. Multiple typed overloads (`OnEvent(string, EnemySlain)`, `OnEvent(string, ChestOpened)`) compile, but every event is deserialized as the first overload's type. Additionally, an extension receives its own emitted events if it declared them, causing double-counting (`3` kills produced `count = 4`).
- **Impact**: Silent wrong deserialization and double-handling without errors.
- **Suggested fix**: Dispatch by event name to matching `OnEvent` overloads (or reject multiple overloads at build time) and filter or document self-emitted events.
- **Found by**: `achievements-3`

### BUG-9 — `Scope = "guest"` is rejected for `player`, `studio`, and `admin` callers (only literal `guest` token passes)
- **Severity**: 2 (Breaks tarball user)
- **Kind**: bug
- **Where**: `core/lib/auth/roles.ex:21,90-96`, `core/lib/action_dispatcher.ex:459`, and `auth.ex:134`
- **What**: `roles.ex` gives `"guest"` rank `0`. `authorize_scope` treats `rank <= 0` as requiring an exact string match in `caller_scopes`. **Correction**: a literal `guest` bearer token *does* carry `"guest"` (`auth.ex:134`), so guests themselves can call `[ExoAction(Scope = "guest")]`; however, `@role_scopes` never includes `"guest"` in `player`, `studio`, or `admin`, so higher roles are rejected — contradicting `roles.ex`'s `admin > studio > player > guest` hierarchy.
- **Impact**: Any `[ExoAction(Scope = "guest")]` rejects `player`, `studio`, and `admin` callers.
- **Suggested fix**: Either give `guest` a positive rank in the hierarchy or add `"guest"` to higher roles' `@role_scopes`.
- **Found by**: `F10`, `audit`

### BUG-10 — Rapid redeploy / push causes `extension_starting` then `startup_failed` timeout with empty logs
- **Severity**: 2 (Breaks tarball user)
- **Kind**: bug
- **Where**: `exo extension push` / `exo extension list` (`wallet`, `achievements`, `game_menu`, `level_share`)
- **What**: Pushing repeatedly or while other workers/events are active caused `push` to report `Verified: ... loaded (native)` (and even serve a first call), then fail with `{:extension_starting, ...}` followed by `{:extension_crashed, {:startup_failed, %{code: "timeout", message: "the startup hook did not finish"}}}` even on extensions with no `OnExtensionStart` hook (`wallet`, `level_share`) or trivial ones. `exo extension logs` printed `(no log lines recorded)`. `exo extension reload <name>` recovered it.
- **Impact**: A green `push` does not guarantee the extension stays up, and crashes leave zero diagnostic logs.
- **Suggested fix**: Have `push` wait until lifecycle settles, log startup hook timeouts/errors to extension logs, and check event frames arriving during lifecycle.
- **Found by**: `economy-10`, `achievements-4`, `menu-10`, `doodle-16`

### BUG-11 — Generated response DTOs are unprefixed in `Exoforge.Client`, colliding across extensions
- **Severity**: 2 (Breaks tarball user)
- **Kind**: bug
- **Where**: `Exoforge.Management/ExoCodeGenerator.cs` → `Assets/Exoforge/Generated/ExoforgeServices.g.cs`
- **What**: Request types are prefixed with the service (`LevelSharePublishRequest`), but response record types are emitted with bare global names (`PublishResult`, `ClearResult`, `Trade`, `Portfolio`) in `Exoforge.Client`.
- **Impact**: Two extensions returning records with the same name (e.g. `ClaimResult`, `Trade`) break Unity compilation.
- **Suggested fix**: Prefix generated response types with the service name just like request types.
- **Found by**: `doodle-8`, `economy-13`

### BUG-12 — `ExoClient` & HTTP wrap `ExoActionException` as `"http_error"` + Elixir tuple string
- **Severity**: 2 (Breaks tarball user)
- **Kind**: bug / confusing
- **Where**: `Exoforge.Client.dll`, `exo call`, and HTTP action error responses
- **What**: Throwing `new ExoActionException("clear_required", "...")` returns `{"error":"{:clear_required, \"...\"}"}` over HTTP/CLI, and `ExoClient` over WebSocket throws `ExoActionException` with `Code == "http_error"` and `Message == "[http_error] {:clear_required, \"...\"} (rid ...)"`.
- **Impact**: Unity gameplay code, `curl` scripts, and CLI callers cannot branch on `ex.Code`.
- **Suggested fix**: Return structured `{"error":{"code":...,"message":...}}` and preserve the extension's error `Code` in `ExoActionException`.
- **Found by**: `doodle-9`, `economy-9`, `menu-5`

### BUG-13 — `exo extension new <name>` silently overwrites existing extension source
- **Severity**: 2 (Breaks tarball user)
- **Kind**: bug
- **Where**: `Exoforge.CLI` / `ExoScaffolder.cs` (`exo extension new`)
- **What**: Running `exo extension new <name>` when `Exoforge/extensions/<name>` already exists prints `Scaffolded C# extension '<name>'` and overwrites `src/<Name>Extension.cs` without warning or prompt.
- **Impact**: Re-running `new` destroys existing extension code.
- **Suggested fix**: Refuse to overwrite a non-empty extension directory unless `--force` is passed.
- **Found by**: `doodle-1`, `achievements-5`, `menu-1`

### BUG-14 — `IsExternalInit` is `internal` to `Exoforge.SDK`, breaking `record` in game asmdefs
- **Severity**: 2 (Breaks tarball user)
- **Kind**: confusing / bug
- **Where**: `Runtime/IsExternalInit.cs` in `com.exoforge.sdk`
- **What**: Any Unity game asmdef defining a C# `record` fails with `error CS0518: Predefined type 'System.Runtime.CompilerServices.IsExternalInit' is not defined or imported`.
- **Impact**: Developers following the "records for payloads" style in game asmdefs hit immediate compile errors unless they add their own `IsExternalInit` shim.
- **Suggested fix**: Document the requirement or provide a separate optional polyfill asmdef.
- **Found by**: `doodle-11`

### BUG-15 — Two different tarballs shipped with identical version `0.1.41`
- **Severity**: 2 (Breaks tarball user)
- **Kind**: bug (process)
- **Where**: `~/Downloads/com.exoforge.sdk-0.1.41.tgz` (770,828 B) vs `dist/com.exoforge.sdk-0.1.41.tgz` (789,894 B)
- **What**: Package contents changed after `0.1.41` shipped without bumping `package.json` / `ExoforgePackageVersion.cs`.
- **Impact**: UPM caches the first `0.1.41` and silently ignores the newer one.
- **Suggested fix**: Enforce version bumps on every tarball build that changes package contents.
- **Found by**: `F14`

### BUG-16 — Anonymous login with `name` fails with `:name_taken` globally
- **Severity**: 2 (Breaks tarball user)
- **Kind**: bug
- **Where**: `POST /api/auth/anonymous {"name":"..."}`
- **What**: Once any player uses a display name, another anonymous login passing `"name"` fails with `{"error":":name_taken"}`.
- **Impact**: Breaks demos/tests or players who pick a common name during anonymous sign-in.
- **Suggested fix**: Allow non-unique display names for anonymous accounts or return a structured error code.
- **Found by**: `doodle-14`

### BUG-17 — `OnEvent` is re-entered during pending host calls, losing updates and dropping outer `host_call_result` frames
- **Severity**: 2 (Breaks tarball user)
- **Kind**: bug
- **Where**: `sdk/csharp/Exoforge.Plugin.SDK/PluginHost.cs:782-792` (host-call wait loop) vs `02_csharp_attributes.md`
- **What**: While blocked waiting for `host_call_result` matching `id`, `PluginHost.cs:783-785` calls `DispatchEvent(line)` inline on `case "event":` on the same thread/stdin loop. Two failures result:
  1. Any `OnEvent` handler that performs a host call (`Exo.Database.*`, `Exo.Events.EmitAsync`) can be re-entered on the same stack. C# `lock` is re-entrant, so it does not serialize: a nested `enemy_slain` overwrote progress before the outer handler wrote its stale count (reproduced in `AchievementsTests.An_event_delivered_during_a_host_call_is_not_lost_or_double_counted`).
  2. The nested host-call wait loop reads from `_stdin` and only returns when `idProp.GetInt64() == innerId` (`PluginHost.cs:793-798`); if the outer `host_call_result` arrives while the nested `OnEvent`'s host call is waiting, the inner `switch` ignores and **drops the outer `host_call_result`**, hanging or breaking the outer host call.
- **Impact**: Any event listener performing read-modify-write host calls can silently lose updates, double-count, or drop outer `host_call_result` frames under load, while docs claim single-process execution needs no locking.
- **Suggested fix**: Queue `event` frames while a host call is pending and dispatch them sequentially from the main loop (just like `BufferedActions` on line 790).
- **Found by**: `achievements-10`, reviewer

---

## 3. Docs That Are Wrong (`DOC-1` – `DOC-13`)

### DOC-1 — `exoforge-extensions` skill uses non-existent `Exo.Events.Publish` and wrong default `Scope`
- **Severity**: 3 (Wrong docs)
- **Kind**: doc-wrong
- **Where**: `Agents~/skills/exoforge-extensions/SKILL.md:30,65,77,80` vs `Interfaces.cs:55` and `Attributes.cs:81`
- **What**: Line 65 calls `Exo.Events.Publish("daily_rewards.claimed", new { ... })`, which fails to compile (`CS1061: 'IEventDispatcher' does not contain a definition for 'Publish'`; real API is `await Exo.Events.EmitAsync(...)`). Line 77 says "default or omitting scope permits public calls", whereas `ExoActionAttribute.Scope` defaults to `"player"` (`Attributes.cs:81`).
- **Impact**: Every developer or agent following the skill writes broken code and misunderstands action security defaults.
- **Suggested fix**: Replace `Publish` with `await Exo.Events.EmitAsync(...)` and state `Scope = "player"` is the default.
- **Found by**: `audit-1`, `F3`, `F6`, `economy-15`, `dungeon-1`, `doodle-2`, `doodle-3`, `achievements-6`, `achievements-8`, `menu-2`

### DOC-2 — Served `[ExoWebhook]` examples fail to compile (`EventName`/`Data`/`Success()` and `EXO004`)
- **Severity**: 3 (Wrong docs)
- **Kind**: doc-wrong
- **Where**: Served `02_csharp_attributes.md` (`docs.export_docs` L474-478) & `04_use_cases_and_patterns.md` (L941-960) vs `Attributes.cs:457-485`
- **What**: `04_use_cases_and_patterns.md` accesses non-existent `payload.EventName`, `payload.Data[...]`, and `WebhookResult.Success()` (`CS1061`, `CS0117`). `02_csharp_attributes.md` uses `HandleStripeWebhook(StripeWebhookPayload payload)`, failing Roslyn analyzer `EXO004`.
- **Impact**: Copy-pasting either webhook doc example fails to build.
- **Suggested fix**: Update both chapters to use `WebhookPayload` (`Json`, `RawBody`, `Headers`) and `new WebhookResult(...)`.
- **Found by**: `audit-2`, `audit-3`

### DOC-3 — Served blueprints omit DTOs, use undefined `PlayerDataRecord`, and misplace `Topic`
- **Severity**: 3 (Wrong docs)
- **Kind**: doc-wrong
- **Where**: Served `04_use_cases_and_patterns.md` (`docs.export_docs` L608-680, 766-876)
- **What**: Auction House, World Boss, and Guild examples omit `*Request`/`*Response` DTOs and reference non-existent `typeof(PlayerDataRecord)`. Guild's `EmitAsync(new GuildActivityEvent($"guild:{guild.Id}", ...))` puts the dynamic topic in the record instead of `EmitAsync(payload, topic)`'s second argument.
- **Impact**: Blueprints don't compile as written, and dynamic topic routing silently falls back to `DefaultTopic`.
- **Suggested fix**: Include DTOs, drop `PlayerDataRecord`, and pass dynamic topic as the 2nd argument to `EmitAsync`.
- **Found by**: `audit-4`

### DOC-4 — Installing tarball does not create `Exoforge/` or `./exo`; documented fallback path is wrong
- **Severity**: 3 (Wrong docs)
- **Kind**: doc-wrong
- **Where**: `Agents~/AGENTS.md` §1
- **What**: Claims `./exo` is available or fallback `dotnet Packages/com.exoforge.sdk/Editor/Cli~/exo.dll`. After a tarball import, neither `Exoforge/` nor `./exo` exists, and `Packages/com.exoforge.sdk/...` only exists for embedded packages (tarball unpacks to `Library/PackageCache/com.exoforge.sdk@<hash>/Editor/Cli~/exo.dll`). Requires `init --dir Exoforge` and `agents install`.
- **Impact**: Headless/tarball CLI setup fails at step 1.
- **Suggested fix**: Document the `Library/PackageCache/com.exoforge.sdk@*/Editor/Cli~/exo.dll` path and `init`/`agents install`.
- **Found by**: `F16`

### DOC-5 — CLI help & error messages tell tarball users to run repo-only `just` commands
- **Severity**: 3 (Wrong docs)
- **Kind**: doc-wrong
- **Where**: `Exoforge.CLI/Program.cs:1328,1725,1977` (`exo extension new --help`, `stubs`, `status`/`connect`)
- **What**: Prints ``run `just pack-sdk` to fill the local feed from a checkout`` and ``Is it running (`just dev`)``. Tarball users have neither the repo nor `just`.
- **Impact**: Misleads tarball users when offline or scaffolding extensions.
- **Suggested fix**: Remove repo-only `just` instructions from shipped CLI output.
- **Found by**: `audit-6`, `dungeon-5`, `doodle-1`, `menu-1`

### DOC-6 — `--json` is documented on `exo extension new/build/push` & errors, but ignored
- **Severity**: 3 (Wrong docs)
- **Kind**: doc-wrong
- **Where**: `Agents~/AGENTS.md:14,20`, `Agents~/skills/exoforge-extensions/SKILL.md:23,87,92,100` vs `Program.cs:1319,1363,1384`
- **What**: `HandleExtensionNew`, `HandleExtensionBuild`, and `HandleExtensionPushAsync` ignore `--json` and emit plain text; `exo call` errors emit plain-text Elixir tuples (`[http_error] {:code, ...}`) instead of JSON.
- **Impact**: Scripts/agents expecting JSON on stdout fail.
- **Suggested fix**: Emit JSON for `--json` on all commands and error paths, or remove `--json` from unsupported commands in docs.
- **Found by**: `audit-7`, `economy-9`

### DOC-7 — `exoforge-connection` skill lists non-existent `exo status --json` fields
- **Severity**: 3 (Wrong docs)
- **Kind**: doc-wrong
- **Where**: `Agents~/skills/exoforge-connection/SKILL.md:51-55`
- **What**: Documents `reachable`, `latency_ms`, and `active_extensions`. Actual output is `{"system": {"extensions_count": 23, "version": "0.1.20", ...}}`.
- **Impact**: Scripts checking `reachable` or `active_extensions` fail.
- **Suggested fix**: Update `SKILL.md` to match the real `{"system": {...}}` output.
- **Found by**: `audit-8`

### DOC-8 — SDK XML docs list `Name` on `[ExoCron]`/`[ExoWebhook]`, which fails with `CS0617`
- **Severity**: 3 (Wrong docs)
- **Kind**: doc-wrong
- **Where**: `Exoforge.Plugin.SDK.xml` (`ExoCronAttribute.Name`, `ExoWebhookAttribute.Name`)
- **What**: `[ExoCron("* * * * *", Name = "tick_prices")]` fails with `error CS0617: 'Name' is not a valid named attribute argument`; `Name` is read-only and must be passed positionally.
- **Impact**: Compile error when setting `Name = ...`.
- **Suggested fix**: Add a setter or fix the XML docs to specify positional constructor usage.
- **Found by**: `economy-5`

### DOC-9 — `PluginServices.g.cs` header cites non-existent `exo plugin stubs` command
- **Severity**: 3 (Wrong docs)
- **Kind**: doc-wrong
- **Where**: Generated `src/Generated/PluginServices.g.cs` header (`Exoforge.Management`)
- **What**: Header says `Regenerate with exo plugin stubs <name>`. There is no `exo plugin` command; the real command is `exo extension stubs <name>`.
- **Impact**: Developers following the header get `Unknown command: plugin`.
- **Suggested fix**: Update the generated header to `exo extension stubs <name>`.
- **Found by**: `economy-12`

### DOC-10 — Scopes (`service`, `server`, `global`, `webhook`), `[ExoDependency]`, and `[ExoEvent]` subscription undocumented
- **Severity**: 3 (Wrong/missing docs)
- **Kind**: missing
- **Where**: `README.md`, `Agents~/skills/exoforge-extensions/SKILL.md`, served `02_csharp_attributes.md`
- **What**:
  1. `roles.ex:65` defines 8 scopes (`admin`, `studio`, `player`, `guest`, `service`, `server`, `global`, `webhook`), but docs omit `service`, `server`, `global`, `webhook`.
  2. Calling another extension via `HostBridge` or `Exo.Actions.CallAction` fails at runtime (`service_not_declared` / `InvalidOperationException` with misleading `"Add '...' to your extension dependencies and regenerate stubs"`) unless `[ExoDependency("...")]` is added, while `InMemoryActionDispatcher` does not enforce it in unit tests. No tarball skill mentions `[ExoDependency]` as a call permission (`02_csharp_attributes` only describes it as boot order).
  3. Implementing `OnEvent` in C# does nothing unless the listening extension *also* declares matching `[ExoEvent(..., Topic = ...)]` records in its own assembly — undocumented everywhere.
- **Impact**: Developers cannot build inter-extension calls, service-scoped endpoints, or event listeners from the docs, and unit tests pass even when `[ExoDependency]` is missing.
- **Suggested fix**: Document the full scope table, `[ExoDependency]` call permission (and enforce it in `InMemoryActionDispatcher`), and `[ExoEvent]` subscription rules.
- **Found by**: `F6`, `economy-3`, `dungeon-2`, `dungeon-9`, `doodle-15`, `achievements-1`, `menu-3`

### DOC-11 — Core SDK & backend workflows undocumented in tarball docs
- **Severity**: 3 (Missing docs)
- **Kind**: missing
- **Where**: Package `README.md`, `Agents~/**`, `Samples~/**`, served chapters 01–04
- **What**: None of the tarball docs cover:
  - `ExoTestHost`, `ExoTestContext`, and `InMemory*` test fakes (shipped in `Exoforge.Plugin.SDK.0.1.0.nupkg`, plus `CallerPlayerId`/`CallerScopes` properties);
  - `AllowPlayerRead` client usage (`ExoServices.ResourceStore.ListAsync(new ResourceStoreListRequest { Resource = "..." })`);
  - HTTP REST routes (`POST /api/<service>/<action>`, `POST /api/auth/anonymous`, `POST /api/files/upload`, `GET /api/files/...`);
  - `ExoClient.UploadFileAsync` / `DownloadFileAsync`, `file_bucket` usage, and `file_bucket.get_file_info`'s response shape (`{"file": {id, bucket, sha256, content_type, url, ...}}`);
  - `auth.issue_token` for `service`-role server tokens and `ExoClient` direct usage for non-player actions (omitted from `ExoforgeServices.g.cs`);
  - Unity asmdef references (`Exoforge.SDK`, `Exoforge.Generated`) and namespaces (`Exoforge.Client` vs `Exoforge.Client.Unity`).
- **Impact**: Developers have to inspect DLLs via reflection or read the Exoforge repo to use these features.
- **Suggested fix**: Add concise sections for testing, HTTP routes, `AllowPlayerRead`, `file_bucket` (with a typed contract), `service` tokens, and Unity asmdefs.
- **Found by**: `audit-10`, `economy-7`, `economy-8`, `economy-14`, `dungeon-3`, `dungeon-4`, `dungeon-10`, `doodle-4`, `doodle-6`, `doodle-10`, `doodle-12`, `doodle-17`, `achievements-7`, `menu-9`

### DOC-12 — Repo `ATTRIBUTES.md` §4 still cites non-existent `ExoforgeSDK.Events.Subscribe`
- **Severity**: 3 (Wrong docs)
- **Kind**: doc-wrong
- **Where**: `sdk/csharp/Exoforge.Plugin.SDK/ATTRIBUTES.md:148`
- **What**: Resolved in served `02_csharp_attributes.md` (`ExoServices.<Service>.SubscribeAsync`), but repo `ATTRIBUTES.md` still shows `ExoforgeSDK.Events.Subscribe<TEvent>`, which does not exist.
- **Suggested fix**: Update `ATTRIBUTES.md` §4 to match `02_csharp_attributes.md`.
- **Found by**: `F8`, `audit`

### DOC-13 — Repo `AGENTS.md` says `ExtensionServices.g.cs` instead of `PluginServices.g.cs`
- **Severity**: 3 (Wrong docs)
- **Kind**: doc-wrong
- **Where**: Repo root `AGENTS.md:257` vs `Program.cs:1713`, `ExoDeployer.cs:374`, `01_quickstart.md:113`
- **What**: Root `AGENTS.md` says `exo extension stubs` writes `src/Generated/ExtensionServices.g.cs`; actual code and served docs write `src/Generated/PluginServices.g.cs`.
- **Suggested fix**: Update `AGENTS.md:257` to `PluginServices.g.cs` (or rename the generated file).
- **Found by**: `F5`, `audit`

---

## 4. Contradictions & Confusing Points (`CONF-1` – `CONF-12`)

### CONF-1 — Extension template list differs across 4 places and `new` ignores `--template`
- **Severity**: 4 (Contradiction)
- **Kind**: contradiction
- **Where**: `ExoScaffolder.cs:22` (6), `README.md:22` (5), `Agents~/AGENTS.md:61` & `SKILL.md:27-30` (4), `exo extension new --help` (1: `standard`)
- **What**: Each doc lists a different set of templates, and `exo extension new --template events` / `persistent` generates the exact same daily-claim sample.
- **Suggested fix**: Align all docs and `--help` with the actual templates implemented in `ExoScaffolder`.
- **Found by**: `F7`, `audit`, `dungeon-5`, `doodle-1`, `achievements-5`, `menu-1`

### CONF-2 — Scaffold targets `net10.0` while docs state `.NET 9+`
- **Severity**: 4 (Contradiction)
- **Kind**: contradiction
- **Where**: Scaffolded `*.csproj` (`<TargetFramework>net10.0</TargetFramework>`) vs `README.md:58`, `AGENTS.md`, `SKILL.md:14` (`.NET 9+`)
- **What**: On a machine with only .NET 9 SDK installed, scaffolded extensions targeting `net10.0` will fail to build.
- **Suggested fix**: Either state `.NET 10` as minimum or template `net9.0`.
- **Found by**: `economy-11`, `dungeon-6`

### CONF-3 — `README.md` requires `Exoforge.prefab` while `01_quickstart.md` says "Zero Scene Wiring"
- **Severity**: 4 (Contradiction)
- **Kind**: contradiction
- **Where**: Package `README.md:17,117` & `Samples~/BasicUsage/README.md:9` vs served `01_quickstart.md:20` (`ExoforgeSDK.cs:18-19`)
- **What**: `README.md` tells users to add `ExoforgeManager` (`Exoforge ▸ Add Exoforge to Scene`), while `01_quickstart.md` and `ExoforgeSDK.cs` state `ExoforgeManager` is created on demand with zero scene wiring.
- **Suggested fix**: Align `README.md` and `BasicUsage/README.md` with zero-wiring behavior.
- **Found by**: `audit-9`

### CONF-4 — Snake sample swaps `name` and `playerId`, masked by `sanitize_payload`
- **Severity**: 4 (Confusing)
- **Kind**: bug / confusing
- **Where**: `sdk/unity/sample_unity/Assets/SnakeGame/SnakeLeaderboard.cs:141-142` vs `extensions/exoforge_std_transport/lib/exoforge/std/transport.ex:64-78`
- **What**: `SubmitScoreAsync` passes `(session.DisplayName, session.PlayerId, ...)`; `transport.ex` silently overwrites `player_id` with the caller's ID, masking the bug on the stored row while `name` gets the `PlayerId`.
- **Suggested fix**: Fix `SnakeLeaderboard.cs` argument order and prefer `Exo.Context.CallerPlayerId` over a `player_id` action parameter.
- **Found by**: `F1`, `F2`, `audit`

### CONF-5 — `Exo.*` vs `ExoServices.*` and `Database.Get(id)` vs `Get(table, key)` mixed without explanation
- **Severity**: 4 (Confusing)
- **Kind**: confusing
- **Where**: `ExoforgePluginGenerator.cs:47,92`, `DatabaseExtensions.cs`, `README.md`, `SKILL.md`
- **What**: `Exo` and `ExoServices` both compile (and `Exo.Services` does not exist), and both `Get<T>(key)` and `Get<T>("table", key)` compile (with `Put(record)` subject to `BUG-7`), but docs and samples switch between them without explaining they are aliases/overloads.
- **Suggested fix**: Pick one canonical style (`Exo.*` + `Get<T>(key)`) and note the alias/table-name overloads.
- **Found by**: `F3`, `F4`, `audit`, `economy-15`, `doodle-2`, `achievements-6`, `menu-2`

### CONF-6 — Declaring `[ExoEvent]` to subscribe makes listener look like emitter in contracts/stubs
- **Severity**: 4 (Confusing)
- **Kind**: confusing
- **Where**: `exo contracts`, generated `ExoforgeServices.g.cs`
- **What**: Because listening requires declaring `[ExoEvent]` records on the listener (`DOC-10`), `achievements` appears in contracts and Unity stubs as emitting `enemy_slain`, `chest_opened`, etc., and `AchievementsServiceClient.SubscribeAsync()` defaults to `world:feed` instead of `achievements:feed`.
- **Suggested fix**: Introduce a distinct `[ExoListen]` (or subscription manifest entry) excluded from emitted contracts and client stubs.
- **Found by**: `achievements-2`

### CONF-7 — `SubscribeAsync` defaults to first topic only; nested `IReadOnlyList<T>` degrades to `JsonElement`
- **Severity**: 4 (Confusing)
- **Kind**: confusing
- **Where**: `ExoforgeServices.g.cs` (`ExoCodeGenerator.cs`)
- **What**: A service with multiple event topics gets a single `SubscribeAsync(string topic = "<first>")` helper, so events on secondary topics require spelling out the topic string. Records wrapping `IReadOnlyList<T>` emit `JsonElement` properties, whereas returning `List<T>` directly generates typed lists.
- **Suggested fix**: Generate per-topic subscribe helpers and emit typed lists inside response records.
- **Found by**: `economy-13`, `doodle-7`

### CONF-8 — `resource_store.list` returns `:resource_not_found` when unreadable; `ListAsync` convenience overload unusable
- **Severity**: 4 (Confusing)
- **Kind**: confusing
- **Where**: `exoforge_std_resources` & `ExoforgeServices.g.cs` (`ResourceStoreServiceClient.ListAsync`)
- **What**: Non-`AllowPlayerRead` tables return `:resource_not_found` instead of `forbidden` to players, and the convenience `ListAsync(JsonElement offset, JsonElement sort, JsonElement filter, JsonElement search, JsonElement limit, string resource)` requires 5 `JsonElement` arguments instead of optional/nullable primitives.
- **Suggested fix**: Return `forbidden` for existing restricted tables (or document the behavior) and generate typed `ListAsync<T>` helpers.
- **Found by**: `menu-7`, `menu-8`, `economy-7`

### CONF-9 — `ExoTestHost` / `ExoServices.*` static state is not parallel-safe across xunit classes
- **Severity**: 4 (Confusing)
- **Kind**: confusing
- **Where**: `Exoforge.Plugin.SDK` (`PluginHost.CurrentContext`, static `ExoServices.*`)
- **What**: `ExoTestHost.Start` states it starts an "isolated in-memory test context", but the ambient context and `ExoServices.<Service>` stub overrides are process-wide statics. Running multiple xunit test classes in parallel causes cross-test database/stub failures unless `[assembly: CollectionBehavior(DisableTestParallelization = true)]` is set.
- **Suggested fix**: Use `AsyncLocal` for test contexts/overrides or document `DisableTestParallelization = true`.
- **Found by**: `dungeon-8`, `menu-9`, `economy-14`, `achievements-7`

### CONF-10 — Two players on one machine share `PlayerPrefs` (`ExoDeviceId`/`ExoTokenStore`) by default
- **Severity**: 4 (Confusing)
- **Kind**: confusing
- **Where**: `Runtime/ExoDeviceId.cs`, `Runtime/ExoTokenStore.cs`, `Runtime/ExoforgeAuth.cs`
- **What**: Both `ExoDeviceId` and `ExoTokenStore` persist to OS `PlayerPrefs` with no per-process, CLI-arg, env-var, or MPPM clone namespacing. Two instances on the same machine sign into the same account by default; calling `Mask()`/`Impersonate()` mutates shared `PlayerPrefs`. Developers must either use Studio **Mask Device ID** sequentially, call `ExoDeviceId.Impersonate(arg)` from custom startup args, or pass explicit `auth.anonymous` tokens to `ExoClient.UseToken`.
- **Suggested fix**: Support optional profile/instance key suffixing (e.g. CLI arg or MPPM player id) in `ExoDeviceId`/`ExoTokenStore` and document multi-player local testing.
- **Found by**: `audit`

### CONF-11 — `file_bucket` has no tags feature despite `README.md` §4
- **Severity**: 4 (Contradiction)
- **Kind**: contradiction
- **Where**: `exoforge-arcade/README.md` §4 vs `exoforge_std_file_bucket`
- **What**: `file_bucket` supports `bucket` and string `metadata` only — there is no `tags` field or tag query.
- **Suggested fix**: Drop `tags` from `README.md` §4 or add tag support to `file_bucket`.
- **Found by**: `doodle-4`

### CONF-12 — `exo status` reports stale build metadata; in-repo `sample_unity` masks tarball bugs
- **Severity**: 4 (Confusing)
- **Kind**: confusing
- **Where**: `exo status` (`commit_hash: fb889f1`, `version: 0.1.20` on HEAD `9d47cb3`) & `sdk/unity/sample_unity`
- **What**: `exo status` reports stale build metadata, and `sample_unity` builds against repo `Directory.Build.targets` / `NuGet.config` from source so it cannot catch tarball packaging bugs.
- **Suggested fix**: Stamp real build metadata in `exo status` and keep tarball smoke tests outside the repo.
- **Found by**: `F15`, `F17`

### CONF-13 — `AllowPlayerRead` exposes all rows with no per-player filter, easily misapplied to per-player tables
- **Severity**: 4 (Confusing)
- **Kind**: confusing
- **Where**: `ExoResourceAttribute.AllowPlayerRead` (spotted on `wallet_balances` in review)
- **What**: Setting `AllowPlayerRead = true` makes every row in the table readable via `resource_store.list`/`get`, not just the caller's own rows. Putting it on a per-player table like `wallet_balances` lets any player list everyone's balances.
- **Suggested fix**: Add a per-row caller filter option (`PlayerId == caller`) or rename to `AllowPublicRead`.
- **Found by**: `economy-16`, reviewer

---

## 5. Nits (`NIT-1` – `NIT-4`)

### NIT-1 — Legacy "Plugin" naming survives the extension rename
- **Severity**: 5 (Nit)
- **Kind**: confusing
- **Where**: `plugins_csharp/`, `Exoforge.Plugin.SDK`, `PluginServices.g.cs`, `PluginHost`, `<ExoforgePlugin>`, wire key `"plugin"`
- **What**: Mixed "plugin" and "extension" terminology across packages, MSBuild flags, and wire frames after Phase 1 rename.
- **Suggested fix**: Decide whether to keep `Plugin` as internal/package ID or schedule a clean rename.
- **Found by**: `F9`, `audit`

### NIT-2 — Scaffolded `.gitignore` omits `bin/` and `obj/`
- **Severity**: 5 (Nit)
- **Kind**: confusing
- **Where**: `ExoScaffolder.cs` → `Exoforge/extensions/<name>/.gitignore`
- **What**: Generated `.gitignore` lists `/.exoforge/`, `/.buildcount`, `/manifest.json`, leaving `src/bin/` and `src/obj/` untracked in git.
- **Suggested fix**: Add `bin/` and `obj/` to the scaffolded `.gitignore`.
- **Found by**: `dungeon-7`

### NIT-3 — `PluginServices.g.cs` emits duplicate types and maps `int`→`long`, `DateTime`→`JsonElement`
- **Severity**: 5 (Nit)
- **Kind**: confusing
- **Where**: `src/Generated/PluginServices.g.cs` (`ExoCodeGenerator.cs`)
- **What**: Emits duplicate records (`WalletWalletBalance` and `WalletBalance`), widens `int` to `long`, turns `DateTime` into `JsonElement`, and redeclares `Exo`/`ExoServices`.
- **Suggested fix**: Deduplicate generated types and preserve `int`/`DateTime` types where known.
- **Found by**: `economy-12`

### NIT-4 — `exo stubs` aliases `sync` (Unity client), confusing users wanting `exo extension stubs`
- **Severity**: 5 (Nit)
- **Kind**: confusing
- **Where**: `exo --help` (`stubs: Alias for sync`)
- **What**: `exo stubs` regenerates Unity client stubs, whereas `exo extension stubs <name>` generates server-to-server stubs.
- **Suggested fix**: Clarify the distinction in `exo --help` or deprecate the top-level `stubs` alias.
- **Found by**: `economy-12`
