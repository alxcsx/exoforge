# Instance reset and per-sample extensions

## Why
Testers get a provisioned instance they cannot recreate. They must be able to wipe it and try another arcade sample.
Repo, Justfile and compose remain maintainer-only; testers act through Studio Settings and the `exo` CLI.

## Goals
- Studio Settings > Danger zone: (1) Reset extensions — remove every user-deployed extension with its tables, files and data; standard extensions stay. (2) Delete everything — also players, game versions, Studio-edited config, file buckets. The Studio admin account survives.
- Both confirm by typing the project name; admin scope only.
- Same server action from CLI: `exo instance reset [--everything]`.
- Each arcade sample declares `"extensions": [...]` in `Exoforge/exoforge.json`; `exo extension push --sample` builds/pushes those plus manifest dependencies, providers first.
- Every sample passes its smoke script after reset + push.

## Non-goals
Undo/backup of a reset; multi-instance provisioning; anything in Justfile/compose for testers.

## Approaches
- Reset: server action `reset_instance(mode)` in extension_manager (picked) vs Studio wiping DB directly (rejected: no CLI path, skips extension cleanup).
- Sample lists: field in exoforge.json (picked) vs separate sample.json (rejected: extra file).

## Left to the builder
Exact wipe order and tables per standard extension; Danger zone layout following existing dangerous-action confirm pattern.
