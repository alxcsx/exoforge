# Findings — economy slice (`wallet`, `daily_rewards`, `brainrot_market`)

Source lookups a tarball user couldn't do are marked **(repo lookup)**.

### economy-1 — A failed extension→extension call is silently turned into `null`; a debit that fails lets the trade through
- **Kind**: bug
- **Where**: generated `PluginServices.g.cs` (`WalletServiceClient.DebitAsync` → `_dispatcher.CallActionAsync<WalletBalance>`), `HostBridge.CallAction*`; **(repo lookup)** `core/lib/drivers/runtime/native_extension_runner.ex:678-687` (`{:error, reason} -> %{error: inspect(reason)}`).
- **What**: `wallet.debit` threw `insufficient_funds` (visible only in the wallet's log), yet the typed stub returned `null` in `brainrot_market`, which carried on: `buy_shares SKBD 100000` returned `{"coins":12000000,...}` for a player with 860 coins. `HostBridge.CallActionRaw` shows the real reply: `{"error":"{:insufficient_funds, \"Needs 120 coins, has 100.\"}"}` (an Elixir `inspect` string, not a code + message). `game_menu`'s author hit the same thing ("the typed stub turns an error reply into an empty WalletBalance instead of throwing").
- **Impact**: anyone calling `wallet`-style services from an extension and ignoring the null gets free money. Nothing in the docs says a call can fail without throwing.
- **Workaround in the sample**: a `WalletCall` seam around `HostBridge.CallActionRaw`; a reply that is null or contains `"error"` becomes an `ExoActionException` whose code is parsed out of `{:code, ...}`.
- **Suggested fix**: throw `ExoActionException(code, message)` from `CallAction*` and typed stubs; return the error as structured `{code, message}`.

### economy-2 — Extension→extension calls skip every scope check, so a `Scope` cannot be what makes `credit`/`debit` "extensions only"; `Scope = "server"` does not stop `exo call`
- **Kind**: contradiction
- **Where**: **(repo lookup)** `native_extension_runner.ex:678` (`ActionDispatcher.dispatch_internal`), `action_dispatcher.ex` `authorize_scope(_declared, :internal) -> :ok`; `roles.ex:60-63` ("`:server` means never reachable from a transport").
- **What**: calls between extensions carry no scope and no caller identity at all (internal), so any declared scope works for them; the scope only matters for transport callers. Tested on `wallet.credit/debit` with `Scope = "server"`: `daily_rewards`/`brainrot_market` can call it; a player over HTTP gets `forbidden_scope` (verified); but `exo call wallet credit ...` as the admin **succeeds** (coins credited), against `roles.ex`'s "never reachable from a transport". (Could not check the admin over plain HTTP: the call was blocked in this environment.) With `Scope = "service"` the admin also passes (F12), and so would the dungeon's `service` token: a leaked game-server token could print coins.
- **Impact**: the question "how do I make an action callable by extensions but not players" has no documented answer; `server` is the closest and still lets admin/CLI through.
- **Workaround in the sample**: `Scope = "server"` on `credit`/`debit`; `player_id` is a parameter because the caller's identity is not forwarded to the callee (that is also why the generated stubs take `PlayerId`).
- **Suggested fix**: document the scope table incl. internal calls; make `server` really reject staff over `exo call`/Studio, or add an `internal` scope.

### economy-3 — Calling another extension needs a declared dependency that only typed stubs add
- **Kind**: confusing
- **Where**: **(repo lookup)** `native_extension_runner.ex:672` (`service_not_declared`), `Manifest.allows_service?`.
- **What**: using `Exo.Wallet` (generated stubs) puts `"dependencies": ["wallet"]` in the manifest. Calling through `HostBridge.CallActionRaw`/`Exo.Actions.CallAction` without stubs returns `{"error":"service_not_declared"}` and nothing else, until `[ExoDependency("wallet")]` is added on the class. No doc mentions `[ExoDependency]` outside the XML docs.
- **Impact**: a confusing silent failure (see economy-1) for anyone not using stubs.
- **Workaround in the sample**: `[ExoDependency("wallet")]` on both callers.
- **Suggested fix**: document the dependency rule; make the error say which attribute to add.

### economy-4 — `[ExoWebhook]` handlers never receive their `WebhookPayload`
- **Kind**: bug
- **Where**: docs `04_use_cases_and_patterns.md:371` (`HandleStripeWebhook(WebhookPayload payload)`), generator `EXO004` (must have exactly one `WebhookPayload` parameter); **(repo lookup)** `PluginHost.cs:610-620` (arguments bind by *parameter name* from top-level payload keys) and `router.ex:176-184` (the payload is `{body, raw_body, json, headers, method, query}` at top level).
- **What**: no key is named `payload`/`request`, so the parameter is `null` (checked with a log line: `webhook null=True`), and the handler dies with `NullReferenceException` (`{:null_reference,...}` over HTTP). The compiler then refuses any other signature, so a webhook cannot be written as documented.
- **Impact**: the headline webhook feature is unusable as documented; headers and raw body (needed for signature checks) are unreachable.
- **Workaround in the sample**: a normal `[ExoAction(Scope = "webhook")] StorefrontPurchase(string rawBody, Dictionary<string,string> headers, JsonElement json)`, which the same route (`/api/webhooks/<service>/<action>`) dispatches. The handler verifies `x-storefront-signature: sha256=<hmac of the raw body>` against a Studio-editable secret and returns `WebhookResult(401, ...)` (HTTP 401 honoured, checked with `curl -i`).
- **Suggested fix**: bind a `WebhookPayload` parameter to the whole payload.

### economy-5 — `Name` is not settable on `[ExoCron]`/`[ExoWebhook]`, though the XML docs list it
- **Kind**: doc-wrong
- **Where**: `Exoforge.Plugin.SDK.xml` (`ExoCronAttribute.Name`, `ExoWebhookAttribute.Name`).
- **What**: `[ExoCron("* * * * *", Name = "tick_prices")]` → `error CS0617: 'Name' is not a valid named attribute argument`; the name is the second constructor argument (`[ExoCron("* * * * *", "tick_prices")]`, `[ExoWebhook("storefront_purchase")]`).
- **Suggested fix**: make them settable, or fix the docs/XML.

### economy-6 — A `[ExoCron]` method is also a player-callable action
- **Kind**: bug
- **Where**: `POST /api/brainrot_market/tick_prices` with a player token → `{"data":{},"status":"ok"}`.
- **What**: the cron method is registered as an action with the default (`player`) scope, so any player can trigger the price tick. `ExoCron` has no `Scope`. Prices *do* tick on schedule (`* * * * *`, first tick at the next minute boundary; `RunOnStartup` defaults to false). `exo call brainrot_market tick_prices` as admin is the way to "run it now" from a terminal; running it from Studio's UI was not tried.
- **Impact**: any cron job that changes shared state is open to players.
- **Workaround in the sample**: the method refuses callers that have a player id and no `admin` scope (`forbidden`).
- **Suggested fix**: cron methods get scope `server`.

### economy-7 — Reading an `AllowPlayerRead` resource from the client is only in an XML doc comment
- **Kind**: missing
- **Where**: `ExoResourceAttribute.AllowPlayerRead` XML doc ("through `resource_store.list` and `resource_store.get`").
- **What**: works: `ExoServices.ResourceStore.ListAsync(new ResourceStoreListRequest { Resource = "meme_stocks" })`; rows come back as `JsonElement` (snake_case keys). A resource without the flag gives `forbidden_scope`. The whole table is readable, not the caller's rows. The generated all-`JsonElement` overload `ListAsync(offset, sort, filter, search, limit, resource)` is awkward; the request-object overload is the usable one. No sample, skill or README says this.
- **Suggested fix**: a short "client reads resources" section in the README and the resources skill.

### economy-8 — The HTTP routes a `curl` demo needs are not in the package docs
- **Kind**: missing
- **Where**: package README/skills.
- **What**: anonymous login is `POST /api/auth/anonymous {"player_id","device_id"}` → `data.token`; any action is `POST /api/<service>/<action>` with `Authorization: Bearer`; webhooks are `POST /api/webhooks/<service>/<action>` (and `/api/webhook/...`, F11). Guesses such as `/api/actions/...` give `not_found`. Found by trying; the Runtime assembly has no readable route strings.
- **Workaround in the sample**: `tools/smoke/economy.sh`.

### economy-9 — Errors from `exo call`/HTTP are Elixir tuples, and `--json` does not apply to them or to `extension new`
- **Kind**: confusing
- **Where**: `exo call wallet debit ...` → `[http_error] {:insufficient_funds, "Needs 500 coins, has 50."} (rid r_...)`; `exo extension new wallet --json` prints human text.
- **What**: `ExoActionException("insufficient_funds", msg)` reaches the CLI as an inspected Elixir tuple; the SDK's Unity client turns it into `Code`/`Message` but the CLI and raw HTTP callers don't. The "`--json` always" rule in AGENTS.md doesn't hold for failures.
- **Suggested fix**: print `{"error":{"code","message","rid"}}` under `--json`.

### economy-10 — Right after `exo extension push`, calls fail with `extension_starting`; a quick second push crashed the extension
- **Kind**: bug
- **Where**: `exo extension push wallet` twice within seconds, then `exo call`.
- **What**: `{:extension_starting, :wallet}` for several seconds (`Verified: … loaded` is printed already), then `{:extension_crashed, {:startup_failed, %{code: "timeout", message: "the startup hook did not finish"}}}` although `wallet` has no startup hook. `exo extension reload wallet` fixed it.
- **Suggested fix**: `push` waits until the extension answers; explain the crash.

### economy-11 — Template targets `net10.0`; the docs say .NET 9+
- **Kind**: contradiction
- **Where**: scaffolded `*.csproj` (`<TargetFramework>net10.0</TargetFramework>`) vs. AGENTS.md/skill ("standard .NET (9.0+)"), README ("`>= 9.0`").
- **What**: only .NET 8 and 10 were on this machine (so a 9-only machine was not tried). Likely fails there.
- **Suggested fix**: say 10, or template `net9.0`.

### economy-12 — Generated extension stubs: wrong command in the header, duplicate types, `exo stubs` means something else
- **Kind**: confusing
- **Where**: `src/Generated/PluginServices.g.cs` header ("Regenerate with `exo plugin stubs <name>`"); `exo --help` ("stubs: Alias for sync").
- **What**: the real command is `exo extension stubs <name> --services a,b`; `exo stubs` regenerates the *Unity* client. The file contains the same type twice (`WalletWalletBalance` and `WalletBalance`), turns `int` into `long` and `DateTime` into `JsonElement`, and defines its own `Exoforge.Plugin.SDK.Exo`/`ExoServices` statics. Re-running it is required after the callee's contract changes (not mentioned in the skill).
- **Suggested fix**: fix the header; dedupe; document `exo extension stubs`.

### economy-13 — Unity client stub: one default topic per service; list payloads are `JsonElement`; response types have global names
- **Kind**: confusing
- **Where**: `ExoforgeServices.g.cs` (`BrainrotMarketServiceClient.SubscribeAsync(string topic = "market:trades")`).
- **What**: the service has two topics (`market:trades`, `market:ticker`) but the stub's default is just the first; `prices_ticked` only arrives after `SubscribeAsync("market:ticker")` with the topic spelled out. Lists inside records (`Holdings`, `Quotes`) are `JsonElement`. Records are emitted as bare global classes (`Trade`, `Portfolio`, `DailyStatus`), so two extensions with a `Trade` record collide in `Exoforge.Client`.
- **Suggested fix**: one `Subscribe<Topic>()` per topic; typed lists; prefix response types with the service.

### economy-14 — Tests: `ExoTestHost` is reachable from the tarball, but the test project needs the same pinned feed path
- **Kind**: confusing (info)
- **Where**: `Exoforge/extensions/<name>.Tests/nuget.config`.
- **What**: works: `ExoTestHost.Start("wallet")`, `host.CallerPlayerId`, `host.Create<T>()`, `host.Database`, `host.Events.HasEmitted`; 31 tests pass with xunit from nuget.org. The test project needs its own `nuget.config` with the same absolute, content-hashed `Library/PackageCache/com.exoforge.sdk@<hash>/…/NuGet~` path (F13). The test host has no clock and no way to fake `HostBridge` calls, so the samples add static `Clock`/`WalletCall` seams. `InMemoryActionDispatcher` does not model economy-1 (a failed call there throws or returns what the test registers).
- **Suggested fix**: an `ExoTestContext.Clock`, and a way to make `HostBridge` calls go through `Actions`.

### economy-15 — F3/F4 (`Exo.*` vs `ExoServices.*`, `Database.Get` forms): both compile
- **Kind**: confusing (re-check of known findings)
- **What**: `Exo.Database.Get<T>(key)`, `Exo.Database.Get<T>("table", key)`, `Exo.Events.EmitAsync(record)`, `Exo.Context`, `Exo.Wallet` and `ExoServices.*` all compile. `Exo.Events.Publish(...)` (skill) does not exist (`EmitAsync`). The skill's `[ExoService("daily_rewards", Category=…)]`/`Scope = "player"` example and README's `[ExoExtension(...)]` both compile; `[ExoAction]` without a scope is `player`, not public (generator `?? "player"`, XML doc "Defaults to \"player\""), contradicting the skill's "omitting scope permits public calls".

### economy-16 — `AllowPlayerRead` exposes every row, which is wrong for per-player tables
- **Kind**: confusing
- **Where**: `wallet_balances` had `AllowPlayerRead = true` (reviewer defect).
- **What**: the flag gates the whole resource, so any player could list all balances; the XML doc says so, but it is easy to set on a per-player table. Removed; clients use `get_balance`.
- **Suggested fix**: a per-row filter (`PlayerId == caller`) for player-readable resources.
