# Diamond 2 close: versioning, data safety, and the Developer Guide (2026-11-20)

## Converged (shipped on projetao_mvp)
- Versioning core: extension version = data version (`_v` stamp), `[ExoMigration]` declarative changes with a gate, game versions
  (`versioning`), `client_outdated`, `upgrade_required`, `SchemaVersioningMode.Manual`, lazy row migration + sweeper, action
  revisions (`FromVersion`), plugs (`ExoPlugs`). Drop gate fails closed when versioning is installed but silent.
- Cut after the "overengineering" pass: `ExoAction.Transport`, row-migration modes, `QueryRaw`, forking resources.
- Developer Guide: Markdown only (`priv/guide`), extensions document themselves in `docs/` (Elixir: `priv/docs/`), directives
  `{{about}} {{actions}} {{events}} {{resources}}` build from the code, links `guide: api: event: service:`, drift tests against
  the SDK attributes, CLI verbs, standard extensions, error codes and cross-links.

## Review (same-family subagent; agy and the free models were out of quota) — acted on
Fixed: truncated summaries, versions chapter split into core + advanced fold, plugs moved to the attribute reference, "zero
reflection" wording, glossary, patterns labelled as sketches, three missing chapters (production, auth & scopes, troubleshooting).
Review claims that were wrong (checked): `standard` IS a template name; `SubscribeAsync(topic = default)` takes an optional argument.

## Deliberately not done (decide next time, with a real use case)
- Merge the four link schemes / four directives; drop `nav` front matter; delete `@legacy` ids (the Studio still defaults to "flow").
- Replace the 17 generated overview pages by a default page (they hold the hand-written Settings/Data lists).
- Simplify the per-attribute drift test regexes; trim `07_patterns.md` by half and verify its code compiles.
- `architecture_graph.ex` (1458 lines) and `pdf_manual.ex` (593 lines): outside the new-developer path; keep or cut?
- Quality gap: the 11 rewritten std `@moduledoc`s were written by a free model and checked by script + 3 spot reads, not fully reviewed.

## Not verified (user tests, then feeds back)
Live end-to-end of migrations/sweeper/revisions/client_outdated; the sidebar folds, expand toggle and scroll-to-top in the
running Studio (static screenshots only); `exo extension push` shipping docs/ to a real server.

## Process notes
Free omp models are good at mechanical extraction (verbatim snippets, HEEx->Markdown) and bad at judgment or breadth; always
pair them with a script that can reject their output. agy and codex were out of quota; omp paid models too (weekly).
