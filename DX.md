# DX Backlog — Plugin Authoring, Upload & Management

> **Status**: the review is closed. Every item it found is fixed and in `git log` — the checklist at
> the bottom records what was covered — and what is still open is below.
>
> Scope: the `exo` CLI, the C# Management library, the Unity Editor Studio, and the Plugin SDK —
> everything a game developer touches when creating, uploading and managing a plugin.

The audience for all of this is a **game developer in Unity** who has never seen Elixir. They
should be able to scaffold a plugin, build it, deploy it, and see it working — without reading the
server source, and without opening a terminal if they don't want to.

---

## Open

Nothing. The last item here — a resource table that predates its primary key — is fixed: the
migration gives the table a unique index, which is what `ON CONFLICT` needs, and the write that
used to discard its own failure no longer does. The account below is kept because the shape of the
bug is worth remembering: it was invisible in tests, and the caller reported success either way.

### A resource table can exist without its primary key, and nothing notices

Found while chasing the known-flaky `pinned extensions persist across remounts` test. Not test
noise — a real, silent failure:

```
[warning] [Action] failed in Exoforge.Std.Resources.upsert:
  "ON CONFLICT clause does not match any PRIMARY KEY or UNIQUE constraint"
```

Instrumenting the failure shows the table it is writing to:

```
CREATE TABLE studio_preferences (player_id text, data text)      <- no PRIMARY KEY
```

while a table created by the current code has one:

```
CREATE TABLE studio_preferences (player_id text PRIMARY KEY, data text)
```

`Resources.column_defs/1` — the only thing that creates a resource table — *always* emits
`PRIMARY KEY`, and it is the only caller of that SQL. So a table in the first shape can only come
from an older schema that `CREATE TABLE IF NOT EXISTS` then never repairs. Once a table is in that
state, **every `upsert` against it fails forever**, and `ON CONFLICT` is the only thing that would
have caught it.

Two things make it invisible:

- `Studio.Preferences.put_pinned/2` discards the result (`_ = store(:upsert, ...)`) and always
  returns `:ok`, so a failed write looks like a successful one.
- Nothing verifies a table's shape after migration — `ensure_migrated/1` trusts an ETS cache keyed
  `{plugin_id, table}`, and `migrate_resource/1` uses `IF NOT EXISTS`.

**Fix:** `migrate_resource/1` checks `sqlite_master` for the declared primary
key and rebuild the table when it is missing, so a stale schema self-heals instead of failing every
write. Separately, a fire-and-forget caller like `put_pinned/2` should at least log the failure.

**Repro:** run the dashboard suite; the `ON CONFLICT` warning appears even in a passing run, and the
`pinned extensions persist across remounts` test fails when the write lands on the broken table.
Fixed along the way:

- `PluginLogs.count/1` used a 2-tuple match against 4-tuple ETS objects, so it always returned 0 —
  which also silently disabled the per-plugin cap.
- `ExoCodeGenerator` emitted contract `@doc` strings raw inside `/// <summary>`; any multi-line doc
  produced a client that would not compile, and because the CLI depends on the generated client it
  could not regenerate itself out of the hole.
- The Control Center's seeded service catalog was wrong for six of nine entries, and its default
  action did not exist.
- `LoadSamplePayload` still referenced `combat` / `combat_wasm`, plugins deleted some time ago.

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
- [x] 4. Native build works outside the repo — the generator now ships inside the SDK and is
      dependency-free, and `just pack-sdk` fills a local feed for it. Publishing to a public feed was
      decided against.
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
- [x] 22. A resource table missing its primary key self-heals, and a failed preference write is not
      silent (see Open above)

---

## Gone

Two names from this file's history: **`ManifestGen`** — M26 replaced it with
`Exoforge.Plugin.Generator`, a Roslyn source generator that runs inside the plugin's own compile, so
there is no separate tool to locate — and **Control Center**, which the editor UI now calls
**Exoforge Studio**.
