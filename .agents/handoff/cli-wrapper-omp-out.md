Working...
Commit 207b63682c4b5ecabf846d15f1e8bd73e398f66d on wt/cli-wrapper.

- Added `ExoCliInstaller` (wrappers + gitignore block, exo/exo.cmd/exo.ps1 only).
- `exo cli install [--dir]` and `exo cli status` wired in Program.cs.
- `ExoAgentInstaller.Install` now calls `ExoCliInstaller` (no duplicate exo entries in agent block).
- Tests: 136 passed.
