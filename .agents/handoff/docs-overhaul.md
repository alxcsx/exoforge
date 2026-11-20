# Docs overhaul, phase 1 (audit, read-only except the report files you write)

Docs under audit: `extensions/exoforge_std_docs/priv/docs/01_quickstart.md`, `02_csharp_attributes.md`, `03_architecture.md`,
`04_use_cases_and_patterns.md` (rendered in the web dashboard's Docs view). Truth sources: `Agents.MD` (repo root, current),
`sdk/csharp/Exoforge.Plugin.SDK/Attributes.cs` + `ATTRIBUTES.md`, `sdk/csharp/Exoforge.CLI/Program.cs` (CLI commands),
`core/lib`, `extensions/exoforge_std_*/lib`, `extensions_csharp/`, and the arcade samples repo at `/Users/alexcs/projects/exoforge-arcade`.
Do NOT edit any doc, code or config. Do NOT commit. Write only the three report files named below. Each report at most 120 lines.

## Task A: audit chapters 01 and 03 -> `.agents/handoff/docs-audit-01-03.md`
## Task B: audit chapters 02 and 04 -> `.agents/handoff/docs-audit-02-04.md`
For every checkable claim in the chapter, one table row: `chapter:line | claim | status | evidence`.
Claims to check: attribute/property/method/class names, parameter defaults, CLI commands and flags (`exo ...`), file paths,
ports, versions, counts ("15 standard extensions"), service/action/event names, code samples (do the identifiers they use exist?).
status is one of: OK, WRONG (contradicted by code), STALE (existed once, renamed or removed), MISSING-IN-DOC (see below), UNVERIFIED.
Evidence is `file:line` from a grep you ran. Never guess: if you did not grep it, status is UNVERIFIED.
After the table add three short lists: (1) things true now that the chapter does not mention (for example: versioning, migrations,
schema versioning mode, plugs `ExoPlugs`, `FromVersion`, std extensions list, `exo db migrate`, game versions) take the topic
list from `Agents.MD` sections "Versions", "Typed resources", and the std-extension table; (2) wording that is marketing or vague;
(3) duplicated content between chapters.

## Task C: arcade example inventory -> `.agents/handoff/docs-arcade-examples.md`
Read `/Users/alexcs/projects/exoforge-arcade/extensions/` (server extensions, C#) and the Unity bridges that call them.
For each extension: path, service name, one line of purpose, attributes used (ExoService, ExoAction scopes, ExoResource/ExoColumn,
ExoEvent, ExoCron, ExoDependency, ExoSingletonResource, ExoSeed, OnExtensionStart), resources and their keys, events it raises,
which other extensions it calls. Then pick the best snippet (at most 25 lines, copied exactly, with `file:first-last`) for each docs
topic: service declaration, action with scope, resource + columns, event publish + subscribe, cron, dependency call to another
extension, singleton config, seed/start hook, Unity side calling `ExoServices.<X>`. Prefer short, correct, self-explanatory code.
Skip any snippet that does not compile against the current attributes (check names in Attributes.cs).

When done, reply with: the three report paths and the one-line count of WRONG/STALE rows per chapter.
