# Docs audit: chapters 01 and 03

## Chapter 01 (01_quickstart.md)

| line | claim | status | evidence |
|---|---|---|---|
| 7 | `com.exoforge.sdk` 0.1.41+ | STALE | sdk/unity/Exoforge.SDK/package.json (version 0.1.50) |
| 8 | .NET 9 minimum | OK | AGENTS.md (".NET 9+") |
| 18 | Zero scene wiring | OK | AGENTS.md ("ExoforgeManager created on demand") |
| 21 | ExoforgeSDK.Auth.LoginAnonymously | OK | AGENTS.md |
| 24-43 | LoginAnonymously code sample | OK | AGENTS.md |
| 59 | `[ExoService(... Version = "0.1.0")]` | OK | Attributes.cs:14 |
| 62 | `[ExoAction(Scope = "player")]` | OK | Attributes.cs:62 |
| 63 | ExoActionException | OK | Attributes.cs:498 |
| 83 | `OnExtensionStart()` no attribute | OK | AGENTS.md (lifecycle) |
| 110 | generated `Assets/Exoforge/Generated/ExoforgeServices.g.cs` | STALE | AGENTS.md ("ExoforgeServices.g.cs" / "ExoServices") |
| 113 | `obj/exoforge/PluginServices.g.cs` | OK | AGENTS.md |
| 129 | `ExoServices.GameplayCalculator` | OK | AGENTS.md |
| 132 | `client.CalculateScore(... onComplete/onError)` | OK | AGENTS.md (main-thread callbacks) |
| 144 | `CalculateScoreAsync` | OK | AGENTS.md |

## Chapter 03 (03_architecture.md)

| line | claim | status | evidence |
|---|---|---|---|
| 19 | worker hello carries `plugin` | WRONG | AGENTS.md ("extension" field) |
| 19 | worker capabilities includes host_call_result | WRONG | AGENTS.md (host declares action_result/host_call/host_log/lifecycle_result; extension declares action/event) |
| 20 | action payload `id: integer` | OK | AGENTS.md |
| 23 | host_call ops list missing db_batch/db_put etc? | STALE | AGENTS.md lists db_batch |
| 31 | 10s lifecycle timeout | OK | AGENTS.md ("10 seconds") |
| 41 | framework-dependent single file | OK | AGENTS.md |
| 43 | `plugin_<ext>` schema prefix | OK | AGENTS.md (configurable) |
| 51 | EXTENSIONS_PATH multi-path | OK | AGENTS.md |
| 52 | /app/builtin_extensions, /app/uploaded_extensions | OK | AGENTS.md |

### True now but not mentioned
- versioning (game versions, locks, resolve)
- migrations (ExoMigration, ExoRowMigration, FromVersion, ExoDrop)
- schema versioning mode (Auto/Manual)
- plugs (ExoPlugs.Use)
- FromVersion action revisions
- std extensions list (17)
- `exo db migrate`
- game versions (dev/live/outdated/blocked)

### Marketing/vague wording
- "Zero Reflection Overhead" (marketing)
- "ahead-of-time tree-shaking" title

### Duplicated content
- wire protocol duplicated with AGENTS.md section.

Counts: chapter 01 WRONG 0, STALE 2; chapter 03 WRONG 2, STALE 1.