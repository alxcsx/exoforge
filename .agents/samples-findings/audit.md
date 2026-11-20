# Exoforge Arcade — Audit Findings (`audit`)

Scope: Tarball-only audit of `com.exoforge.sdk@388f2f3b4c6d` (`README.md`, `Agents~/AGENTS.md`, `Agents~/skills/*/SKILL.md`, `Samples~/BasicUsage/*`), served cluster docs (`docs.export_docs` from `http://localhost:4001`), CLI (`exo.dll`), and `Exoforge.Plugin.SDK.0.1.0.nupkg` against the Exoforge source (read-only).

---

## 1. Re-check of `SAMPLES_FINDINGS.md` (F1–F12)

- **F1 — Snake client passes `name` and `playerId` swapped**: **confirmed**. `sdk/unity/sample_unity/Assets/SnakeGame/SnakeLeaderboard.cs:141-142` calls `SubmitScoreAsync(session.DisplayName, session.PlayerId, score, length)` against `SubmitScoreAsync(string playerId, string name, long score, long snakeLength)` (`ExoforgeServices.g.cs:2860`).
- **F2 — Client contract asks for a `player_id` the server always overwrites**: **confirmed**. `extensions/exoforge_std_transport/lib/exoforge/std/transport.ex:64-78` (`sanitize_payload/2`) overwrites `"player_id"` with the authenticated caller's `player_id` for non-staff callers.
- **F3 — Three names for the host-capability holder**: **changed / partly resolved**. Both `Exo` and `ExoServices` compile (`ExoforgePluginGenerator.cs:47,92` emits both in `Exoforge.Plugin.SDK`, and `ExoCodeGenerator.cs:977,1057` emits both in `PluginServices.g.cs`). `Exo.Services` does **not** exist (`Exo` exposes `Context`, `Database`, `Logger`, `Events`, `Actions`, `Reset()`). `Exo.Events.Publish(...)` does **not** exist (`IEventDispatcher` only has `EmitAsync`; see `audit-1`).
- **F4 — `Database.Get` signature differs between docs and samples**: **confirmed (with runtime trap)**. Both `IDatabase.Get<T>(table, key)` (`Interfaces.cs:28`) and `DatabaseExtensions.Get<T>(id)` (`DatabaseExtensions.cs:74`) exist. However, `DatabaseExtensions.Put<T>(entity)` fails at runtime when `PrimaryKey` is snake_case (see `audit-5`).
- **F5 — Stub file name differs**: **confirmed**. Repo root `AGENTS.md:257` says `src/Generated/ExtensionServices.g.cs`, whereas `Exoforge.CLI/Program.cs:1713`, `ExoDeployer.cs:374`, and served `01_quickstart.md:113` all write `src/Generated/PluginServices.g.cs`.
- **F6 — Action scopes: docs list 4, code has 8**: **confirmed**. `core/lib/auth/roles.ex:65` defines `@action_scopes [@admin, @studio, @player, @guest, @service, "server", "global", "webhook"]`. `Agents~/skills/exoforge-extensions/SKILL.md:77` lists only `player`, `admin`, and falsely claims omitted scope is public (it defaults to `"player"`, `Attributes.cs:81`). Served `02_csharp_attributes.md` (`served_docs.md:268`) lists 4 (`guest`, `player`, `studio`, `admin`) and omits `service`, `server`, `global`, `webhook`.
- **F7 — Template list differs**: **confirmed**. `ExoScaffolder.cs:22` defines `{"standard", "basic", "blank", "persistent", "config", "events"}`. Package `README.md:22` lists 5 (`Basic Service`, `Blank / Minimal`, `Persistent Data`, `Config & State`, `Event Producer`); `Agents~/AGENTS.md:61` and `exoforge-extensions/SKILL.md:27-30` list 4 (`persistent`, `basic`, `config`, `events`); `exo extension new --help` lists only `standard (default)`.
- **F8 — Unity event subscription API differs**: **resolved in served docs / still in repo `ATTRIBUTES.md`**. Served `02_csharp_attributes.md` (`served_docs.md:325,353-354`) now shows `await ExoServices.<Service>.SubscribeAsync("topic")` + `On<Event>`, matching `ExoCodeGenerator.cs:1565`. `sdk/csharp/Exoforge.Plugin.SDK/ATTRIBUTES.md:148` (not in tarball) still has the non-existent `ExoforgeSDK.Events.Subscribe<TEvent>`.
- **F9 — "Plugin" naming survives the extension rename**: **confirmed**. `plugins_csharp/` exists at repo root, and the tarball ships `Exoforge.Plugin.SDK.0.1.0.nupkg`, `Exoforge.Plugin.Generator.dll`, `PluginServices.g.cs`, `IPluginContext`, `PluginHost`, and wire frame `"plugin": "<name>"` (`served_docs.md:532`).
- **F10 — `Scope = "guest"` appears callable by no transport caller**: **confirmed**. `roles.ex:21` gives `"guest"` rank `0`, `action_dispatcher.ex:459` falls back to exact string match when `rank <= 0`, and `@role_scopes` (`roles.ex:90-96`) never includes `"guest"` in any role (`"guest" => ["read"]`). Any `[ExoAction(Scope = "guest")]` is rejected for all transport callers.
- **F11 — Webhook endpoint is unauthenticated; nothing says the extension must verify it**: **confirmed**. `exoforge_std_http/lib/exoforge/std/http/router.ex:148-202` dispatches `/api/webhooks/:service/:action` and `/api/webhook/:service/:action` unauthenticated with `caller_scopes: ["webhook", "global"]`; neither `Attributes.cs` nor served `02_csharp_attributes.md` (`served_docs.md:467-480`) warns that the endpoint is public and must verify signatures.
- **F12 — Admin holds `service` but studio doesn't, and `studio` lacks `player`**: **confirmed**. `roles.ex:90-96` assigns `"admin" => ["admin", "service", "studio", "player", "write", "read"]` and `"studio" => ["studio", "write", "read"]`.

---

## 2. New Findings

### audit-1 — `exoforge-extensions` skill example fails to compile and misstates default `Scope`
- **Kind**: doc-wrong
- **Where**: `Agents~/skills/exoforge-extensions/SKILL.md:65,77,80` vs `Exoforge.Plugin.SDK` (`Interfaces.cs:55`, `Attributes.cs:81`)
- **What**: Line 65 calls `Exo.Events.Publish("daily_rewards.claimed", new { playerId, amount = rewardAmount });`. Compiling against `Exoforge.Plugin.SDK.0.1.0.nupkg` fails with `error CS1061: 'IEventDispatcher' does not contain a definition for 'Publish'`. Line 77 also states "default or omitting scope permits public calls", whereas `ExoActionAttribute.Scope` defaults to `"player"` (`Attributes.cs:81`).
- **Impact**: Every developer or agent following the bundled skill writes code that does not compile and misunderstands action visibility.
- **Workaround in the sample**: Use `await Exo.Events.EmitAsync("daily_rewards.claimed", ...)` or a typed `[ExoEvent]` record, and set `Scope = "global"` explicitly for public actions.
- **Suggested fix**: Replace `Publish` with `await Exo.Events.EmitAsync(...)` and document `Scope = "player"` as the default.

### audit-2 — Served `[ExoWebhook]` blueprint in `04_use_cases_and_patterns.md` does not compile
- **Kind**: doc-wrong
- **Where**: Cluster served docs `04_use_cases_and_patterns.md` (`docs.export_docs` lines 941-960) vs `Exoforge.Plugin.SDK/Attributes.cs:457-485`
- **What**: `HandleStripeWebhook(WebhookPayload payload)` accesses `payload.EventName`, `payload.Data["client_reference_id"]`, and returns `WebhookResult.Success()`. Compiling against `Exoforge.Plugin.SDK.0.1.0.nupkg` fails with:
  - `error CS1061: 'WebhookPayload' does not contain a definition for 'EventName'`
  - `error CS1061: 'WebhookPayload' does not contain a definition for 'Data'`
  - `error CS0117: 'WebhookResult' does not contain a definition for 'Success'`
  (`WebhookPayload` has `Body`, `RawBody`, `Json`, `Headers`, `Method`, `Query`; `WebhookResult` has `new WebhookResult(...)`.)
- **Impact**: Developers copying the Stripe webhook blueprint get immediate compile errors.
- **Workaround in the sample**: Read `payload.Json` / `payload.RawBody` / `payload.Headers` and return `new WebhookResult(200)`.
- **Suggested fix**: Update `04_use_cases_and_patterns.md` to use `payload.Json`, `payload.RawBody`, and `new WebhookResult()`.

### audit-3 — Served `[ExoWebhook]` snippet in `02_csharp_attributes.md` fails Roslyn analyzer `EXO004`
- **Kind**: doc-wrong
- **Where**: Cluster served docs `02_csharp_attributes.md` (`docs.export_docs` lines 474-478) vs `ExoforgePluginGenerator.cs:115-121`
- **What**: The example declares `public async Task HandleStripeWebhook(StripeWebhookPayload payload)`. The source generator rejects any `[ExoWebhook]` method whose single parameter is not `WebhookPayload` (`EXO004: Webhook method '...' marked with [ExoWebhook] must accept exactly one parameter of type WebhookPayload`).
- **Impact**: Following the attribute reference produces a build error.
- **Workaround in the sample**: Always take `WebhookPayload payload`.
- **Suggested fix**: Change the parameter type in `02_csharp_attributes.md` to `WebhookPayload`.

### audit-4 — Served blueprint examples omit DTOs, reference non-existent `PlayerDataRecord`, and misuse `Topic`
- **Kind**: doc-wrong
- **Where**: Cluster served docs `04_use_cases_and_patterns.md` (`docs.export_docs` lines 608-680, 766-876)
- **What**:
  1. Auction House, World Boss, and Guild examples fail to compile because their `*Request`/`*Response` DTOs are omitted and `PlayerDataRecord` (`ReferencesType = typeof(PlayerDataRecord)`) does not exist in `Exoforge.Plugin.SDK`.
  2. Guild example calls `await Exo.Events.EmitAsync(new GuildActivityEvent($"guild:{guild.Id}", ...))`, passing the dynamic topic as a record field instead of the second parameter of `EmitAsync(payload, topic)` (`EventDispatcherExtensions.cs:18`).
- **Impact**: Copy-pasting the blueprints fails to compile; dynamic guild topic routing silently falls back to `DefaultTopic` (`"guild:*"`).
- **Workaround in the sample**: Define all DTOs locally and pass dynamic topics as the second argument to `EmitAsync(payload, topic)`.
- **Suggested fix**: Include the DTOs or mark snippets partial, remove `typeof(PlayerDataRecord)`, and pass `$"guild:{guild.Id}"` as the `topic` argument.

### audit-5 — `DatabaseExtensions.Put(record)` throws at runtime when `PrimaryKey` is snake_case
- **Kind**: bug
- **Where**: `sdk/csharp/Exoforge.Plugin.SDK/DatabaseExtensions.cs:256` vs `[ExoResource(..., PrimaryKey = "player_id")]`
- **What**: `EntityMetadata<T>` looks up `KeyProp = type.GetProperty(resAttr.PrimaryKey, BindingFlags.Public | BindingFlags.Instance | BindingFlags.IgnoreCase)`. When a record declares `[ExoResource("leaderboard_entries", PrimaryKey = "player_id")]` with C# property `PlayerId` (as in `Agents~/skills/exoforge-resources/SKILL.md:20-26` and `SnakeScoreRecord`), `GetProperty("player_id")` returns `null`. Calling `db.Put(new LeaderboardEntry("p1", 5))` throws `InvalidOperationException: Cannot determine primary key for type 'LeaderboardEntry'`.
- **Impact**: Developers using `Put(entity)` with snake_case `PrimaryKey` crash at runtime unless they also add `[ExoColumn(PrimaryKey = true)]` or call `Put(key, entity)`.
- **Workaround in the sample**: Always annotate the key property with `[ExoColumn(PrimaryKey = true)]` or use `Put(key, entity)`.
- **Suggested fix**: Normalize `resAttr.PrimaryKey` (e.g. compare `ExoNaming.ToSnakeCase(prop.Name)`) in `EntityMetadata<T>`.

### audit-6 — CLI help and error messages direct tarball users to repo-only `just` commands
- **Kind**: doc-wrong
- **Where**: `Exoforge.CLI/Program.cs:1328,1725,1977` (observed via `./exo extension new --help` and `./exo status`)
- **What**:
  - `./exo extension new --help` prints: ``run `just pack-sdk` to fill the local feed from a checkout.``
  - `./exo status` / `./exo connect` on unreachable cluster prints: ``Could not reach the cluster. Is it running (`just dev`), and is the environment's ws_url correct?``
  - `exo extension stubs` missing-contract error mentions ``Start the cluster (`just dev`)``.
  A tarball user has neither the Exoforge repo nor `just`.
- **Impact**: Confuses tarball users when offline or scaffolding extensions.
- **Workaround in the sample**: Ignore `just` references and use the local backend / package `NuGet~/` feed.
- **Suggested fix**: Remove repo-only `just` instructions from the shipped CLI strings.

### audit-7 — `--json` flag is documented on `exo extension new/build/push` but ignored
- **Kind**: doc-wrong
- **Where**: `Agents~/AGENTS.md:20`, `Agents~/skills/exoforge-extensions/SKILL.md:23,87,92,100` vs `Exoforge.CLI/Program.cs:1319,1363,1384`
- **What**: `Agents~/AGENTS.md:14` states "Always append `--json` to commands when programmatic parsing is required. JSON responses are written directly to stdout." The docs pass `--json` to `exo extension new`, `build`, and `push`, but those handlers never check `cli.Json` and emit human-readable progress text.
- **Impact**: Agents/scripts parsing stdout as JSON fail on `extension new/build/push`.
- **Workaround in the sample**: Do not parse `exo extension new/build/push` stdout as JSON.
- **Suggested fix**: Implement `--json` output in `HandleExtensionNew`, `HandleExtensionBuild`, and `HandleExtensionPushAsync`, or remove `--json` from their examples.

### audit-8 — `exoforge-connection` skill lists non-existent `exo status --json` fields
- **Kind**: doc-wrong
- **Where**: `Agents~/skills/exoforge-connection/SKILL.md:51-55` vs live `./exo status --json` output
- **What**: The skill states `exo status --json` returns `reachable`, `latency_ms`, `version`, and `active_extensions`. Actual output from `./exo status --json` is `{"system": {"arch": "...", "build_date": "...", "commit_hash": "...", "extensions_count": 23, "version": "0.1.20", ...}}` — none of `reachable`, `latency_ms`, or `active_extensions` exist.
- **Impact**: Agents or scripts checking `reachable` or `active_extensions` fail.
- **Workaround in the sample**: Check process exit code and `system.extensions_count`.
- **Suggested fix**: Update `exoforge-connection/SKILL.md` to match the actual `{"system": {...}}` schema.

### audit-9 — Scene setup contradiction: "Zero Scene Wiring" vs `Exoforge.prefab` required
- **Kind**: contradiction
- **Where**: Package `README.md:17,117` and `Samples~/BasicUsage/README.md:9` vs served `01_quickstart.md:20` (`ExoforgeSDK.cs:18-19`)
- **What**: `README.md:17` instructs: "Ensure the active scene contains an `ExoforgeManager` (`Exoforge ▸ Add Exoforge to Scene`)" and `README.md:117` says "Dropping `Exoforge.prefab` into your first scene ensures background reconnects...". Meanwhile, served `01_quickstart.md:20` states "**Zero Scene Wiring**: You do not need to manually instantiate prefabs in your scene. `ExoforgeManager` initializes automatically on demand" (confirmed in `ExoforgeSDK.cs:18-19`).
- **Impact**: Developers think they must wire `Exoforge.prefab` in every scene.
- **Workaround in the sample**: Rely on on-demand `ExoforgeManager` initialization (or `SamplePlayer`).
- **Suggested fix**: Align `README.md` and `Samples~/BasicUsage/README.md` with the zero-wiring behavior.

### audit-10 — `ExoTestHost` and `InMemory*` test fakes ship in the NuGet package but are undocumented
- **Kind**: missing
- **Where**: `Editor/Plugins/NuGet~/Exoforge.Plugin.SDK.0.1.0.nupkg` (`Exoforge.Plugin.SDK.xml`) vs `README.md`, `Agents~/**`, `Samples~/**`, and served docs
- **What**: `ExoTestHost`, `ExoTestContext`, `InMemoryDatabase`, `InMemoryEventDispatcher`, `InMemoryLogger`, and `InMemoryActionDispatcher` are all present and public in `Exoforge.Plugin.SDK.0.1.0.nupkg` (reachable by a tarball user), but zero package or cluster docs mention them.
- **Impact**: Tarball users don't know they can unit-test extensions locally without a running cluster.
- **Workaround in the sample**: Use `ExoTestContext.Create<T>()` / `InMemory*` directly from the NuGet package in `<name>.Tests`.
- **Suggested fix**: Add a short testing section to `01_quickstart.md` and `exoforge-extensions/SKILL.md`.

---

## 3. Question: How do two players run on one machine with device-keyed login, and what does the developer have to do?

### How it currently works (`Runtime/ExoDeviceId.cs`, `Runtime/ExoTokenStore.cs`, `Runtime/ExoforgeAuth.cs`)
1. `ExoDeviceId.Get()` reads `PlayerPrefs.GetString("Exoforge.DeviceId")`, falling back to `ExoDeviceId.HardwareId` (a SHA-256-derived hash of `SystemInfo.deviceUniqueIdentifier`) and caching it in `s_cached` and `PlayerPrefs`.
2. `ExoTokenStore` stores `"Exoforge.Token"`, `"Exoforge.PlayerId"`, `"Exoforge.Scopes"`, `"Exoforge.PlayerName"`, and `"Exoforge.DeviceId.Attached"` in the same `PlayerPrefs`.
3. `ExoforgeSDK.Auth.LoginAnonymously()` sends `auth.anonymous` with `player_id = activeDeviceId` and caches the returned token in `ExoTokenStore`.
4. **There is no per-process, CLI-arg, environment-variable, or Multiplayer Play Mode (MPPM) namespacing** in `ExoDeviceId` or `ExoTokenStore`. Two instances of the same Unity build (or Editor + Build) on one machine share the exact same OS `PlayerPrefs` store, so **by default both instances resolve to the same `ExoDeviceId` and sign into the same player account**.

### What the developer has to do
- **Interactive (Unity Editor + 1 Build, or sequential testing)**:
  Use **Exoforge ▸ Studio ▸ Settings ▸ Mask Device ID (New Account)** (or **Impersonate Specific Device ID**, or menu **Exoforge ▸ Sessions ▸ Reset Anonymous Player Session**) in the Editor *after* the other instance has already signed in and cached its in-memory `ExoSession` (or mask before launching the second instance if only one reads `PlayerPrefs` at a time). Note that `Mask()` / `Impersonate()` calls `ExoTokenStore.ClearDeviceSession()`, which overwrites the shared `PlayerPrefs` keys.
- **Side-by-side / automated two-player testing on one machine**:
  The developer must explicitly override the identity in their own startup code before calling `LoginAnonymously()`:
  1. Call `ExoDeviceId.Impersonate(id)` from a custom CLI argument or environment variable (note: simultaneous cold launches still race on shared `PlayerPrefs` until `s_cached` is populated in each process); **or**
  2. Bypass `ExoforgeSDK.Auth.LoginAnonymously()` for the second player by calling `auth.anonymous` / `auth.register` directly and passing the token to `ExoforgeSDK.Client.UseToken(token)` / `AuthenticateAsync(token)`.
