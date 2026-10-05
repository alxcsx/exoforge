# DX Backlog — Plugin Authoring, Upload & Management

> **Status**: In progress. See the checklist at the bottom.
>
> Scope: the `exo` CLI, the C# Management library, the Unity Editor Control Center, and the
> Plugin SDK — everything a game developer touches when creating, uploading and managing a plugin.
> Findings are from a DevEx review of the Unity + C# SDK; two were verified against a live cluster.

The audience for all of this is a **game developer in Unity** who has never seen Elixir. They
should be able to scaffold a plugin, build it, deploy it, and see it working — without reading
the server source, and without opening a terminal if they don't want to.

---

## P0 — breaks the core loop

### 1. `exo plugin push` reports success after a failed build

`Exoforge.CLI/Program.cs` discards the build result:

```csharp
_ = BuildPlugin(ws, pushName, GetOption(args, "--rid"));   // ← result ignored
Console.WriteLine($"[Exoforge] Uploading plugin '{pushName}' to live cluster...");
```

`ExoDeployer.UploadPluginAsync` only checks that *a* binary exists, so it uploads the previous
build. Verified against a live cluster with a deliberate compile error:

```
error CS0246: The type or namespace name 'BROKENstring' could not be found
[Exoforge] Build failed: ... exited with code 1.
[Exoforge] Uploading plugin 'snake_leaderboard' to live cluster...
[Exoforge] Successfully deployed 'snake_leaderboard'!
  Server Response: {"status":"installed","type":"native","plugin_id":"snake_leaderboard"}
```

The worst possible failure mode: the developer fixes nothing, sees "Successfully deployed", and
debugs code that is not running. The Unity path is already correct (`BuildPluginAsync` catches and
aborts before `thenDeploy`) — only the CLI is wrong.

**Fix:** abort the push when the build fails.

### 2. The Action Sandbox opens on an action that does not exist

`ExoforgeControlCenter` seeds a hardcoded service catalog, and `ParseServiceCatalog` only *adds*
to it — so the stale entries survive and sort first. Six of the nine seeded names are wrong:

| Seeded | Actual |
| :--- | :--- |
| `auth.verify` | `verify_scope` |
| `player_data.get_profile` | `get_player` |
| `player_data.set_attributes` | `set_data` |
| `player_data.delete_profile` | `delete_player` |
| `plugin_manager.system_info` | `get_system_info` |
| `plugin_manager.export_info` | `export_plugin_info` |

`_sandboxAction` defaults to `get_profile`, so **the first dispatch a new developer ever runs is a
404**.

**Fix:** delete the seed dictionary; populate purely from the live export and default to the first
real action.

---

## P1 — missing capability

### 3. Plugin logs are unreachable

`HostBridge.LogInfo/LogWarning/LogError` reach the server's `Logger` and stop there. Neither the
Control Center nor the CLI can see them, and `plugin_manager` exposes no log action. A developer
can deploy a plugin and has **no window into it running** — no log line, no swallowed exception, no
sign of a boot failure after the upload returns `installed`.

This is the largest *capability* gap. Everything else here is friction by comparison.

**Fix:** a `plugin_manager` log action, a Logs pane in the Control Center, and `exo plugin logs`.

### 4. Native builds require the Exoforge repo checkout

`ExoDeployer.FindManifestGen` walks up looking for `sdk/csharp/Exoforge.ManifestGen` and throws
otherwise, so a game developer who installed the SDK as a UPM tarball **cannot build a native
plugin at all**. The scaffolder makes it worse by falling back to an unpublished package:

```csharp
: "    <PackageReference Include=\"Exoforge.Plugin.SDK\" Version=\"0.1.0\" />";
```

That package is not on NuGet. Outside the repo you get a project that cannot restore, with no hint
why.

**Fix:** ship ManifestGen with the SDK, and make the scaffolder fail loudly with the real reason
instead of emitting an unresolvable reference.

---

## Create — friction

### 5. Unity cannot pick a template

`ScaffoldNewPlugin()` calls `ScaffoldPlugin(path, name)` with no `template`, so Unity always gets
`standard` while the CLI offers three.

**Fix:** a template dropdown in the Plugins tab.

### 6. Scaffolding dead-ends

You get "✓ Scaffolded C# plugin at …" and nothing else — no offer to open the folder, the `.cs` or
the IDE, and no README in the generated project.

**Fix:** end the first-run flow with the file to edit and the command to deploy.

### 7. The `liveops` template targets a deleted feature

`LiveOpsTemplate` emits `DrawerTabs = new[] { "overview", "schedule" }` and the CLI help advertises
`--template standard|inventory|liveops`, but LiveOps (schedule timeline, calendar view,
`TimeWindow`) was removed. A template that scaffolds into a dead drawer tab is worse than not
having it.

**Fix:** drop the template and the help text, or restore the feature.

### 8. No feedback on the plugin name

`exo plugin new "My Cool Plugin!!"` silently becomes `my_cool_plugin`.

**Fix:** show the normalised id before writing.

---

## Upload & build — friction

### 9. `Build All` does not rebuild modified plugins

`Where(p => p.CanBuild && !p.IsBuilt)`. After editing, clicking it does nothing — which reads as
"nothing to do" rather than "wrong button".

### 10. SDK warnings flood the plugin author's build

A clean scaffolded plugin emits IL2026 / IL3050 / IL2067 from *our* `Json.cs` and `PluginHost.cs`.
Those belong in the SDK's own project settings, not in every plugin author's log.

### 11. Build numbers skip on failure

`NextBuildNumber` writes `.buildcount` before `dotnet publish`, so a failed build burns a number
and correlating a deploy with a build is confusing.

### 12. No build timeout

`RunProcess` waits indefinitely; a hung `dotnet publish` hangs the CLI or the Unity editor.

### 13. No watch loop

Edit → alt-tab → click. `dotnet watch` is not leveraged and there is no `exo plugin dev --watch`.

### 14. The wire field is named `wasm_binary` for native plugins

Confusing for anyone reading the protocol.

### 15. `push` does not verify the plugin is live

It prints the server's JSON and stops. A boot failure after `installed` is invisible until you
call an action.

---

## Manage — friction

### 16. Remove has no confirmation

One click removes a plugin from the cluster.

### 17. No per-plugin "test action"

After deploy you must switch tabs and re-find the service by hand.

### 18. `--help` is one flat block

`exo plugin --help` prints three lines. No per-subcommand help, no examples.

### 19. No `--json`

`plugin list` and `status` always pretty-print, so CI cannot consume them.

### 20. Positional parsing is fragile

`args[2]` is the plugin name while flags are scanned anywhere, so
`exo plugin push --rid linux-x64 snake_leaderboard` treats `--rid` as the name.

### 21. No reload

Iterating means remove + push.

---

## Do not regress

Better than most plugin tooling; these are why the SDK feels good when it works:

- **The per-plugin state model** — `✗ Build failed` / `○ Not built` / `● Modified #42` /
  `● Not deployed` / `✓ Ready (1.2 MB)`, with build-tag comparison against the remote version.
  It answers "what do I need to do?" without a wiki.
- **Auto-regenerating client bindings after deploy**, so game code is never out of step.
- **`SessionState`-persisted build failures** surviving domain reloads, with the full exception.
- **`ResolveDotnetPath`** — Unity GUI apps do not inherit the shell PATH; the PATH → login shell →
  common-locations fallback chain is the right fix, well documented.
- **The sample dogfoods the scaffolder** (`src/`, `.slnx`, `.gitignore`, `PluginServices.g.cs`).

---

## Checklist

- [x] 1. `push` aborts when the build fails
- [x] 2. Sandbox catalog comes from the live export; default action exists
- [x] 3. Plugin logs: server action + Control Center pane + `exo plugin logs`
- [ ] 4. Native build works outside the repo — *partly*: the scaffolder now fails loudly and
      `--sdk` / `EXOFORGE_PLUGIN_SDK` can point at the SDK, but `Exoforge.ManifestGen` still has to
      be shipped with the SDK package before a UPM-only install can build a native plugin.
- [x] 5. Template picker in the Unity Plugins tab
- [x] 6. Scaffolding tells you what to do next (and opens the file)
- [x] 7. `liveops` template + stale help removed
- [x] 8. Scaffolder reports the normalised plugin id
- [x] 9. `Build All` rebuilds modified plugins
- [x] 10. SDK trimming warnings suppressed in the SDK's own build
- [x] 11. Build counter only advances on success
- [x] 12. Build has a timeout
- [x] 13. Watch loop for plugin builds (`exo plugin dev`)
- [x] 14. Upload payload field renamed (`wasm_binary` → `binary`)
- [x] 15. `push` verifies the plugin loaded
- [x] 16. Remove asks for confirmation
- [x] 17. Per-plugin "Test action" shortcut
- [x] 18. Per-subcommand `--help` with examples
- [x] 19. `--json` on `plugin list` / `logs` / `status`
- [x] 20. Flag parsing independent of argument position
- [x] 21. `exo plugin reload`

---

## What shipped

| Area | Change |
| :--- | :--- |
| **CLI** | Rewritten around a `CliArgs` parser (position-independent flags), per-subcommand help, `--json`, and errors that say what to do instead of echoing `:not_found`. |
| **Build** | `push` stops on a build failure; build counter only advances on success; 10-minute process timeout; SDK trimming warnings silenced at their source. |
| **Deploy** | `push` verifies the plugin is loaded *at the version just built*; `--no-verify` to skip. |
| **Logs** | New `Exoforge.PluginLogs` ring buffer, written by the native and WASM runners; `plugin_manager.logs` action; `exo plugin logs [--follow]`; a Logs pane in the Control Center. |
| **Lifecycle** | `plugin_manager.reload_plugin` + `exo plugin reload`; removal clears the plugin's logs; Unity removal asks first. |
| **Iteration** | `exo plugin dev` polls the source fingerprint and redeploys on change. |
| **Scaffolding** | Template picker in Unity; reports the normalised id; opens the file to edit; ships a README; no silent unpublished-package fallback. |
| **Sandbox** | Hardcoded catalog deleted — it is built from the live export, and payloads are generated from each action's declared params, so any service (including your own plugin) produces a valid request. |
| **Protocol** | `wasm_binary` → `binary`; the code generator now sanitises multi-line contract docs (a multi-line `@doc` previously emitted invalid C#). |

### Bugs found while fixing

- `PluginLogs.count/1` used a 2-tuple match against 4-tuple ETS objects, so it always returned 0 —
  which also silently disabled the per-plugin cap.
- `ExoCodeGenerator` emitted contract `@doc` strings raw inside `/// <summary>`; any multi-line doc
  produced a client that would not compile, and because the CLI depends on the generated client it
  could not regenerate itself out of the hole.
- The Control Center's seeded service catalog was wrong for six of nine entries, and its default
  action did not exist.
- `LoadSamplePayload` still referenced `combat` / `combat_wasm`, plugins deleted some time ago.
