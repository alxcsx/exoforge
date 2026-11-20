# dungeon — findings

### dungeon-1 — `ExoAction.Scope` default: SDK XML says "player", the skill says "omitted = public"
- **Kind**: contradiction
- **Where**: `Exoforge.Plugin.SDK.xml` (`ExoActionAttribute.Scope`: "Defaults to \"player\"") vs package `Agents~/skills/exoforge-extensions/SKILL.md` §3 ("default or omitting scope permits public calls"). Known F6 covers the scope list; this is the default.
- **What**: the two sources disagree about what a bare `[ExoAction]` allows. Not verified on the cluster.
- **Impact**: someone leaving the scope off a trusted action believes it is open or closed, depending on which doc they read.
- **Workaround in the sample**: every action states its scope.
- **Suggested fix**: one sentence in both places, from the dispatcher's real behaviour.

### dungeon-2 — `Scope = "service"` is valid and compiles, but no package doc names it
- **Kind**: missing
- **Where**: `grep -rn service` over the package README, `Agents~/**` finds no scope list; the generator accepted `Scope = "service"` and wrote it to `manifest.json`.
- **What**: the only way to learn the value exists is the repo (F6). Once deployed, `exo call` with the admin token succeeds (admin holds `service`), and a player gets `{"error":"forbidden_scope","caller_scopes":["player","read","write"],"required_scope":"service"}`.
- **Impact**: the README's "trusted game server reports kills" pattern can't be built from the docs.
- **Workaround in the sample**: used `"service"`, tested with a player token (`tools/smoke/dungeon.sh`).
- **Suggested fix**: a scope table in the skill and the package README.

### dungeon-3 — `service` actions get no client stub (good), but nothing says so
- **Kind**: confusing
- **Where**: `ExoforgeServices.g.cs` after `exo sync` has `AdventureWorldServiceClient.GetProgressAsync` only; `report_*` (scope `service`) are absent.
- **What**: the generator hides non-player actions. Not documented. A game server therefore has no typed way to call them: it needs `ExoClient.SendActionAsync<T>("adventure_world", "report_kill", payload)` with a hand-built dictionary.
- **Impact**: the trusted-server side has no documented, typed path in Unity.
- **Workaround in the sample**: `MockGameServer` uses `new ExoClient { HttpBaseUri = … }`, `UseToken`, `SendActionAsync`.
- **Suggested fix**: document the pattern, or generate an opt-in server-side client.

### dungeon-4 — Issuing a `service` token is undocumented, and I did not do it
- **Kind**: missing
- **Where**: `auth.issue_token(user_id, scopes, player_id)` is listed with scope `admin` in `exo contracts`; no package doc mentions it, its lifetime, or that a game server needs one.
- **What**: my attempt `exo call auth issue_token --data '{"user_id":"mock-game-server","scopes":["service"]}'` was denied by this session's permission classifier, so lifetime and revocation are **unverified**. `MockGameServer` reads `Exoforge/mock-game-server.token`; the file does not exist yet.
- **Impact**: until someone issues it, the mock reports nothing and `tools/smoke/dungeon.sh` skips the server half.
- **Workaround in the sample**: the Editor script warns and disables itself when the file is missing.
- **Suggested fix**: document the call and TTL; consider a `exo token issue --scope service` command. Orchestrator: add `Exoforge/mock-game-server.token` to `.gitignore`.

### dungeon-5 — `exo extension new --help` lists one template; docs list four; the scaffold ignores the choice
- **Kind**: contradiction
- **Where**: `exo extension new --help`: "`--template <t>  standard (default)`"; skill/AGENTS.md: `persistent|basic|config|events`.
- **What**: `--template events` was accepted and produced the same single-action greeting extension. Also `new` says "run `just pack-sdk` to fill the local feed from a checkout", which a tarball user has no way to do (the feed is already in the package, via the absolute path in `nuget.config`, see F13).
- **Impact**: templates documented in three places do not exist.
- **Workaround in the sample**: wrote the extension by hand.
- **Suggested fix**: make help and docs agree, drop the `just` hint from `new`.

### dungeon-6 — Scaffold targets net10.0; docs say .NET 9+
- **Kind**: confusing
- **Where**: scaffolded `src/adventure_world.csproj` `<TargetFramework>net10.0</TargetFramework>` vs AGENTS.md/README ".NET 9+/`>= 9.0`".
- **What**: a machine with only the .NET 9 SDK would fail to build. This machine has 10.
- **Suggested fix**: state the real minimum.

### dungeon-7 — Scaffolded `.gitignore` leaves `bin/` and `obj/` untracked-but-visible
- **Kind**: confusing
- **Where**: `Exoforge/extensions/adventure_world/.gitignore` contains `/.exoforge/`, `/.buildcount`, `/manifest.json` only; `src/obj` and `src/bin` exist after a build.
- **Impact**: `git status` fills with build output unless the workspace ignores it.
- **Suggested fix**: add `bin/` and `obj/`.

### dungeon-8 — Test projects can use the SDK fakes, but `ExoTestHost` is not parallel-safe and is undocumented
- **Kind**: confusing
- **Where**: `Exoforge.Plugin.SDK.xml` (`ExoTestHost.Start`: "Starts an isolated in-memory test context"). Reachable from the tarball: the nupkg ships `InMemoryDatabase`, `InMemoryEventDispatcher`, `ExoTestHost`.
- **What**: with two test classes, xunit's default parallelism made one fail with `ExoDatabaseException: Database operation failed on table 'adventurer_progress': Database put operation failed` (the ambient context belongs to the other class's host). Adding `[assembly: CollectionBehavior(DisableTestParallelization = true)]` fixed it. "Isolated" is only true per process. No docs mention testing at all; the package skill has no tests section.
- **Impact**: flaky first tests for everybody who writes a second test class.
- **Workaround in the sample**: `AssemblyInfo.cs` disables parallelization.
- **Suggested fix**: document the rule, or make the ambient context `AsyncLocal`.

### dungeon-9 — `OnEvent` from another native extension: works, declared by an `[ExoEvent]` record, not by `dependencies`
- **Kind**: confusing (answer, not a bug)
- **Where**: `achievements/manifest.json` has `"dependencies": []` and lists `enemy_slain`/`chest_opened`/`zone_entered` under its own `events` with topic `world:feed`.
- **What**: end to end, `exo call adventure_world report_kill` x3 for a throwaway player created the `slime_slayer` unlock row in `unlocks`, with no client connected. The SDK XML says only "Marks an event emitted or handled by the plugin"; nothing says that the same attribute declares a subscription, or that a matching name+topic is how the host routes it.
- **Impact**: the listener side is learned by imitation. `ExoDependency` is not needed for events.
- **Suggested fix**: document "to listen, declare the event record with the same name and topic, and add `OnEvent`".

### dungeon-10 — `exo call` rows and routes: HTTP is `POST /api/<service>/<action>`, found in no package doc
- **Kind**: missing
- **Where**: package docs, SDK XML. The route was copied from another worker's smoke script; `strings` over `Exoforge.Client.dll` finds only `/api/files/`.
- **What**: needed for `curl` demos and for knowing the shape of `forbidden_scope` (`caller_scopes`, `required_scope`, `rid`).
- **Suggested fix**: one "calling over HTTP" section in the connection skill.

### dungeon-11 — Dynamic topics and who may subscribe: not verified
- **Kind**: missing
- **What**: `SubscribeAsync("world:feed")` is generated with a default topic and the Unity bridge uses it; I did not test whether a player may subscribe to an arbitrary topic or another player's. No package doc covers it. I did not read the server.

### dungeon-12 — Test rows created through `exo call` with the admin token
- **Kind**: confusing
- **What**: the admin token holds `service`, so `exo call adventure_world report_kill` "works" even though the action is service-only. A developer verifying scope with `exo call` sees a pass; the refusal only shows with a player token (`dungeon.sh` does that). Matches F12.
- **Suggested fix**: `exo call --as player` or print the caller scopes.
