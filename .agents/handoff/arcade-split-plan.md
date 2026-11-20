# Arcade split + opt-in AI tooling (plan, 2026-11-18)

Arcade repo: github.com/alxcsx/exoforge-arcade (public, `main`, single commit). No AI co-author trailers anywhere.

## Decisions (user)
- One public repo, one folder per Unity project, so projects can diverge (2D and 3D).
- Snowball Siege is the only 3D project and the only unimplemented sample (README #3, extension `world_boss`,
  pays through `wallet.credit`); it gets its own 3D (URP/3D) Unity project.
- AI tooling (skills, AGENTS.md, `exo` wrapper) ships INSIDE the SDK tarball (`Agents~`, `Cli~`) but is
  never installed by default. A user opts in; generated copies are gitignored.
- No MCP server exists; ignore the MCP idea.

## Target layout (arcade repo)
```
exoforge-arcade/
  README.md  tools/smoke.sh        # shared, run against a backend
  extensions/                      # shared server extensions + *.Tests (wallet, achievements, game_menu, ...)
  2d-hub/              MainMenu + BrainrotExchange   (Unity project)
  2d-echo-dungeon/     EchoDungeon                   (Unity project)
  2d-doodle-dash/      DoodleDash                    (Unity project)
  3d-snowball-siege/   world_boss client             (3D Unity project, new)
```
Each project: own Assets/Packages/ProjectSettings and its own `Exoforge/exoforge.json` with
`"extensions_dir": "../../extensions"` (relative, forward slashes: works on macOS/Linux/Windows; NO symlinks, they
break on Windows). All samples share ONE backend instance (achievements/wallet are cross-game), so the extensions
are the arcade's server side: built and pushed once with `exo extension build|push`, and the Unity projects are
clients that only need the generated stubs. `ExoWorkspace.ExtensionsDir` is a single path today; a list
(`extensions_dirs`: shared + project-own) is the upgrade if per-project Studio lists get noisy. Real extension
distribution (packaged/versioned artifacts) is NOT needed and is out of scope.
Verify in step A: a test that `ExtensionsPath` resolves `../../extensions` (Path.GetFullPath) on all OSes.

## Work items (one helper at a time, worktree per task)
A. SDK (exoforge repo, wt/agents-optin) - bump SDK version (package.json + ExoforgePackageVersion.cs):
   1. Nothing AI-related installs automatically on import, SetUpAll or build; keep it a menu/CLI opt-in.
   2. Add a headless opt-in: `exo agents install [--claude|--gemini|--agents|--all]` and a Unity
      `-executeMethod` entry, writing skills/AGENTS.md/exo wrapper into the project.
   3. Verify `just pack-unity` tgz contains Cli~ and Agents~; test it.
   4. Installer writes a .gitignore block for what it generated (or documents it).
B. Arcade (exoforge-arcade): git rm --cached the generated AI files (`.agents/ .claude/ .gemini/ exo exo.cmd
   Exoforge/exo*`), ignore them, split into the layout above, fix tools/smoke.sh paths, SetUpAll per project.
   (Publishing the SDK tarball so a fresh clone opens: NOT a priority, the user is the only one working on it.)
C. Snowball Siege: `world_boss` extension (+Tests, smoke script) and the 3D client per README section 3.
D. CI: extract the headless extensions + smoke into the monorepo or CI-run them against Postgres (see earlier discussion).
