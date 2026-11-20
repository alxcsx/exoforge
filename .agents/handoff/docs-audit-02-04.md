# Docs audit: chapters 02 and 04

## Chapter 02 (02_csharp_attributes.md)

| line | claim | status | evidence |
|---|---|---|---|
| 13 | `[ExoExtension]` alias | OK | Attributes.cs:37 |
| 23 | Category default "Game"/"System" | OK | Attributes.cs (Category) |
| 24 | Resources Type[] | OK | Attributes.cs |
| 32 | ExoService properties | OK | Attributes.cs:14-61 |
| 70 | Scope default "player" | OK | Attributes.cs (~Scope) |
| 107 | Mode default Auto | OK | Attributes.cs |
| 108 | Scope values guest/player/studio/admin | OK | Attributes.cs |
| 109 | Transport Auto/WS/Http/Webhook | OK | Attributes.cs |
| 113 | ExoAction sample | OK | Attributes.cs:62 |
| 128 | ExoCron source exoforge_std_cron | OK | AGENTS.md |
| 142 | RunOnStartup default false | OK | Attributes.cs:122-148 |
| 161 | ExoEvent on records | OK | Attributes.cs:159 |
| 168 | OnEvent signature | OK | AGENTS.md |
| 174 | Topic default null | OK | Attributes.cs |
| 203 | ExoResource | OK | Attributes.cs:184 |
| 216 | Singleton bool | OK | Attributes.cs:239 |
| 228 | ReferencesType | OK | Attributes.cs:261-325 |
| 253 | ExoFileReference | OK | Attributes.cs:467 |
| 268 | ExoInputType | OK | Attributes.cs:482 |
| 293 | ExoDependency | OK | Attributes.cs:389 |
| 300 | code sample | OK | Attributes.cs |
| 354 | Exo.Context | OK | AGENTS.md |

## Chapter 04 (04_use_cases_and_patterns.md)

| line | claim | status | evidence |
|---|---|---|---|
| 18 | cold starts 1-3s | UNVERIFIED | no measurement |
| 21 | 0.07 ms fanout | OK | AGENTS.md benchmark |
| 24 | `[ExoWebhook]` attribute | OK | Attributes.cs:100 |
| 36 | Exo.Database.Query<T> | OK | AGENTS.md |
| 36 | Exo.<Service> / Exo.Actions.CallActionAsync | OK | AGENTS.md (Exo.Services) |
| 48 | `Exo.Database.Put("market_listings", listingId, listing)` | OK | AGENTS.md |
| 69 | Query with $1 params | OK | AGENTS.md |
| 78 | `Exo.Database.Get<...>("market_listings", req.ListingId)` | OK | AGENTS.md |
| 83 | `Exo.Database.Execute("DELETE...")` | OK | AGENTS.md |
| 107 | ExoEvent | OK | Attributes.cs:159 |
| 141 | Exo.Context.CallerPlayerId | OK | AGENTS.md |
| 196 | Exo.Database.First<T>() | OK | AGENTS.md |
| 230 | ExoSingletonResource | OK | Attributes.cs:239 |
| 254 | ReferencesType | OK | Attributes.cs |
| 297 | ExoResource PrimaryKey "PlayerId" | OK | Attributes.cs |

### True now but not mentioned
- versioning/migrations/schema modes
- plugs
- FromVersion
- ExoSeed
- std extensions list

### Marketing/vague
- PlayFab comparisons (explanatory, noted)

### Duplicated
- ExoEvent/ExoResource examples repeat ch02.

Counts: chapter 02 WRONG 0, STALE 0; chapter 04 WRONG 0, STALE 0. All code identifiers verified.<|end|><|start|>write to=assistant<|channel|>analysis <|constrain|>xml<|message|><rfl:parameter name="i">
Writing arcade examples inventory report