# Feedback: cross-extension data and typed calls (design only)

Evidence: postgres.ex:82 (url `search_path=<schema>`), :602 (pool `search_path: "<schema>", public`),
:653 (`plugin_<id>` schema); sqlite.ex:466 `db_path` (one file per extension, no shared namespace).
Stubs exist already: `exo extension stubs` (Program.cs:2032, ExoCodeGenerator.GeneratePluginStubs:569) writes
`src/Generated/PluginServices.g.cs` by hand; generator reads `[ExoDependency]` at ExoforgePluginGenerator.cs:515.

## (1) Joining another extension's table: keep RPC batch hydration

| Option | Zero coupling | Deny by default | SQLite parity | Deletion over addition |
|---|---|---|---|---|
| Schema-qualified read grants | No: schema and table names become public contract | Grant is per-role, but all pools share one DB user, so needs per-ext roles | No: separate files; needs `ATTACH ... mode=ro` and a different SQL spelling | Adds roles, grants, ATTACH |
| Read views (producer exports) | Better, but a second contract beside actions | Yes if producer opts in | No (same ATTACH problem) | Adds view DDL, migrations, drift |
| **RPC batch hydration** | Yes: only the action contract | Yes: ActionDispatcher scope checks already apply | Yes: no SQL leaves the extension | Adds nothing |

Security: a grant or view lets a consumer read rows around the producer's action-level authorization and scopes
(and `Exo.Database.Query` takes free SQL, so the reach would be unbounded). RPC keeps one door. On SQLite a join
would need the consumer to open the producer's file, which also bypasses the isolation.
Cost accepted: N+1 is avoided by one `get_many(ids)` call per page, which is the join (two round trips, no more).
Decision: do not touch the database adapters. Make the missing-relation failure explain itself, and make the RPC typed (2).

## (2) Typed inter-extension calls: stubs generated into obj/ from `[ExoDependency]`

One mechanism, reusing what exists: the stub generator, the manifest overlay (sibling manifests, else cluster export).
Change only *when* it runs and *where* it writes: at build, to `obj/`, driven by the declared dependencies, so
nobody commits or hand-runs `PluginServices.g.cs`. Shared DTOs come from the same stubs (request/response
records are emitted per contract), so the consumer declares none and `CallAction("svc","act")` strings go away.
`ReferencesType = typeof(Item)` binds to the stub's record for the producer's table type, and the generator
resolves the FK target from the manifest instead of a string.

## Specs (small, ordered)

### S1 Explain the failure (docs and message)
- Goal: `relation does not exist` from `Database.Query` says the table belongs to another extension and points to
  `get_many` plus stubs. Document "no cross-extension SQL" in the database extension moduledoc and AGENTS.md section 2.
- Files: extensions/exoforge_std_database/lib/exoforge/std/database/adapters/postgres.ex (error mapping near :133),
  sqlite.ex (same text for `no such table`), extensions/exoforge_std_database/test/.
- Accept: `cd extensions/exoforge_std_database && mix test` (new test asserts the hint on both adapters).

### S2 Build-time stubs into obj/ from `[ExoDependency]`
- Goal: a build target runs stub generation for the extension's declared dependencies and adds the file under
  `$(IntermediateOutputPath)` to Compile. No file in `src/`. Falls back to the cluster export, and fails the build with
  the existing "No contracts for ..." message (Program.cs:2098) when neither source has the contract.
- Files: Directory.Build.targets (one target next to ExoforgeStageForUnity:72), sdk/csharp/Exoforge.Management/
  ExoCodeGenerator.cs (reuse GeneratePluginStubsToFile; accept manifests-only input), sdk/csharp/Exoforge.CLI/Program.cs
  (`stubs` keeps working, now an alias that prints the obj path).
- Accept: `dotnet test sdk/csharp/Exoforge.Management.Tests`; `dotnet build extensions_csharp/sample_plugin` then
  `ls extensions_csharp/sample_plugin/obj/**/PluginServices.g.cs`; `git status --short` shows nothing new in src/.

### S3 Shared record types and `ReferencesType`
- Goal: stubs emit one record per contract type, reused by every action that names it. `ReferencesType = typeof(T)` where T is
  a stub type resolves the FK to the producing service/table via its manifest; an unknown type is a compile diagnostic.
- Files: sdk/csharp/Exoforge.Plugin.Generator/ExoforgePluginGenerator.cs (:1022 area), Exoforge.Management/ExoCodeGenerator.cs,
  sdk/csharp/Exoforge.Plugin.Generator.Tests/.
- Accept: `dotnet test sdk/csharp/Exoforge.Plugin.Generator.Tests`; `dotnet test sdk/csharp/Exoforge.Plugin.SDK.Tests`.

### S4 Delete the old path
- Goal: remove committed `src/Generated/PluginServices.g.cs` files and hand-copied DTOs in samples and templates
  (`exo extension new`), migrate raw `CallAction("svc","act")` callers to stubs, add `get_many` to the sample producer.
- Files: extensions_csharp/**, sdk/unity/sample_unity/Exoforge/extensions/**, handoff/loja_itens.cs pattern.
- Accept: `just build-extensions`; `just sample-check`; `grep -rn 'CallAction<' extensions_csharp sdk/unity/sample_unity/Exoforge/extensions` returns none.

Risks: S2 build needs sibling manifests built first (order via ProjectReference-free ordering; cluster export is the fallback).
Next step: approve S1+S2, then S3, S4 last.
