# Studio and Unity editor: review, custom-UI decisions and implementation plan (2026-11-20)

Method: real screenshots of the running Studio (throwaway server, `/private/tmp/claude-501/studio/shots`, 1440 px dark + one mobile),
three read-only reviewers (web layout, Unity editor, custom-UI candidates; same model family as the author, Unity not run, so all
Unity visuals are reconstructed from code). I verified the claims below marked VERIFIED; the rest is reviewer judgment.

## Capture note (important for the next review)
The first set of screenshots was server-rendered only: headless Chrome on `127.0.0.1` fails the WebSocket origin check
("Could not check origin"), so LiveView never connected and clicks did nothing (modals, tabs and the inspector were never seen).
Use `http://localhost:4005` (the compose default `PHX_HOST`) with puppeteer-core in `/private/tmp/claude-501/studio`.

## Verified
- VERIFIED (live DOM): buttons in Users and Extension Manager show the icon NAME as text ("refresh Refresh", "plus Register User"):
  `refresh` and `plus` were missing from the three icon sets. FIXED + regression test (`ui_standard_test`).
- VERIFIED: the Studio's resource browser exists (`/resources/:name`, `ResourceLive`) but nothing in the nav leads to it; the
  "Resource Store" tab is nine raw RPC cards. Discoverability, not absence.
- VERIFIED: Unity editor has no handling of `upgrade_required`/game versions; `LastLoginPassword` is stored in EditorPrefs in clear;
  `DrawSandbox`/`DrawEnvironmentSelector` have no callers (dead code).
- Seen in screenshots: versioning, cron, metering, observability tabs are the generic "one form card per action" panel; overview
  banner wastes ~17% of the page; Extensions page mixes 19 extensions by "has a UI", counts do not add up.

## Which extensions get a custom UI (decision)
| Extension | Verdict | Why |
|---|---|---|
| versioning | P1 custom | highest-consequence job; today raw JSON `locks` and typed version strings |
| metering | P2 custom, small | one read action, wants range + totals + table |
| cron | P2 custom, small | needs a job table + Run now; contract returns bare maps (declare the fields first) |
| observability | P2, later | most of it already lives in Overview/timeline; relocate, do not rebuild |
| resources (resource_store) | no view: link to the real browser, hide the RPC tab | admin API |
| database, lldb, http, ws, transport, dashboard_views | generic is fine; hide platform internals by default | no producer job |
| auth, player_data, file_bucket, extension_manager, docs | already custom; fix bugs only (icons, file_bucket preview/pills) | |
| game extensions (arcade) | NOT custom UIs: better `[ExoColumn]`/`[ExoResource]` metadata + row actions | wallet credit/debit, level moderation, enum choices |

## Mechanism (my decision, differs from one reviewer)
Do NOT design a declarative view-spec language from one example. Build versioning, then metering, then cron as ordinary LiveComponents
on a few shared function components (status badge, confirm button, data table, stat tile). When three exist, extract the spec only if a
C# author still needs something metadata + row actions cannot express (candidate: world_boss status card). Microfrontend assets stay the
escape hatch; no new data bridge.

## Slices (ordered)
0. DONE: icon bug + regression test; quick wins done: "Actions"/"Access" labels, no always-SYNC pill, display name as page title, optional numbers open empty and are not sent, category pills add up (a made-up category gets its own pill). STILL OPEN from the list (S, web): rename "Interactive Action Control Panel" -> "Actions", "Technical
   Context & Scopes" -> "Access", drop the always-SYNC pill, display name as page title, empty (not "1") defaults for optional integers,
   "plugin" terminology leaks in descriptions, fix the Extensions counts, `aria-label`s on icon buttons, Esc closes the topmost modal.
1. DONE (7e9ec8b+): Versioning view (M): `Exoforge.Std.DashboardViews.VersioningView` (convention-resolved): status stats, versions table with chips, locks
   as `extension@version`, Promote/Block with two-step confirm, Edit locks (dev only), Register form, and the "versioning is off until
   you register a version" empty state. Tests: LiveView render + actions.
2. DONE: Usage (metering) and Scheduled Tasks (cron) screens. Cron needed no contract change: `list_jobs` already returns id, schedule, last run/result, run count. Still open: declare `returns` fields in the contracts for the catalog, and a stale-build ghost ("Plugin Manager") was a leftover in `_build`, removed locally.
3. Resource discoverability + metadata (M): link Extensions cards and the nav to `/resources/:name`; `ExoColumn` Format/Readonly/Hidden/
   Choices/Min/Max/Order, `ExoResource` DefaultSort + row actions (generator + manifest + `ResourceLive`). Unlocks wallet and moderation.
4. IA (M): Extensions page grouped as "Your game" / "Studio features" / collapsed "Platform internals"; Overview v2 (one-line dismissible
   guide strip, health + recent failures with rid links + live game version, remove the three duplicate error statements, fix the
   "47 calls / 0 in 30 min" contradiction); rid lookup in search/Cmd+K; deploy feedback (running/failed + reason) in Extension Manager.
5. Generic panel v2 (M): master/detail, Read/Write/Destructive grouping, auto-run zero-arg reads as tables, red + confirm for destructive.
6. Unity editor (cannot be compiled or run in this environment; do with Unity open):
   a. security: stop persisting `LastLoginPassword`, mask tokens in Settings (S)
   b. show build/deploy errors on the Studio Extensions tab + persist the build log (S)
   c. environment safety: coloured env chip, regenerate runtime config on switch, confirm deploy to non-local (S-M)
   d. delete the duplicate build/deploy path and dead code (~700 lines), one Extensions UI (M)
   e. Versions panel + `OnUpgradeRequired` editor hook; deep links to the web Studio (timeline by rid, logs) (M)
   f. first run in 3 steps; stop reopening the wizard on every domain reload; move 30 s `WaitForExit` off the main thread (M)
7. Only then: observability relocation, spec language if still needed, mobile layout.

## Not verified (needs eyes)
Unity rendering in light skin (hard-coded dark cards), setup wizard click counts, whether dotnet WaitForExit runs on a background
thread, how `ResourceLive` is reached from game-extension tabs, the Settings modal and command palette (screens did not open).
