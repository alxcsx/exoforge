# menu — findings

Slice: `game_menu`, MainMenu scene, README §0 walkthrough. Package 0.1.41 (`@388f2f3b4c6d`), tarball only.

### menu-1 — `exo extension new --help` offers one template and a repo recipe; the docs list four
- **Kind**: contradiction
- **Where**: `exo extension new --help` vs package `Agents~/skills/exoforge-extensions/SKILL.md` §2 and `Agents~/AGENTS.md` §4
- **What**: help says `--template <t>   standard (default)` and "run `just pack-sdk` to fill the local feed from a checkout". The skill lists `persistent`, `basic`, `config`, `events`. `exo extension new game_menu --template persistent` is accepted and prints "(persistent)"; a second `exo extension new game_menu` on the existing folder succeeds ("(standard)") with no "already exists" error.
- **Impact**: a tarball user has no checkout and no `just`; they can't tell which templates exist, and re-running `new` doesn't warn.
- **Workaround in the sample**: wrote the extension by hand.
- **Suggested fix**: print the real template list in help, drop the `just` sentence, refuse to scaffold over an existing folder.

### menu-2 — The skill's code sample doesn't match the scaffold or the SDK XML docs
- **Kind**: contradiction
- **Where**: `exoforge-extensions/SKILL.md` §3 vs the scaffold (`GameMenuExtension.cs` from `exo extension new`) and `Exoforge.Plugin.SDK.xml`
- **What**: the skill uses `[ExoService]`, `Exo.Database.Get<T>("daily_claims", key)` / `Put("daily_claims", key, v)` and `Exo.Events.Publish(...)`; the scaffold and package README use `[ExoExtension]` with `Get<T>(key)` / `Put(record)` and `Resources = [typeof(...)]`. The skill says "omitting scope permits public calls"; the SDK XML for `ExoActionAttribute.Scope` says "Defaults to \"player\" (requires player or higher authentication)". (Extends F3/F4/F6; I did not test an unscoped action, so which is true is unverified.) The skill's own `[ExoResource("t", PrimaryKey = "player_id")]` string form differs from the scaffold's `nameof(PlayerId)`.
- **Impact**: copying the skill's example gives code that mixes two styles; the scope default decides whether an unmarked action is public.
- **Workaround in the sample**: followed the scaffold; wrote `Scope = "player"` explicitly on every action.
- **Suggested fix**: one example, generated from the scaffold; state the scope default once.

### menu-3 — Calling another extension needs `[ExoDependency]`, which no tarball doc mentions
- **Kind**: missing
- **Where**: skill and package README (no occurrence of `ExoDependency` in `README.md`, `Agents~/**`, `Samples~/**`); runtime error below
- **What**: calling `wallet.credit` from `game_menu` first failed with `{:invalid_operation, "Service 'wallet' is not declared in this extension's dependencies. Add 'wallet' to your extension dependencies and regenerate stubs."}`. Fix: `[ExoDependency("wallet")]` on the class, `exo extension stubs game_menu`, redeploy; the manifest then lists `"dependencies": ["wallet"]`.
- **Impact**: the first extension→extension call fails at runtime, not build time, and the message doesn't name the attribute.
- **Workaround in the sample**: added the attribute.
- **Suggested fix**: document extension→extension calls (attribute, `exo extension stubs`, `ExoServices.<Service>`); name the attribute in the error.

### menu-4 — A failed extension→extension call returns an empty object instead of throwing
- **Kind**: bug
- **Where**: generated `Generated/PluginServices.g.cs` (`WalletServiceClient.CreditAsync` → `IActionDispatcher.CallActionAsync<T>`)
- **What**: with `wallet.credit(amount: 0)` rejected (`invalid_amount`), `await ExoServices.Wallet.CreditAsync(...)` returned a non-null `WalletBalance` with `PlayerId == null`, `Coins == 0`. The reply is `{"error":"{:invalid_amount, ...}"}` (seen with `HostBridge.CallActionRaw`) and the typed deserializer reads it as an object with every field default. First version of `ClaimGift` therefore "succeeded", recorded the claim and returned 0 coins.
- **Impact**: any extension that calls another and trusts the result silently loses errors — in a game, a failed payment looks like success.
- **Workaround in the sample**: `if (balance?.PlayerId == null) throw new ExoActionException("wallet_rejected", …)`, with a comment.
- **Suggested fix**: `CallActionAsync<T>` throws `ExoActionException` on an `error` reply.

### menu-5 — Errors are Elixir tuples in a string, in the CLI and over HTTP
- **Kind**: confusing
- **Where**: `exo call game_menu save_settings …` → `[http_error] {:invalid_volume, "Volume must be between 0 and 100."} (rid r_…)`; HTTP: `{"error":"{:invalid_volume, \"Volume…\"}","status":"error","rid":"r_…"}`
- **What**: the `ExoActionException` code and message arrive as one string in Erlang term syntax; there is no separate `code` field. (Whether the Unity `ExoActionException.Code` is split out: not checked headlessly.)
- **Impact**: curl and script users have to regex the code out.
- **Workaround in the sample**: smoke script prints the raw reply.
- **Suggested fix**: `{"error":{"code":…,"message":…}}`.

### menu-6 — Error replies to a player carry server stack traces and absolute paths
- **Kind**: bug (information disclosure)
- **Where**: any failing action called with a player token, `logs` array of the HTTP reply
- **What**: `{"logs":["[ERROR] …ExoActionException: … at Exoforge.Extensions.GameMenuExtension.SaveSettings(...) in /Users/alexcs/projects/exoforge-arcade/Exoforge/extensions/game_menu/src/GameMenuExtension.cs:line 32 …"]}`, including the other extension's frames on a nested failure (`wallet/src/WalletExtension.cs:line 15`).
- **Impact**: players see developer machine paths and internal call chains; also useful for the walkthrough, which relies on the same data in Studio.
- **Workaround in the sample**: none.
- **Suggested fix**: return `logs` only to staff callers.

### menu-7 — A non-readable resource answers `:resource_not_found` to a player
- **Kind**: confusing
- **Where**: `POST /api/resource_store/list {"table":"menu_gifts"}` and `{"resource":"menu_gifts"}` with a player token
- **What**: `menu_news` (`AllowPlayerRead = true`) lists fine with `{"resource":"menu_news"}`. For `menu_gifts` (not readable) the reply is `:resource_not_found`, not a forbidden error; the field is `resource`, and `table` gives the same `:resource_not_found`.
- **Impact**: someone who forgot `AllowPlayerRead` is told the table doesn't exist.
- **Workaround in the sample**: none (it is what hides `menu_gifts` from players; intended).
- **Suggested fix**: `forbidden` for existing resources; document `resource_store.list`'s `resource` param and `AllowPlayerRead` in the skill.

### menu-8 — The generated client for `resource_store.list` is awkward and untyped
- **Kind**: confusing
- **Where**: `Assets/Exoforge/Generated/ExoforgeServices.g.cs` `ResourceStoreServiceClient.ListAsync(JsonElement offset, JsonElement sort, JsonElement filter, JsonElement search, JsonElement limit, string resource, …)`
- **What**: five optional parameters are required `JsonElement`s in the convenience overload; only the request-object overload is usable (`new ResourceStoreListRequest { Resource = "menu_news" }`); `Rows` is a `JsonElement`, so the game parses rows by hand.
- **Impact**: reading a player-readable resource, the feature the README advertises, needs hand-written JSON parsing.
- **Workaround in the sample**: `MenuBridge.ReadNewsAsync` walks `Rows.EnumerateArray()`.
- **Suggested fix**: generate a typed `ListAsync<T>` per `AllowPlayerRead` resource.

### menu-9 — `ExoTestHost` works from the tarball, but nothing in the tarball documents it
- **Kind**: missing
- **Where**: `Exoforge.Plugin.SDK.xml` documents `ExoTestHost`/`ExoTestContext`/`InMemory*`; `README.md`, `Agents~/**`, `Samples~/**` don't mention them
- **What**: a test project with a `ProjectReference` to `game_menu.csproj`, `Microsoft.NET.Test.Sdk` and xunit builds and runs (8 tests pass). `ExoTestHost.Start("game_menu")` returns an `ExoTestContext` with settable `CallerPlayerId` and `CallerScopes`; found by reflection (the XML doesn't describe the properties). Stubs for other extensions are overridden through the static `ExoServices.Wallet = fake`, which is process-wide, so test classes that do it can't run in parallel.
- **Impact**: a user writing tests has to discover the API from the DLL.
- **Workaround in the sample**: `game_menu.Tests`.
- **Suggested fix**: a "Testing extensions" section in the skill with this example.

### menu-10 — `game_menu` startup timed out once after a wallet redeploy
- **Kind**: bug (unconfirmed)
- **Where**: backend, `exo call game_menu claim_gift` at 13:52
- **What**: `{:extension_starting, :game_menu}`, then `{:extension_crashed, {:startup_failed, %{code: "timeout", message: "the startup hook did not finish"}}}`. `OnExtensionStart` only does three database reads and writes. `exo extension logs game_menu` showed nothing for the crash. `exo extension reload game_menu` fixed it. Other workers were deploying at the time.
- **Impact**: an extension that hangs at start gives no log line about why.
- **Workaround in the sample**: `exo extension reload`.
- **Suggested fix**: log the startup attempt and its duration; say what the timeout is.
