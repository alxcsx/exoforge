# Task: one documentation page per standard extension (write only the files named; read the code, do not change it)

Each Exoforge extension keeps its own docs in a reserved folder; the Developer Guide gathers them. For every directory
`extensions/exoforge_std_*` (17 of them) create `extensions/<dir>/priv/docs/overview.md` (create `priv/docs/` if needed).
Do not touch any other file. No commits.

Page format (Markdown, GitHub style, plain English, short sentences, no marketing words, no emoji):
```
---
nav: Overview
summary: <one sentence, max 90 chars>
---
# <Human title, e.g. "Auth">

<2-4 sentences: what it is for and who uses it.>

## Actions
| Action | Scope | What it does |
|---|---|---|
| `name` | `player`/`studio`/`admin`/`service`/`guest`/`server` | <one line> |

## Events
<events it raises, with their topic, or the sentence "It raises no events.">

## Configuration
<every environment variable and Application config key this extension reads, as a table `Setting | Default | Effect`,
or the sentence "It has no settings.">

## Data
<tables or resources it owns, one line each, or "It stores nothing.">
```
Rules, because wrong docs are worse than none:
1. Only state what you verified in the code. Action names and scopes: from `defaction` in the extension's `lib/` and from the
   service contract in `core/lib/std/services.ex` (`defservice <service>` ... `action :name` ... `scope(:x)`). Settings: grep the
   extension's `lib/` and `config/` for `System.get_env`, `Application.get_env`, `Application.fetch_env`. Events: grep for
   `emit` / `EventDispatcher`. Tables: grep for `CREATE TABLE` and `[ExoResource]`/`defresource`.
2. If you cannot find something, leave that section's "none" sentence. Never guess a default value or a scope.
3. Use the action names exactly as written in the code (snake_case, no leading colon).
4. Extensions without a service of their own (`dashboard_views`, `lldb` helpers) still get a page: say what they provide.
5. Do not copy long code. No code blocks except, optionally, one short JSON or C# call example you saw in a test of that extension.

When done run `ls extensions/exoforge_std_*/priv/docs/overview.md | wc -l` and reply with only that number and the list of
extensions where you had to write a "none" sentence because you found nothing.
