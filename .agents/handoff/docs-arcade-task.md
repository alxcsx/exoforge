# Task: arcade snippets for the docs (read-only; write only `.agents/handoff/docs-arcade-snippets.md`)

Repo: /Users/alexcs/projects/exoforge-arcade (extensions in `extensions/*/src/*.cs`, Unity bridges under the `2d-*` projects).
Your previous report was too thin and its snippet list was empty. Redo it. For EACH of these 9 topics find the best example
in the arcade code and copy it VERBATIM (no edits, no ellipses) - at most 25 lines each:
 1. service declaration (`[ExoService(...)]` class header)
 2. an action with a non-default `Scope`
 3. a resource record with `[ExoResource]` and `[ExoColumn]`s
 4. an event declared and raised (`[ExoEvent]` + the emit call), and one that handles it (`OnEvent`)
 5. a cron (`[ExoCron]`)
 6. a call from one extension to another (`Exo.Services.<X>` or generated stub)
 7. a singleton config (`[ExoSingletonResource]`) and reading it
 8. `OnExtensionStart` or `[ExoSeed]`
 9. Unity side: a bridge MonoBehaviour calling `ExoServices.<X>` (the `2d-*` projects)
Output format, exactly, per topic:
### N. <topic>
`<repo-relative path>:<first line>-<last line>`
```csharp
<the lines, exactly as in the file>
```
One sentence (max 25 words) saying what it shows. If a topic has no example, write `NONE` and say what you searched.
Before you finish, for every snippet run `sed -n '<first>,<last>p' <path>` and confirm it matches what you wrote.
Do not edit anything else, do not commit. When done reply with only the report path and the list of topics marked NONE.
