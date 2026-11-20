# Findings — achievements

### achievements-1 — Nothing says an extension only receives events it declares itself
- **Kind**: missing
- **Where**: chapter `02_csharp_attributes` (`[ExoEvent]` note: "To listen to events in a C# extension: Implement public void OnEvent(string name, TPayload payload)"); `03_architecture` ("An event that this extension subscribed to…"). Repo lookup (a user couldn't do this): `core/lib/drivers/runtime/native_extension_runner.ex:183-188` subscribes only to `declared_events(manifest)`, i.e. the extension's *own* `[ExoEvent]` records.
- **What**: a plain `OnEvent(string name, JsonElement payload)` compiles, deploys, and never fires. No error, no log, no manifest entry. Evidence: `adventure_world.report_kill` ×3 → `achievement_progress` empty, `exo extension logs achievements` → "(no log lines recorded)". It only started firing after I added an `[ExoEvent("enemy_slain", Topic = "world:feed")] record EnemySlain(string PlayerId)` per listened event in the *listening* extension. Nothing documents that this is the subscription mechanism, or that the record's event name and topic must match the emitter's.
- **Impact**: anyone building a listener (the whole point of `OnEvent`) gets silent nothing.
- **Workaround in the sample**: one `[ExoEvent]` record per listened event (names/topics agreed with the emitting workers).
- **Suggested fix**: document "declare the event (name + Topic) to subscribe to it", and have the generator warn when `OnEvent` exists but no event is declared.

### achievements-2 — Declaring a listened event makes the listener look like its emitter
- **Kind**: confusing
- **Where**: `exo contracts`, generated `ExoforgeServices.g.cs`.
- **What**: because subscription = declaration (achievements-1), `achievements` is listed as emitting `enemy_slain`, `chest_opened`, `zone_entered`, `trade_made`, `level_published`. The Unity stub grows a duplicate `AchievementsServiceClient.OnEnemySlain` etc. (same events as `AdventureWorldServiceClient`), and `AchievementsServiceClient.SubscribeAsync(string topic = "world:feed")` defaults to the *first* event's topic, not to `achievements:feed`, which is the only topic that service really publishes. The toast must pass `"achievements:feed"` explicitly.
- **Impact**: wrong default topic; duplicate events in Studio's contract view; a reader can't tell who owns an event.
- **Workaround in the sample**: pass the topic explicitly.
- **Suggested fix**: a separate way to declare "listens to" (e.g. `[ExoListen]`), kept out of the emitted contract and the client stubs.

### achievements-3 — Only the first `OnEvent` overload is ever called, for every event
- **Kind**: bug
- **Where**: `sdk/csharp/Exoforge.Plugin.SDK/PluginHost.cs:242-257` (`FindEventHandler` returns the first method named `OnEvent`); docs show one typed handler and say nothing about several.
- **What**: I wrote `OnEvent(string, EnemySlain)`, `OnEvent(string, ChestOpened)`, … Every event was deserialised as the first overload's payload type and sent to it. The extension also receives its own `achievement_unlocked` (it is declared), and that was counted as an `enemy_slain`: 3 kills produced `achievement_progress.count = 4`. Evidence: `ach_test3:enemy_slain count 4` after 3 `report_kill`; log showed a fourth "event enemy_slain" right after each unlock.
- **Impact**: wrong counts without any error; silent double-handling.
- **Workaround in the sample**: one `OnEvent(string name, JsonElement payload)` that switches on `name` and ignores `achievement_unlocked`.
- **Suggested fix**: dispatch on event name to the matching overload, or reject several `OnEvent` methods at build time; and don't deliver an extension its own events (or document it).

### achievements-4 — Extension went `crashed` with `startup_failed` / `timeout` while idle, with no log
- **Kind**: bug (cause not found)
- **Where**: `exo extension list` after repeated pushes while events were flowing.
- **What**: `achievements crashed: {:startup_failed, %{code: "timeout", message: "the startup hook did not finish"}}`. `OnExtensionStart` is a trivial seed. `exo extension logs achievements` → "(no log lines recorded — the extension may not have run yet)". `exo extension reload achievements` fixed it. It happened with the build that had several `OnEvent` overloads and a blocking `Exo.Events.EmitAsync(...).GetAwaiter().GetResult()` inside the handler; I did not see it again after switching to one handler. I can't say which of the two, or an event arriving during the 10 s lifecycle window, caused it.
- **Impact**: a crashed extension with an empty log gives nothing to debug with.
- **Workaround in the sample**: none needed since; noted in case it recurs.
- **Suggested fix**: log the lifecycle failure reason to the extension log; check what happens to `event` frames that arrive before `lifecycle_result`.

### achievements-5 — `exo extension new --template` is documented four ways and implemented one
- **Kind**: contradiction
- **Where**: `exo extension new --help` ("--template <t>   standard (default)"); `Agents~/AGENTS.md` and skill (`persistent`, `basic`, `config`, `events`); package README (Studio list: Basic Service, Blank / Minimal, Persistent Data, Config & State, Event Producer).
- **What**: `exo extension new achievements --template events` printed "Scaffolded C# extension 'achievements' (events)", then `exo extension new achievements` over the same directory printed "(standard)" and replaced it with no prompt or refusal. The scaffolded file is the same daily-claim example whatever the name: a class called `AchievementsExtension` with `ClaimDailyReward` and an `achievements_claims` resource. I did not diff what `events` generated, since the second run replaced it.
- **Impact**: the doc'd templates can't be told apart from the CLI; a rerun destroys work.
- **Workaround in the sample**: wrote the extension by hand.
- **Suggested fix**: list the real templates in `--help`, refuse a non-empty target without `--force`.

### achievements-6 — Skill code uses an API that doesn't exist (`Exo.Events.Publish`)
- **Kind**: doc-wrong
- **Where**: `Agents~/skills/exoforge-extensions/SKILL.md` §2 (`events` template: "`Exo.Events.Publish`") and the `daily_rewards` example (`Exo.Events.Publish("daily_rewards.claimed", new { … })`).
- **What**: the SDK's XML docs have no `Publish`; the real call is `Exo.Events.EmitAsync(record)` (what the cluster docs chapters and the scaffold use). The same example also uses `[ExoService]` with `Exo.Database.Get<T>("daily_claims", key)`, while the scaffold and README use `[ExoExtension]` and `Get<T>(key)`. Extends F3/F4.
- **Impact**: an agent following the skill writes code that doesn't compile.
- **Workaround in the sample**: used `EmitAsync` and the scaffold's form.
- **Suggested fix**: make the skill match the scaffold.

### achievements-7 — `ExoTestHost` / `ExoTestContext` exist but no doc a tarball user gets mentions them
- **Kind**: missing
- **Where**: only in `Exoforge.Plugin.SDK.xml` inside the NuGet package; no mention in package README, `Agents~/**`, or the four docs chapters.
- **What**: found only by reading the XML. `ExoTestHost.Start("achievements")` returns a context with `Events.EmittedEvents` (tuples `(EventName, Payload, Topic)`, not payload objects), `Create<T>()`, and ambient `Exo.Database` — enough to test everything here. Two traps: the test project needs its own `nuget.config` copy (the extension's lives in its own folder; the `exoforge` feed is not picked up from a sibling directory), and the caller is set through `ExoTestContext.CallerPlayerId` / `CallerScopes` (settable properties, found only in the SDK source: `Exoforge.Plugin.SDK` test helpers), which no doc mentions.
- **Impact**: people write their own fakes or skip tests; the tarball gives xunit-ready test support nobody is told about.
- **Workaround in the sample**: `Exoforge/extensions/achievements.Tests` (xunit, 9 tests, all pass).
- **Suggested fix**: a "Testing extensions" section; show how to set the caller.

### achievements-8 — `[ExoAction]` with no scope is `player`, as the docs say; F6's "omitted = public" is not true for C#
- **Kind**: contradiction (re-check of F6)
- **Where**: chapter `02_csharp_attributes` (Scope default `"player"`); skill ("default or omitting scope permits public calls").
- **What**: `List()` has `[ExoAction]` with no scope and the generated manifest says `"scope": "player"`. The skill's sentence is wrong; the chapter and XML docs are right.
- **Impact**: contradicting docs on a security default.
- **Workaround in the sample**: none.
- **Suggested fix**: correct the skill.

### achievements-9 — No way to send an event to one player
- **Kind**: missing
- **Where**: chapter `02_csharp_attributes` uses `Topic = "player:*"` / `"guild:{guild_id}"` in examples without saying how a topic is bound to a caller.
- **What**: `achievement_unlocked` goes out on `achievements:feed` with `Scope = "global"`, so every subscriber receives every player's unlocks. `AchievementToast` filters by `PlayerId` on the client. The docs never say whether a per-player topic (`player:<id>`) exists, who may subscribe to it, or whether a client can subscribe to someone else's.
- **Impact**: a "private" notification is visible to everyone who subscribes; for unlocks it's harmless, for anything else it's a leak.
- **Workaround in the sample**: client-side filter.
- **Suggested fix**: document per-player topics and their access rules.

### achievements-10 — `OnEvent` is re-entered on the same thread while a host call is pending
- **Kind**: bug
- **Where**: `sdk/csharp/Exoforge.Plugin.SDK/PluginHost.cs:~780-785` (the host-call wait loop calls `DispatchEvent(line)` for any `event` frame that arrives before the `host_call_result`); chapter `02_csharp_attributes` says nothing about handlers being re-entered.
- **What**: a handler that does a host call (`Exo.Database.*`, `Exo.Events.EmitAsync`) can be called again, on the same stack, from inside that call. A C# `lock` is re-entrant, so it doesn't serialise: my first `Record` read a progress row, a nested `enemy_slain` ran inside the next host call and wrote its increment, then the outer wrote its stale count over it (a lost increment; an unlock could also double). The nested read loop also consumes frames meant for the outer call. Reproduced in `AchievementsTests.An_event_delivered_during_a_host_call_is_not_lost_or_double_counted`, which fails against the lock version and passes with the queue.
- **Impact**: any event listener with read-modify-write logic can lose or duplicate work under load; nothing warns the author, and "every change runs in one process so there's no lock needed" (README) is not true for event handlers.
- **Workaround in the sample**: `OnEvent` only enqueues; a non-reentrant drain loop (busy flag) applies events one at a time.
- **Suggested fix**: have the SDK queue events while a host call is pending and dispatch them from the main loop; failing that, document it.
