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
4. MOSTLY DONE (2026-11-20): Overview v2 (quickstart is a one-line strip with a close button and the grid no longer stretches it; headline numbers are the same 30 minutes as the graphs, lifetime totals beside them; the duplicate "no errors" statements removed), request-id lookup (paste `r_…` in the palette, or open `?focus=request:<rid>`), a crashed extension now shows as Crashed in Extension Manager with a readable reason (it showed as "Active & Supervised"), callers get `extension_unavailable`, "cluster" became "server" in the Studio. STILL OPEN: live game version on the Overview, deploy feedback beyond the crash state (running/updating + last deploy time). Previously: Extensions page grouped as "Your game" / "Studio features" / collapsed "Platform internals", readable counts, helpful empty state. STILL OPEN: Overview v2, rid lookup in search/Cmd+K, deploy feedback. Original item: Extensions page grouped as "Your game" / "Studio features" / collapsed "Platform internals"; Overview v2 (one-line dismissible
   guide strip, health + recent failures with rid links + live game version, remove the three duplicate error statements, fix the
   "47 calls / 0 in 30 min" contradiction); rid lookup in search/Cmd+K; deploy feedback (running/failed + reason) in Extension Manager.
5. Observability DONE (screen: health + needs attention, failures, events, request timeline, captures). Generic panel v2 (M), still open: master/detail, Read/Write/Destructive grouping, auto-run zero-arg reads as tables, red + confirm for destructive.
6. Unity editor DONE in code (2026-11-20, SDK 0.1.69; compiles against Unity 6000.6, see memory `compile-unity-editor-code`; behavior and rendering NOT seen, see the verification list below):
   a. DONE: `LastLoginPassword` removed (earlier stored ones are deleted on open), tokens masked in Settings
   b. DONE: build and deploy failures shown on the card (reason, not only a tooltip), "Deploy Failed" state, build log persisted across reloads and shown in the Extensions tab
   c. DONE: environment chip says REMOTE (amber) for any server that is not this machine; deploying to one asks for confirmation; switching environment regenerates the runtime config from the selected environment (it used the workspace default before)
   d. DONE as one shared `ExoforgeExtensionOps` (RID choice, failure recording, deploy error wording, confirm) used by both windows, plus ~700 lines of dead code deleted (IMGUI extension list, sandbox, unused helpers). The two windows still exist; merging them into one is a product decision, not done
   e. PARTLY: Overview shows the served game versions and the editor reacts to `upgrade_required`; no full Versions panel (the web Studio's Game Versions screen is the place)
   f. PARTLY: setup wizard opens once per editor session (not on every domain reload); runtime-pack restore runs off the main thread. Not done: first run in 3 steps; the 3 s `dotnet --version` probes are still synchronous
7. Only then: observability relocation, spec language if still needed, mobile layout.

## Not verified (needs eyes)
Unity rendering in light skin (hard-coded dark cards), setup wizard click counts, whether dotnet WaitForExit runs on a background
thread, how `ResourceLive` is reached from game-extension tabs, the Settings modal and command palette (screens did not open).

## Logs: what was found and fixed (2026-11-20)
Validated end to end on a real server with a C# sample action (`sample_plugin.log_demo`). Faults found and fixed:
- warnings and errors were dropped in a flood (100 lines/s guard); now always kept, drops counted in one summary line
- after a restart one new line hid the persisted history (memory shadowed the database); now merged
- plain `Console.WriteLine`/`Console.Error` of a C# extension never reached the Logs tab; now `[stdout]`/`[stderr]`, and how the
  process exited is logged
- failure groups, the action trace and the log flood counters lived in whichever request created them and vanished with it
  (the reason "Needs attention" and Failures looked empty); they now belong to `Exoforge.TableOwner`
- the per-action `[action]` log line was dead code for Elixir ids and noise for others; removed
Still true and worth knowing: Elixir standard extensions log to the server console, not to the Logs tab; lines logged before the
database is ready are in memory only.

## SDK issues reported on the live server (2026-11-20)
1. Extension crashed on deploy with `exit_before_handshake` / "syntax error: unexpected word": the uploaded file was a Windows executable (`MZ`) on a Linux server. Fixed: staging only takes the publish output of the RID just built; the server refuses a binary built for another OS before stopping the running copy.
2. A refused Studio token said "cluster offline". Fixed: "Sign in again" state (banner, gate, pill, Overview). "cluster" is now "server" in the editor, CLI, deployer and the guide.
3. A refused anonymous player token said nothing useful. Fixed: the console says the session was refused and names Reset Anonymous Player Session / `ExoforgeSDK.Auth.ResetSession()`.
4. Extensions with dependencies deployed in name order. Fixed: `ExoDeployOrder` (providers first, cycle and missing-service problems reported, `Verify` for an order); both Build & Deploy All paths and Build All use it. Not done: the CLI has no push-all; the server's service list is not passed in, so a missing service is not reported in Unity.

## Verification list (needs a person; "compiles" is the only thing already proven)
Environment: a Unity project with the package built from this commit, one local server and one remote server.
- [ ] Wrong OS: build an extension with the target set to `win-x64`, deploy to a Linux server. Expect a refusal naming `linux-musl-x64`, and the previously running version still running.
- [ ] Stale output: build `win-x64`, then Auto while connected to a Linux server, deploy. Expect a working extension (staging ignores the old `win-x64` folder).
- [ ] Sign-in: revoke the Studio token on the server (or let it expire with no refresh token), reopen the window. Expect "SIGN IN AGAIN" in the Extensions banner, on a gated tab, in the header pill and the Overview, and no "offline" wording. Stop the server instead: expect "SERVER OFFLINE".
- [ ] Player token: in play mode with a revoked device token and a refresh token that fails. Expect the console warning naming the menu item; run the menu item and confirm a new anonymous player.
- [ ] Order: two extensions where B calls A's service, names chosen so B sorts first. Build & Deploy All in both windows. Expect A built and deployed first; B's stubs generated from A's manifest. Add a circle and expect the warning.
- [ ] Remote safety: select a non-local environment. Expect the amber "REMOTE" chip in both windows, a confirmation before any deploy, and "Cancel" really deploying nothing. Switch environment, enter play mode, confirm the game connects to the selected one (`Assets/Resources/exoforge.json`).
- [ ] Failures on cards: break a build, then deploy to a server that refuses. Expect a red card with the first lines of the reason, and the Build Log foldout open and surviving a script reload.
- [ ] Password: sign in, close and reopen the editor. Expect the email prefilled and the password empty. Settings shows a masked token.
- [ ] Setup wizard: close it on a fresh project, edit a script to trigger a reload. Expect it not to reopen until the next editor start.
- [ ] Pre-warm: press it with the network off. Expect the editor to stay responsive and a warning afterwards.
- [ ] Game versions: Overview shows e.g. `live 1.0.0 · dev 1.1.0`, "Not set up" with none registered, and `—` without the versioning extension.
Earlier, still unverified: Unity rendering in the light skin (hard-coded dark cards), setup wizard click counts, how `ResourceLive` is reached from game-extension tabs, the Settings modal and the command palette in the web Studio.
