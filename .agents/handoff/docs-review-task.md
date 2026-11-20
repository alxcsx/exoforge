# Review: the Developer Guide and the system behind it (read-only; write only `.agents/handoff/docs-review.md`)

Context: the Developer Guide is now Markdown rendered by the docs extension; each extension keeps its own pages in `docs/`
and the guide gathers them; action/event tables are built from the code. It was built quickly by one author over a few hours.
You are the second pair of eyes. Look for OVER-ENGINEERING and for things that DO NOT MAKE SENSE. Be blunt and specific.

Read (in this order, stop when you have enough):
1. `extensions/exoforge_std_docs/priv/guide/*.md` (8 chapters) as a first-time game developer would.
2. `extensions/exoforge_std_docs/lib/exoforge/std/docs.ex`, `docs/pages.ex`, `docs/markdown.ex`, `docs/view.ex`
   (loader, directives `{{about}} {{actions}} {{events}} {{resources}}`, link schemes `guide: api: event: service:`, front matter,
   sidebar folds, expand toggle), and `extensions/exoforge_std_docs/test/*.exs`.
3. Two or three of `extensions/exoforge_std_*/priv/docs/overview.md`.
4. For the versioning features the guide documents (chapter 04), compare the claims with `Agents.MD` ("Versions" paragraph) and
   `sdk/csharp/Exoforge.Plugin.SDK/Attributes.cs`.

Answer these, each with `file:line` evidence:
A. Over-engineering: which mechanisms in the guide system or in what it documents are heavier than their use justifies?
   (candidates to challenge: four link schemes, four directives, front matter keys, nested sidebar folds, generated overview
   pages, per-attribute drift tests, row stamps + lazy row migration + sweeper + `client_outdated` + action revisions + plugs + manual
   mode as ONE story for a small studio). Say what you would delete or merge and what it costs to keep.
B. Things that do not make sense to a reader: contradictions between chapters, steps that cannot work as written, claims the code
   contradicts (check at least 10 claims with grep and say which you verified), jargon used before it is explained, chapters that
   repeat each other, examples that would not compile.
C. Missing: the three most valuable pages or sections a new developer would look for and cannot find.
D. A ranked list of at most 12 concrete actions (delete / merge / rewrite / fix), each with effort S/M/L and your confidence.

Rules: do not edit anything except the report. Do not run the full test suites. Reply with the report path and the top 3 actions.
