# Samples — Findings Log

Every inconsistency, contradiction, confusing point or bug found while building the samples.
One entry per finding. Workers append; nobody "fixes it quietly" outside their sample.

Format:

```
### F<n> — <one-line title>
- **Kind**: bug | contradiction | confusing | doc-wrong | missing
- **Where**: file:line (and the doc/code it disagrees with)
- **What**: what is said vs. what is true, with evidence (command + output, or code quote)
- **Impact**: who trips on it and how
- **Workaround used in samples**: none / what we did
- **Suggested fix**: one line
```

---

### F22 — CRITICAL: a contract's scope was ignored whenever the Elixir action didn't repeat it — players could run SQL
- **Kind**: bug (security) — orchestrator, found while fixing F20; **fixed** in the exoforge repo
- **Where**: `core/lib/extension.ex:52` `defaction` defaulted `scope` to `:player`; `action_dispatcher.ex` `fetch_action_scope/2` only consulted the contract when the implementation's scope was `nil`, which it never was.
- **What**: 18 standard actions whose contract says `:server`/`studio` ran with `:player`: `database.execute` and `table_columns`, `lldb.connection_config`, all 7 `file_bucket` actions, `dashboard(_view).*`, `observability.error_groups/recent_events`. Reproduced on the throwaway backend: a disposable anonymous player ran `SELECT 1` through `database.execute` with `plugin: "auth"` (the auth tables hold password hashes and tokens).
- **Fix**: `defaction` records `scope_explicit`; a defaulted scope now takes the contract's whenever the contract is stricter than `:global`. `file_bucket` raw actions are `:studio`, `upload_file` no longer accepts `path`, the HTTP upload route is staff-only and reads the multipart file itself, and downloads need a staff token, an operator-listed public bucket (`public_buckets`, default `["sdk"]`) or a `file_bucket.signed_url` link (server-only, HMAC, expiring) checked through `file_bucket.authorize_download`.
- **Note**: path dependencies don't recompile when a macro in `core` changes, so a stale `_build` keeps the old behaviour — recompile with `mix deps.compile --force` after pulling this.

### F23 — The Studio served every bucket file to anyone on :4005; in dev mode a token-less request is admin
- **Kind**: bug (security) — orchestrator; **fixed** for the file route
- **Where**: `exoforge_std_dashboard/.../router.ex` `pipeline :public_files` (empty) → `ApiController.serve_file/2`, which looked the file up internally and sent it with no access check. Separately, `ApiController.token_auth/2` treats a request with no token as `dev:admin` whenever dev tokens are allowed and `require_admin_auth` is off.
- **What**: closing `/api/files` on the HTTP extension (:4001) alone would have left the same files open on the Studio port. The Studio route now applies the same rule (public bucket, signed URL, or a staff session/token). The dev-mode "anonymous is admin" default still applies to every Studio route, by design for local work, but it means a dev cluster reachable from a network is fully open.
- **Suggested fix**: make the dev-mode default loud in the Studio header and in `exo status`, and never enable it when the endpoint binds beyond localhost.

### F20 — CRITICAL: `file_bucket.upload_file` reads any server file for any caller
- **Kind**: bug (security) — found by doodle (`samples-findings/doodle.md` doodle-5), confirmed in source by the orchestrator
- **Where**: `extensions/exoforge_std_file_bucket/lib/exoforge/std/file_bucket.ex:36` `defaction upload_file(payload) do` — no scope, so `authorize_scope(nil, _) -> :ok` (`action_dispatcher.ex:443`); `:40` takes `payload["path"]`; `resolve_binary_data/2` (`:313-322`) does `File.read(path)`; files are then served by `GET /api/files/<bucket>/<id>/<filename>` without a token, and responses include `disk_path`.
- **What**: any caller — probably even unauthenticated — can copy any file the server process can read (`.env`, SQLite DBs, tokens) into a bucket and download it. doodle reproduced it with a player token and `/etc/hosts` on the throwaway backend, then deleted the copy.
- **Impact**: every deployed cluster running `exoforge_std_file_bucket`, including any public one.
- **Suggested fix**: drop the `path` parameter from the transport-facing action (or restrict it to `:server`/internal), give `upload_file` and the other file actions explicit scopes, require auth on file GETs for private buckets, remove `disk_path` from responses.

### F21 — HTTP action responses hand every caller the server's log lines and stack traces
- **Kind**: bug (security, information leak) — orchestrator, from the menu smoke run
- **Where**: `extensions/exoforge_std_http/lib/exoforge/std/http/router.ex:330` `logs = Exoforge.ExtensionLogs.for_rid(rid)`, added to every response (`:336-364`) with no role check.
- **What**: with an anonymous **player** token, a failing `game_menu.claim_gift` returned `logs` holding two full .NET stack traces with the developer's absolute paths (`/Users/alexcs/projects/exoforge-arcade/Exoforge/extensions/wallet/src/WalletExtension.cs:line 15`) and internal messages from a *different* extension (`wallet`), because the logs follow the rid across the call chain.
- **Impact**: any player sees server internals, file layout and other services' log text; an extension that logs a secret leaks it.
- **Suggested fix**: include `logs` only for staff scopes (or a dev flag), never for player/guest callers.

### F1 — Snake client passes `name` and `playerId` swapped
- **Kind**: bug
- **Where**: `sdk/unity/sample_unity/Assets/SnakeGame/SnakeLeaderboard.cs` (`SubmitScoreAsync(session.DisplayName, session.PlayerId, score, length)`) vs generated `ExoforgeServices.g.cs:2860` (`SubmitScoreAsync(string playerId, string name, …)`)
- **What**: arguments are swapped. Masked because `exoforge_std_transport` `sanitize_payload` overwrites `player_id` with the caller's id, so the stored row is correct, but `name` receives the player id, so the `score_submitted` event carries the id as `Name` and the live leaderboard row shows an id until the next refresh.
- **Impact**: visible wrong name in the flagship sample; positional string args make this easy to repeat.
- **Workaround used in samples**: none.
- **Suggested fix**: pass named args / fix order; see F2.

### F2 — Client contract asks for a `player_id` the server always overwrites
- **Kind**: confusing
- **Where**: `snake_leaderboard.SubmitScore(string playerId, …)`; `transport.ex` `sanitize_payload`; snake `AGENTS.md` §5 ("player_id is taken from the caller's identity")
- **What**: the generated client stub requires a `playerId` parameter that is silently replaced for non-staff callers. The extension never reads `CallerPlayerId`; correctness depends on a transport-layer magic field name. Undocumented in the SDK skills / ATTRIBUTES.md.
- **Impact**: developers think they must (or can) send a player id; an extension that names the param differently (`userId`) gets no protection.
- **Suggested fix**: document the rule, or prefer `Exo.Context.CallerPlayerId` and drop the param from player-facing actions.

### F3 — Three names for the host-capability holder
- **Kind**: contradiction
- **Where**: root `AGENTS.md` + bundled skill `exoforge-extensions` use `Exo.Database`, `Exo.Events.Publish(...)`, `Exo.Context`; sample extensions use `ExoServices.Database`, `ExoServices.Events.EmitAsync(record)` (namespace `Exoforge.Plugins.Generated`); AGENTS.md also mentions `Exo.Services`.
- **What**: to verify which compile (`Exo.*`, `ExoServices.*`, or both) and whether `Events.Publish(topic, obj)` exists at all vs `EmitAsync`.
- **Impact**: an agent/developer following the skill may write code that doesn't compile.

### F4 — `Database.Get` signature differs between docs and samples
- **Kind**: contradiction
- **Where**: skill `exoforge-extensions` `Exo.Database.Get<T>("daily_claims", key)` / `Put("table", key, value)` vs sample `ExoServices.Database.Get<SnakeScoreRecord>(playerId)` / `Put(record)` (table inferred from `[ExoResource]`).
- **What**: to verify both overloads exist and which is recommended.

### F5 — Stub file name differs
- **Kind**: contradiction
- **Where**: root `AGENTS.md` says `exo extension stubs` writes `src/Generated/ExtensionServices.g.cs`; snake `AGENTS.md` and the real file say `src/Generated/PluginServices.g.cs`.

### F6 — Action scopes: docs list 4, the code has 8
- **Kind**: doc-wrong
- **Where**: skill `exoforge-extensions` ("`player`, `admin`; omitted = public"); `ATTRIBUTES.md` (`guest`, `player`, `admin`, `studio`, default `global`); code `core/lib/auth/roles.ex:65` `@action_scopes [admin, studio, player, guest, service, server, global, webhook]`.
- **What**: `service`, `server` and `webhook` are undocumented. "Omitted = public" is **false for C#**: `ExoActionAttribute.Scope` defaults to `"player"` (`Attributes.cs:81`); only an Elixir `defaction` with no scope (`nil`) passes everyone (`action_dispatcher.ex:443`). So the two runtimes have different defaults. Root AGENTS.md's "deny by default" is about *caller* scopes, and reads as if it contradicts that. Scopes without a rank (`service`, `webhook`) need an exact match, not the hierarchy (`action_dispatcher.ex:461`). `server` rejects every transport caller (`:446`). None of this is in any SDK doc, yet it is exactly what "callable by other extensions / a trusted server but not players" needs.
- **Suggested fix**: a scope table in ATTRIBUTES.md and the skill, with who can call each.

### F10 — `Scope = "guest"` appears callable by no transport caller
- **Kind**: bug (to confirm in W0)
- **Where**: `roles.ex:21` gives `guest` rank 0, so `known?` is false (`action_dispatcher.ex:459`) and an exact `"guest"` scope is required; but `@role_scopes` (`roles.ex:90`) gives the guest role `["read"]` and no role contains `"guest"`.
- **What**: a guest-scoped action is rejected for players and admins (no role's scope list contains `"guest"`). **Correction:** a literal `guest` bearer token *does* carry the `guest` scope (`auth.ex:134`), so guests themselves can call it; the hierarchy still doesn't let higher roles in. This contradicts the moduledoc's "admin > studio > player > guest" hierarchy and ATTRIBUTES.md listing `guest` as a valid scope.

### F11 — Webhook endpoint is unauthenticated; nothing says the extension must verify it
- **Kind**: missing (doc)
- **Where**: `exoforge_std_http/.../router.ex:148-202`: `/api/webhooks/:service/:action` dispatches any request with `caller_scopes: ["webhook", "global"]`. The payload carries `headers`, `raw_body` and `json`, so a signature check is possible in the extension.
- **What**: `[ExoWebhook]` docs don't say that anyone on the internet can call it, or show how to verify a signature. Two route spellings (`/api/webhooks/` and `/api/webhook/`) are both live.

### F12 — Admin holds `service` but studio doesn't, and `studio` lacks `player`
- **Kind**: confusing (to confirm in W0)
- **Where**: `roles.ex:90-96`.
- **What**: rank-based scopes (`player`) work for studio through the hierarchy, but exact-match scopes (`service`) depend on the literal scope list, so a studio account can't call a `service` action from the Studio's Action Sandbox while an admin can. To verify whether that's intended.

### F7 — Template list differs
- **Kind**: contradiction
- **Where**: root `AGENTS.md` lists 5 templates (incl. `blank`); bundled `AGENTS.md` and skill list 4.

### F8 — Unity event subscription API differs
- **Kind**: contradiction
- **Where**: `ATTRIBUTES.md` §4: `ExoforgeSDK.Events.Subscribe<TEvent>("topic", handler)`; Snake uses `client.SnakeLeaderboard().OnScoreSubmitted += …; await client.SubscribeAsync(topic)`.
- **What**: to verify whether `ExoforgeSDK.Events` exists.

### F9 — "Plugin" naming survives the extension rename
- **Kind**: confusing
- **Where**: root `AGENTS.md` says Phase 1 purged `plugins_csharp`; the directory `plugins_csharp/` still exists at repo root (`sample_plugin`, `sample_wasm`). Sample classes are `SnakeLeaderboardPlugin` in `Exoforge.Plugins.*`, package `Exoforge.Plugin.SDK`, msbuild flag `<ExoforgePlugin>`, `PluginServices.g.cs`, `PluginHost`.
- **Impact**: the samples teach the old term. New samples will use `…Extension` class names; the package/namespace names are a separate decision.

### F13 — Workspace `nuget.config` pins a content-hashed PackageCache path
- **Kind**: bug
- **Where**: `exotest/Exoforge/nuget.config`: `<add key="exoforge" value=".../Library/PackageCache/com.exoforge.sdk@9b9de2461604/Editor/Plugins/NuGet~" />`
- **What**: the hash changes whenever the package changes (the fresh 0.1.41 tarball landed at `@388f2f3b4c6d`), and the path is absolute, so the file breaks on package update and on any other machine — yet it lives in the workspace a team commits.
- **Correction (orchestrator, after reading the Editor code)**: `ExoforgeIdeProjectGenerator.cs:98-128` rewrites the workspace `nuget.config` *and one per extension folder* whenever they don't contain the current feed path, so it self-heals on Editor load. What remains broken: the files are machine-specific yet live where a team commits them (so they churn on every machine), and a CLI-only clone that hasn't opened Unity has none, so the first `exo extension build` fails to restore. The reviewer also found 14 per-project copies with the same absolute path.
- **Seen in practice (orchestrator, 0.1.41 → 0.1.42 upgrade)**: after swapping the tarball, every extension build failed to restore — the git-ignored configs still pointed at `com.exoforge.sdk@388f2f3b4c6d`, now gone — until the Editor ran again and rewrote them for `@ef2c84f07731`. A CLI-only upgrade has no such step. On top of that, F19 means the restored SDK would be the cached `0.1.0` anyway.
- **Suggested fix**: one workspace `nuget.config` with a path relative to the workspace (e.g. copy the nupkg into `Exoforge/.packages/` on load), or have `exo` write it on demand; say in the docs whether to commit it. The arcade samples git-ignore them.

### F14 — Same version number, different package
- **Kind**: bug (process)
- **Where**: `~/Downloads/com.exoforge.sdk-0.1.41.tgz` (770,828 B) vs. `dist/com.exoforge.sdk-0.1.41.tgz` built from HEAD 9d47cb3 (789,894 B).
- **What**: the source changed after 0.1.41 shipped without the bump AGENTS.md §5 requires, so two different 0.1.41s exist — the UPM stale-cache case the rule exists for.

### F15 — `exo status` reports stale build metadata
- **Where**: backend run from HEAD 9d47cb3 reports `commit_hash: fb889f1`, `build_date: 2026-11-08`, `version: 0.1.20`.
- **Kind**: confusing — whoever reads it to see "what's deployed" is misled.

### F16 — Installing the tarball doesn't create the workspace or `./exo`
- **Kind**: doc-wrong / confusing
- **Where**: package `Agents~/AGENTS.md` §1 ("If installed, execute `./exo`… fallback `dotnet Packages/com.exoforge.sdk/Editor/Cli~/exo.dll`").
- **What**: after a headless import, there's no `Exoforge/` and no `./exo`. It took `dotnet Library/PackageCache/com.exoforge.sdk@<hash>/Editor/Cli~/exo.dll init --dir Exoforge` and then `… agents install`. The first fallback path (`Packages/com.exoforge.sdk/…`) only exists for an embedded package, not a tarball. `init --dir Exoforge` also drops a second `exo`/`exo.cmd` inside `Exoforge/`. (Possibly the Editor's setup wizard covers this interactively — to confirm.)

### F17 — The in-repo sample can't prove the tarball path
- **Kind**: confusing (test gap)
- **Where**: `sdk/unity/sample_unity` sits under the repo's `Directory.Build.targets` and `NuGet.config`, which supply the SDK "from source when the SDK is beside it" (root AGENTS.md).
- **What**: its extensions build even if the packaged NuGet path is broken. `just test-unity-package` checks compile + auth only, not building or deploying an extension from the tarball. The arcade samples live outside the repo for this reason.

### F18 — Half the tarball is macOS AppleDouble files
- **Kind**: bug
- **Where**: `Justfile` `pack-unity`: `tar -czf … -C dist package` on macOS without `COPYFILE_DISABLE=1`.
- **What**: `dist/com.exoforge.sdk-0.1.41.tgz` has 266 entries, 133 of them `._*` (Python `tarfile`; macOS `tar -t` hides them). They land in `Library/PackageCache/…`, and `exo agents install` copies `._SKILL.md` into `.agents/`, `.claude/` and `.gemini/` of the user's project, where they get committed.
- **Suggested fix**: `COPYFILE_DISABLE=1 tar …` (or `--no-mac-metadata`), plus a check in `pack-unity` that fails on `._` entries.

### F19 — The extension SDK NuGet is always `0.1.0`, so upgrades never reach extension builds
- **Kind**: bug
- **Where**: `ExoScaffolder.cs:262` `SdkPackageVersion = "0.1.0"`; the 0.1.41 tarball ships `Editor/Plugins/NuGet~/Exoforge.Plugin.SDK.0.1.0.nupkg`; global cache `~/.nuget/packages/exoforge.plugin.sdk/0.1.0/`.
- **What**: NuGet treats a version as immutable. Once any tarball's `0.1.0` is in the global cache, every later tarball's SDK is ignored: a developer who upgrades the Unity package keeps building extensions against the first SDK they ever restored, with no error. AGENTS.md §5's bump rule covers `package.json` and `ExoforgePackageVersion.cs` but not this.
- **Suggested fix**: version the nupkg with the package version and scaffold `<PackageReference … Version="<package version>">`.

### Audit (agy) — see `.agents/samples-findings/audit.md`
F1–F12 re-checked against the current code (F3 partly resolved: `Exo` and `ExoServices` both compile, but `Exo.Services` and `Exo.Events.Publish` don't exist; F8 resolved in the served docs but still wrong in the repo's `ATTRIBUTES.md`). New: audit-1…audit-10 — the bundled skill's example doesn't compile (`Events.Publish`); both served `[ExoWebhook]` examples fail to compile (wrong payload API, analyzer `EXO004`); the served blueprints omit their DTOs and pass a dynamic topic as a record field; `Put(record)` throws when `PrimaryKey` is snake_case (as in the resources skill); CLI messages send tarball users to `just`; `--json` is ignored on `extension new/build/push`; the documented `exo status --json` fields don't exist; "zero scene wiring" vs "drop the prefab"; `ExoTestHost` and the in-memory fakes are shipped but undocumented. Two players on one machine resolve to the same account by default (shared `PlayerPrefs`, no per-process namespace).

## F24 — a service account's explicit player_id was overwritten by its own (fixed 9d45444)
transport.ex sanitize_payload only let admin/studio name a target, so `adventure_world.report_kill`
from the game server's service token credited the service account. The dungeon smoke didn't assert,
so it printed kills 0 and still passed. Also: `exo user token --help` prints the group usage.

## F25 — open risks from the SDK fix review (agy, approved)
- PluginHost.cs BufferedFrames / BufferedHostCallResults / _stdin are unsynchronized: an action that runs
  host calls concurrently (Task.WhenAll) may interleave reads. Sequential await is safe. Pre-existing shape;
  either serialize CallHost with a lock or document "host calls are sequential".
- Runtime/IsExternalInit.cs is now public: a Unity project with another package that also exports a
  public IsExternalInit gets CS0433. Watch for it; an opt-out define would cover it.

## F26 — F13 fix nit (agy): the Unity refresh is keyed by a machine-wide EditorPrefs value
A second project upgraded to the same SDK version skips the reload-time refresh; the CLI/Studio build
path (PublishNative) still heals it. A per-project key (e.g. include Application.dataPath) would close it.

## F27 — the IsExternalInit button can be unreachable when it is needed
With the SDK's copy internal, a game assembly with a record fails CS0518. If the project has never compiled
(fresh clone, CI, batchmode) Unity does not run editor code while scripts have errors, so the Studio button and
the wizard step cannot be used; only an editor that already loaded a previous good domain shows them. A CLI
command (`exo unity records [--asmdef <dir>]`) over ExoIsExternalInit would cover headless/fresh projects.
Also ExoforgeIsExternalInit.PresentPath is project-wide while presence matters per assembly.

## F28 — two processes sharing PlayerPrefs can revoke a refresh family (agy, wt/tokens)
The refresh gate is per ExoClient; two Unity processes on one machine (MPPM, two editors) share ExoTokenStore.
B may send a refresh token A already rotated -> server revokes the family. Same root as CONF-10.

## F29 — a 401 from the HTTP auth plug carries no rid
`unauthenticated` / `token_expired` replies (router.ex auth plug) have the nested error but no `rid`; every
other error reply has one. Also: a clean Unity compile on 0.1.48 did not migrate an old project to .feed by
itself (phase3.md); the first CLI or Studio build does.

## F30 — one Exoforge.Plugin.SDK.Tests run hung (not reproduced)
After merging wt/instances+tooling+migrate, one `dotnet test sdk/csharp/Exoforge.Plugin.SDK.Tests` run's testhost
stayed alive 10 min (normally 2-4 s); 7 reruns with --blame-hang-timeout 45s all passed in 2-4 s. Suspect: a test
path where the new host-call reader thread (wt/hostcalls) blocks on the real stdin when the runner inherits a
terminal. Next time: run with --blame-hang-timeout and keep the hang dump.

## F31 — Postgres adapter opens a 10-connection pool per extension, exhausting max_connections
- **Repro**: Start backend with `DATABASE_URL="postgres://postgres:postgres@127.0.0.1:5432/exoforge_prod"` (default Postgres `max_connections=100`) and push all 7 arcade extensions (`for e in wallet daily_rewards brainrot_market adventure_world level_share achievements game_menu; do ./exo extension push "$e"; done`).
- **Error**: `wallet` installs, then `daily_rewards`, `brainrot_market`, `adventure_world`, `level_share`, `achievements` fail migration with `DBConnection.ConnectionError` (`reason: :queue_timeout`, 4000ms) and backend logs `FATAL 53300 (too_many_connections) sorry, too many clients already`; `game_menu` times out after 10s.
- **Where**: `extensions/exoforge_std_database/lib/exoforge/std/database/adapters/postgres.ex:286` (`pool_size: Map.get(config, :pool_size, 10)` per `{database, schema}` pool, so 10+ system/game extensions exceed 100 connections).

## F32 — Postgres adapter KV operations hardcode `(id, data)` instead of schema-migrated columns
- **Repro**: With `wallet` deployed on Postgres, run `bash /Users/alexcs/projects/exoforge-arcade/tools/smoke.sh` (or `POST /api/wallet/get_balance`).
- **Error**: `Database operation failed on table 'wallet_balances': {:postgres_error, "column \"data\" does not exist"}`.
- **Where**: `extensions/exoforge_std_database/lib/exoforge/std/database/adapters/postgres.ex:157,169` (`kv_put`/`kv_get`/`kv_all`/`kv_delete` query `data` and `(id, data, updated_at)` unconditionally, unlike `sqlite.ex` which inspects `real_table_info` for resource-migrated tables).

## F33 — `observability` and `extension_logs` fail on Postgres (32-bit `integer` timestamps, ambiguous `n`, SQLite-only `column_exists?`)
- **Repro**: Boot backend with `DATABASE_URL="postgres://postgres:postgres@127.0.0.1:5432/exoforge_prod"` and a fresh `EXOFORGE_DATA_DIR`.
- **Error**:
  - `(DBConnection.EncodeError) Postgrex expected an integer in -2147483648..2147483647, got 1795010740821` (and `1792368000000`).
  - `{:postgres_error, "column reference \"n\" is ambiguous"}` on rollup upsert.
  - `{:postgres_error, "column \"at\" of relation \"events\" already exists"}` (and `day`, `origin`, `rid`, `status`) on boot.
- **Where**:
  - `extensions/exoforge_std_observability/lib/exoforge/std/observability/events.ex:532,547,555` (`integer` instead of `bigint` for ms timestamps), `:467,732` (`DO UPDATE SET n = n + excluded.n`), `:553-562` (`column_exists?` check before `ALTER TABLE`).
  - `core/lib/extension_logs.ex:388` (`timestamp integer` instead of `bigint`).

## F34 — Postgres resource KV path passes string `id` to integer primary-key columns
- **Repro**: Deploy `daily_rewards` on a Postgres-backed backend (`./exo extension push daily_rewards` or `tools/smoke.sh economy`). `DailyRewardsExtension.OnExtensionStart()` seeds `daily_reward_table` (`day integer PRIMARY KEY`) via KV `Put`.
- **Error**: `Postgrex expected an integer in -2147483648..2147483647, got "1". Please make sure the value you are passing matches the definition in your table or in your query or convert the value accordingly.`
- **Where**: `extensions/exoforge_std_database/lib/exoforge/std/database/adapters/postgres.ex:174,176,228,239` (`id = to_string(command[:id])` / `Map.put(data, pk_col, id)` passes string `id` into `INSERT`/`SELECT`/`DELETE` without coercing by the column's `data_type`).

## F35 — Postgres resource KV `:put` passes ISO-8601 timestamp strings to `timestamp` columns
- **Repro**: Run `tools/smoke.sh menu` (or `wallet.credit` / `achievements` `unlocks` write) against a Postgres-backed backend.
- **Error**: `Postgrex expected %DateTime{} or %NaiveDateTime{}, got "2026-11-18T14:40:28.756442Z". Please make sure the value you are passing matches the definition in your table or in your query or convert the value accordingly.`
- **Where**: `extensions/exoforge_std_database/lib/exoforge/std/database/adapters/postgres.ex:173-224` (`execute_resource_kv(:put, ...)` binds JSON-decoded ISO-8601 `DateTime` strings directly to Postgrex without parsing them to `%DateTime{}`/`%NaiveDateTime{}` for `timestamp*` columns).
