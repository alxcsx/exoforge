# Exoforge Architecture & Plan (`plan.md`)

> **Status**: Kernel, 10 standard plugins, C# Client SDK, C# Plugin SDK, C# Management Engine (`exo`
> CLI), Unity SDK (`com.exoforge.sdk`), Producer Studio, clustering and Kubernetes manifests are
> **complete** — **266 Elixir + 81 C# = 347 tests passing**, plus a live E2E vertical slice of 6 tests
> against a running server.
> **Benchmark**: 0.07 ms fanout to 50 event subscribers over `:pg`.

Completed work is not kept here. It is in `git log`, which is the record that does not drift; this
file is the invariants and what is next. Milestone identifiers (**M1**…**M30**) are historical and are
referenced from `Agents.MD`, `DX.md` and commit messages, so they stay in the table below and nowhere
else.

---

## 1. Ground Truth & Invariants

**The Rule**: everything above the kernel is a plugin.
**The Exception**: the kernel is not — `PluginRegistry`, `ActionDispatcher`, `EventDispatcher`,
`WorkerRegistry`, `PluginSupervisor`, `PluginBootstrapper`.

- **Service atoms, never module names.** Plugins depend on `:database`, `:auth`, `:player_data`.
  Swapping PostgreSQL for SQLite changes no consumer.
- **Pure C# outside Mix.** Game developers have no Elixir toolchain. Workspace init, scaffolding,
  codegen and deploy are pure C# (`netstandard2.1`).
- **The Unity package is the unit of distribution.** It ships into projects with no Exoforge checkout
  anywhere near them, so it must work exactly as it is shipped.
- **The instance is the unit of deployment.** A developer has Unity, the package and their own
  plugins; the kernel and the standard plugins run somewhere else and are reached over the wire.
  Anything that assumes a checkout — a `_build` path, a `just` recipe, a sibling directory — is a
  tool for this repository's own team, not for a user.
- **No engine SDK owns engine-agnostic code.** The C# client and the plugin tooling belong to the
  dotnet side; each engine ships them as a compiled assembly. Adding an engine adds a bucket that
  ships those libraries, not one that reimplements them.
- **A project names no other project's path.** Where a build input comes from is a property of the
  environment, decided by the hooks in `Directory.Build.targets`, not by a reference in a `.csproj`.

```
database ──▶ auth ──▶ player_data
               │
               ├──▶ http (:4001)
               ├──▶ ws   (:4000)
database ──────┴──▶ dashboard (:4005)
plugin_manager ───▶ (independent root)
```

---

## 2. Completed Milestones

| M | Delivered |
| :--- | :--- |
| **M1–M6** | Kernel (`PluginRegistry` ETS, `ActionDispatcher`, `EventDispatcher`), Bandit HTTP/WS ingress, SQLite DB, Auth, PlayerData |
| **M7–M13** | Producer Studio (LiveView, `:4005`), Horde delta-CRDT virtual actors, `:pg` event fanout, cluster benchmark, Kubernetes manifests |
| **M14–M17** | `Cmd+K` palette, actor passivation, typed resources (`[ExoResource]`), dynamic action forms, C# client generation |
| **M18** | Zero compiler warnings, WebSocket `AuthenticateAsync`, green E2E slice |
| **M19** | `exoforge_std_plugin_manager`: hot plugin upload, runtime reload, manifest export |
| **M20** | C# Management engine + `exo` CLI — `init`, `plugin new\|build\|push\|dev\|reload\|logs\|stubs\|list\|remove`, `sync`, `status`. `push` verifies the deployed version; `dev` redeploys on save; `logs` reads back plugin output |
| **M21** | Unity SDK `com.exoforge.sdk` — one game-facing entry point (`ExoforgeSDK.Auth`/`.Client`/`.ConnectAsync`), device-keyed two-stage anonymous sign-in, prefab created on demand, `Samples~/BasicUsage` |
| **M22** | Control Center window — cluster ping, environment switcher, event monitor, action sandbox, plugin scaffold/build/deploy/logs, typed codegen. Split across `ExoforgeControlCenter*.cs` partials; `just pack-unity` builds the tarball |
| **M23** | SQLite local mode — `Exoforge.Std.Database.Adapters.Sqlite` + `:sqlite` driver, no PostgreSQL daemon needed |
| **M24** | Plugin Tooling DX ([`DX.md`](DX.md)) — 21 fixes across plugin creation, upload and management |
| **M25** | LiveOps *(withdrawn)* — time windows, schedule timeline and calendar view removed; game rules belong in the game, not the platform |
| **M26** | `Exoforge.Plugin.Generator` — a Roslyn source generator replaces the out-of-process `ManifestGen` tool. The manifest, the entry point, the action/event dispatch table and the contract interfaces come from the plugin's own compile, so every build shares one pipeline, the host no longer reflects over a generated plugin's methods, and a C# plugin declares services on a class or on a contract interface in its own assembly |
| **M27** | Self-Contained Unity Package — no symlink leaves the package, no path is resolved by walking out of it, and nothing in package code names this repository's layout |
| **M28** | SDK Runtime Hardening — four correctness bugs and six DX problems on the game-facing path, each with a test that fails when the fix is reverted |
| **M29** | Engine-Agnostic C# Core — the C# client and plugin tooling moved out of the Unity package, which now contains only Unity-specific code and ships the libraries as binaries |
| **M30** | Duplication and Build-Step Cleanup — one code generator, one manifest path, no second implementation of anything |
| **M31** | Dev Hooks and the Plugin Feed — `Directory.Build.targets` supplies a plugin's SDK, generator and manifest plumbing from a single opt-in, the Unity package stages its own libraries by building, and `Exoforge.Plugin.SDK` packs into a feed a plugin outside this repository builds against |

---

## 3. Standing Principles

Following the Ponytail doctrine — deletion over addition, standard library over dependencies,
shortest working path.

- **One code generator.** Pure C# `ExoCodeGenerator` is the single source for client bindings; the
  old Mix task is gone.
- **The host boundary is a pipe.** JSON frames over stdin and stdout, no per-plugin bindings, so a
  runtime that is not a process is a runner rather than a rewrite.
- **A plugin ships IL, not a runtime.** Framework-dependent .NET assemblies, one process per plugin.
  *(Landed in M32; the switch is Phase 1 below.)*
  The runtime lives in the image, paid for once; the plugin pays for its own code. This is what
  UGS Cloud Code does (`.ccm` = a zip of the DLL, its `deps.json`, dependencies and PDBs), and it is
  why reflection works and none of the plugin authoring path needs generated help to serialise.
- **No heavy ORMs.** Raw SQL or light `:postgrex`; actor state is a serialized blob, not a relational
  object graph.
- **Zero-config containers.** Local defaults are baked into `docker-compose.yml`, the K8s manifests
  and the `Justfile`, so `just compose-up` needs no environment setup.

---

## 4. Next — M32: Framework-Dependent Plugins and Usage Metering

**The decision.** Plugins ship as framework-dependent .NET assemblies and run on a runtime in the
image. AOT is dropped. Measured on the sample plugin, spawned in batches and left idle:

| | on disk | N=1 Pss | N=8 total | marginal per plugin |
| :--- | ---: | ---: | ---: | ---: |
| NativeAOT | 2.8 MB | 3.2 MB | 10 MB | ~1 MB |
| framework-dependent | 144 KB | 12.5 MB | 57 MB | ~6.4 MB |

Dropping AOT buys 20× less disk and costs 6× more RAM per plugin. Disk is a container image layer
and effectively free; RAM is what runs out, so this trade is only sound because **usage is billable**
— which is the same position Unity is in, and the reason they can ship IL and not care.

What it buys, beyond the number: **reflection works**, so records, enums, `[Inject]`, nested and
anonymous shapes all serialise without generated help. Most of the machinery in M31 exists only to
work around AOT, and this deletes it rather than fixing it.

**Phase 1 — the switch.** *Done.* The deployment defaults live in
`Exoforge.Plugin.SDK/build/Exoforge.Plugin.SDK.targets`, which is imported both by NuGet for a
consumer and by this repository for its own plugins, so a plugin built here and one built against
the package deploy identically: `PublishAot=false`, `SelfContained=false`, `PublishSingleFile=true`
(the deploy protocol uploads one binary), `PublishReadyToRun=true` (Unity recommends R2R for cold
start; measured on the sample at 28.7 ms against 31.0 ms median to the first action, for 55 KB),
`RollForward=LatestMajor`.

Every one of those is **conditional** on being unset, which is not a style choice: unconditional,
the import overwrote what a plugin set for itself, so `PublishAot=true` became `false`, the build
succeeded and the guard could never fire. A default that overrides hides the intent.

Two errors guard the deployment, both verified by setting the property and watching them fire:
`EXOFORGE001` for `PublishAot=true`, `EXOFORGE002` for `PublishTrimmed=true`. Trimming and AOT both
remove the property metadata reflection needs, so a record serialises as an empty object — silently,
and only once deployed.

The image carries the SDK in the builder and the runtime in the runner. **Built and booted**: the
release reaches `Discovered 10 plugin manifests`, `All 10 plugins loaded`, `System online in 47ms`.
Six defects stood between the image and that line, none of them visible by reading, all of them in
`git log` under `fix(docker)` - and the phase 1 image change, written without a container runtime to
build against, did not work until one existed.

**Not in Phase 1, and deliberately:** the two-pass build stays. It exists only so the generated JSON
context is visible to the System.Text.Json generator on a second compile, and the context is what
Phase 2 deletes — so the two go together, and collapsing the build now would leave a context that is
written and never compiled.

**Phase 2 — delete the workarounds.** The generator stops emitting the JSON context, the per-enum
converters and the `[DynamicDependency]`. `FindJsonContext` stays: a hand-written context is still
honoured, it is just no longer required. `AotHint` becomes an ordinary serialization error, and the
notes about the `JsonObject` route and `IlcTrimMetadata` go, because their premise is gone —
reflection handles both. The manifest, dispatch table, contracts and client stubs are untouched.

**Phase 3 — make the runtime dependency safe.** The builder stage takes the .NET SDK, the runner
stage the runtime. `RollForward=LatestMajor` plus the plugin's own `runtimeconfig.json` states the
requirement. **Ship PDBs**, as Unity does: the crash story is currently strong on isolation (a
`kill -9` is caught and the plugin restarts) and weak on diagnosis, and an AOT binary is the worst
of the two for a stack trace.

**Phase 4 — usage metering.** Process-per-plugin is what makes this cheap: the OS already reports
per-plugin CPU and RSS, so nothing needs instrumenting inside the runtime. **This also settles the
shared-host question** — metering and fault isolation both want a process per plugin, and a shared
host would make usage attribution guesswork. Meter in the runner, which holds the port's pid and
sees every call: invocations by action, wall and CPU time, peak RSS, bytes, events, host calls,
restarts and uptime. On by default, including self-hosted: it is cheap, and it is the operator's own
data in the operator's own database.

**The call shape has landed.** `Exoforge.Metering` holds per-plugin counters in ETS - invocations
and errors by action, wall time and wire bytes, events, host calls, starts, restarts, uptime - fed
by the native runner, which is where the port and its byte counts are visible. `snapshot/0` and
`snapshot/1` stamp them with the instance's `title_id` and `studio_id` (`config :exoforge, :instance`,
env-overridable), so the rollup is already a `GROUP BY`. Both this table and the log buffer are owned
by `Exoforge.TableOwner`, not by the first caller: a runner restart must not take a plugin's own
usage with it.

CPU time and peak RSS are sampled from the plugin's OS process every five seconds (`os_pid/1`
existed for exactly this); `VmHWM` is a high-water mark, so a peak between samples is not lost.

**Persistence and the CLI landed.** `exoforge_std_metering` flushes deltas from the kernel's
counters into its own isolated database every minute - and on graceful shutdown - as append-only
rows stamped with title and studio. The `:metering` service's `usage` action rolls them up per
plugin and action, flushing first so the answer is current, and `exo plugin usage [name]` renders
it. A hard crash loses at most a minute of counters.

The Studio's generic extension view now renders the `usage` action (the plugin declares a
`dashboard_view`) and `exo status` reports the instance's `title_id`/`studio_id`, so "which title is
this?" is answered by the target rather than by an id on the wire. Deliberately not built: a
bespoke Studio table, deploy records carrying the ids, and egress - the first two have no consumer
yet, and egress needs a destination and an idempotency key (the rows are deltas, so a retry would
double-bill) before it can be correct.

**Meter shape, never content** — counts, durations, bytes, CPU, RSS, plugin and action *names*.
Never payloads, never player or user identifiers. That is what makes "on by default" defensible, and
it belongs in the invariants, not in a config comment. Action names are the one grey area: useful to
the operator, mildly revealing to us, so aggregate or hash them if they ever leave the instance.

Two masters, and only one of them needs a switch. **Local metering** answers the operator's own
questions — capacity, which plugin is expensive, what to charge internally — and is on by default.
**Sending the same numbers off the instance** so they can be billed against is a data-egress
question rather than a cost one, and is separately configured. Cost was never the objection.

What ownership unit exists today: **none beyond the instance.** `auth` has users and roles,
`player_data` has players, `ExoWorkspace` is a developer's local plugin directory, and environments
(dev/prod) are deploy targets. Nothing answers "whose plugins are these", because there has only
ever been one answer.

**The tenant is a Title, and a studio sits above it.** PlayFab's shape — a Studio holds Titles —
with the studio as a **field** rather than an entity: one studio, many titles, usage belongs to a
title and rolls up to the studio.

```
studio_id   a field, not an entity: the account the bill goes to
  └── Title   the tenant: plugins, players, environments, usage
        ├── environment   dev / staging / prod — a deploy target
        ├── plugins
        ├── players
        └── usage records
```

**A Title gets its own instance.** That is what both PlayFab and UGS do, and it is what collapses
"tenant" back into "the instance" instead of requiring multi-tenancy: nothing is shared, so nothing
needs scoping and there is no query to filter. Titles are separated by a process boundary and a
database file, which is a stronger guarantee than a `WHERE` clause — and it makes many-titles-per-
instance a shape to avoid rather than one to build.

So the MVP needs **no isolation work at all** — one studio, one title, both ids constant. What it
needs is the **shape**: the instance knows its `title_id` and `studio_id`, deploys carry them, and
metering records carry them. Then the rollup — usage per plugin, summed to the title, summed to the
studio — is a `GROUP BY` that is already correct on day one and does not change when the second
title appears.

**Staff are ordinary users with a higher role, and that is already built.** `Exoforge.Auth.Roles`
carries `admin > studio > player > guest` as scopes on a caller's auth context, and an action
declares the scope it requires. A studio-role user *is* staff; a player-role user *is* a player;
both are users, in the same table, with the same tokens and the same sign-in. **Nothing new is
needed for the staff model.** "Staff assigned to particular players" is an optional relationship on
top of that rather than a different kind of account — not modelled, and not needed until someone
asks for it.

The `studio` **role** and the `studio_id` **field** are different things that happen to share a
word, and the overlap reads correctly: the role is the staff *of* the studio. Worth knowing they are
not the same concept before either is renamed.

**Naming: `title_id`, not `title`.** The manifest already uses `title` for a service's display name
(`Title = "Dispatch Sample"`), so the tenant takes PlayFab's own term, `title_id`, and stays
distinguishable from it. This is the third near-collision in this area — "tenant" was taken for a
plugin's private database namespace, "project" for MSBuild's `.csproj` — so the vocabulary is worth
settling here rather than discovering later.

**Deferred until there is more than one Title**, and cheap when it comes because the identity
already exists: studio membership and per-title permissions (who may deploy to which title), and
per-title isolation *only if* titles are ever made to share an instance, which this design
deliberately avoids.

**Found while doing phases 1–3**, which is the other half of the work: things noticed in passing, split
by whether they were worth doing on the spot.

*Done:*

The fixes made while doing phases 1–4, kept here as an index only - each is in `git log` with its
reasoning: a plugin's logs went nowhere; the exception trace was thrown away; PDBs were not shipped;
the runner had no OS pid accessor; the kill test was a hand run; `exo plugin logs` read only half the
channel; plugin log volume is now bounded per plugin; `PublishReadyToRun` is measured; the health
probes pointed at a 404 in three places; and a deployment property passed on the command line broke
the SDK build instead of the plugin's.

*Worth doing later, in rough order of value:*

- **`upload_plugin` base64s the plugin** into a JSON action payload: +33%, encoded and decoded on
  both sides. A WebSocket binary frame for that one field would fix it, and deploying is rare enough
  that it is hygiene rather than performance.

### The deployment model: how a plugin reaches a running server

**The image is the server, and a plugin is not an image.** One container holds the kernel, the standard
plugins and the .NET runtime, because plugins run as child processes of the BEAM *inside* it — one
container, N processes. A plugin is a 195KB file that is pushed and becomes a process, which is the
whole point of the stdio boundary. Making plugins containers would put a container runtime in the
middle of a pipe and defeat the orchestrator that is already there.

**So the split is:** whoever deploys the server runs it with a volume on the plugin directory, once.
A game developer clicks Deploy in Unity and the plugin is uploaded and hot-loaded, forever after.
They never see a Dockerfile, a tag or a pipeline. The image also works with no volume at all —
plugins are then ephemeral, which is fine for a demo or a dev box — so the volume is one operator
flag and one line of documentation.

**A derived image was considered and rejected**, not on merit but on this: one-click deploy from the
Unity Editor is the product, and a container build per plugin change puts CI/CD between the developer
and their change. Plugins as containers orchestrated by something else was rejected for the mirror
reason: the BEAM is the orchestrator.

**Replicas are the open problem, and it is a design problem.** Verified: a push reaches exactly one
node. `WorkerRegistry` is a local `Registry` and not Horde, and `plugin_manager` broadcasts nothing —
so both the artifact and the runner stay where the push landed. With N replicas and per-replica
volumes, a plugin pushed to one node is missing from the others.

The answer is the one thing that also makes titles work: **a single source of truth.** The artifact
belongs to the *title*, not to a container. Push writes there, and instances converge from it — pull
at boot, or a broadcast on push, or both. That is a change in where the endpoint lives and how
instances converge, not in the plugin model: the plugin stays a file that becomes a process.

Until that exists, the honest statement is **one replica**. Anything more silently loses plugins, and
losing them silently is worse than not supporting it.

**Phase 5 — flexibility and boilerplate.** *Landed.* The host opens every native plugin with a
`hello` frame declaring protocol `1` and the frames it can receive (`action_result`, `host_call`,
`host_log`); the SDK answers with its own (`action`, `event`, `host_call_result`) before the first
action is read. The host refuses a plugin that speaks another protocol or cannot handle what will
be sent, naming which, and refuses one that never answers after five seconds; the SDK refuses to
make a host call a host said it cannot answer, and sends an exception trace to stderr rather than a
`host_log` frame a host did not declare. Adding a frame type is now a capability to negotiate, not a
version to bump. The runner seam stays (native and Elixir; a shared-host runner remains a runner,
not a rewrite). The plugin `.csproj` stays ~20 lines, `exo plugin new` to a running plugin stays one
command, and it gets faster, because a plugin no longer AOT-compiles.

**Phase 6 — verification.** *Landed.* The `kill -9` isolation check is a real test: a plugin that
dies mid-call answers its caller and stops with the reason the supervisor restarts on. The
deployment guards now have tests that build a fixture plugin and assert `EXOFORGE001` and
`EXOFORGE002`, and the runtime contract has one that publishes the fixture, asserts the
runtimeconfig's `LatestMajor` and framework version, then demands a runtime no image has and
asserts the apphost refuses naming it. What is not tested here is a real second runtime - the test
environment has only one - so the container build remains where the image's runtime is verified.
Correct the recorded numbers above when they change.

**What this costs, stated plainly.** 6× RAM per plugin, absorbed by billing. Runtime version
coupling between plugin and image, which AOT did not have. And **IL is decompilable where an AOT
binary is not** — for third-party plugins that is an intellectual-property consideration, and UGS
has exactly the same property.

**Prior art this follows.** UGS Cloud Code (framework-dependent .NET 9, zip of assemblies, R2R for
cold start, size limits, no trimming); LSP and DAP (stdio JSON-RPC, process per server, versioned
handshake); Terraform providers (process per provider, versioned protocol); Grafana (process per
plugin, supervised restart). The counterexample is the VS Code extension host — one host for every
extension, no isolation, and extension bisect as the only mitigation.

Two things were on this list and are settled:

- **Publishing `Exoforge.Plugin.SDK` to a public feed** — decided against. `just pack-sdk` fills the
  local feed, a plugin built outside this repository resolves from it, and `just clean-room-sdk`
  proves the consumer path from a pristine export of `HEAD`. A published feed buys nothing until
  someone without a checkout needs one.
- **Generating client stubs without a cluster** — done, and it took the manifest format with it. The
  manifest is JSON now, written by the plugin's own generator and by the Elixir compiler, and read by
  both the server and the C# tooling. It used to be an Elixir map literal that the server evaluated,
  which meant the only copy of a plugin's contracts could be read by one language — and the tooling
  that generates client stubs from them has no Elixir. Stub generation lays each built plugin's
  manifest over the cluster export, so a plugin that is built but not deployed has stubs, and one
  being edited generates stubs for what it is now rather than for what was last deployed.

What that leaves: a service that is neither built locally nor deployed has no contract, so stubs for
it cannot be generated. The command says which services are missing and writes nothing, rather than
replacing working stubs with a file that has fewer of them.

## 5. Out of Scope for the MVP

Not planned. Recorded so they stop reappearing as "next":

- **Unreal Engine SDK (`ExoforgeUE`)** — a second engine client. M29/M30 already did the work that
  would make this cheap (engine SDKs ship the dotnetSDK binaries), but nothing needs it yet.
- **Clustered matchmaking / lobby** — matchmaking by MMR and latency.
- **Non-standard plugin runtimes** — anything beyond native (framework-dependent .NET) and Elixir. A
  sandboxed runtime is the obvious next one, and it is a runner rather than a rewrite.

---

## 6. Naming

Three buckets, one rule: **no engine SDK owns engine-agnostic code.**

| Bucket | Is | Holds |
| :--- | :--- | :--- |
| **Exo** | language-agnostic deploy & management | the CLI. Deploys C# and Elixir alike; carries no build logic of its own |
| **dotnetSDK** | C#-specific | plugin authoring (`Exoforge.Plugin.SDK`), manifest gen, build and codegen tooling, the C# client |
| **unitySDK** | Unity-specific | the UPM package: Unity runtime wrappers, editor tooling, and the dotnetSDK assemblies as binaries |

Adding an engine means adding a fourth bucket that ships the same two libraries — not a fourth
implementation of them.
