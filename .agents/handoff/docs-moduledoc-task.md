# Task: improve the @moduledoc of 11 standard extensions (documentation only)

The Developer Guide now shows each extension's own `@moduledoc` as the opening of its page (the `{{about}}` directive) and the
Studio inspector shows it too. Several are one or two lines. Rewrite the `@moduledoc` of the ROOT module of these extensions:

| extension | file |
|---|---|
| cron | extensions/exoforge_std_cron/lib/exoforge/std/cron.ex |
| ws | extensions/exoforge_std_ws/lib/exoforge/std/ws.ex |
| transport | extensions/exoforge_std_transport/lib/exoforge/std/transport.ex |
| http | extensions/exoforge_std_http/lib/exoforge/std/http.ex |
| dashboard | extensions/exoforge_std_dashboard/lib/exoforge/std/dashboard.ex |
| docs | extensions/exoforge_std_docs/lib/exoforge/std/docs.ex |
| dashboard_views | extensions/exoforge_std_dashboard_views/lib/exoforge/std/dashboard_views.ex |
| file_bucket | extensions/exoforge_std_file_bucket/lib/exoforge/std/file_bucket.ex |
| player_data | extensions/exoforge_std_player_data/lib/exoforge/std/player_data.ex |
| versioning | extensions/exoforge_std_versioning/lib/exoforge/std/versioning.ex |
| database | extensions/exoforge_std_database/lib/exoforge/std/database.ex |

HARD RULES (a script checks them; a failing file is reverted):
1. Change ONLY text inside the `@moduledoc """ ... """` heredoc of that one module. No other line of any file may change.
2. Keep every factual sentence already there that is still true. Add; do not delete facts.
3. Every fact you add must be verifiable in that extension's `lib/` (or `core/lib` for kernel behavior). Read the code first:
   the supervision children (`children/0`), the processes and ETS tables it starts, the tables it creates, the ports it opens,
   the events it emits (`emit`/`EventDispatcher`), the services it calls (`ActionDispatcher.dispatch...(:service`), the
   `Application.get_env` / `System.get_env` keys it reads. If you did not see it in the code, do not write it.
4. Structure, Markdown, 600 to 2500 characters total:
   - a first paragraph of 2 to 4 sentences: what it is, who uses it, why it exists as an extension;
   - `### How it works` with 3 to 7 bullets of concrete mechanics seen in the code;
   - `### Depends on` one line: the services it calls (e.g. `:database`), or "Nothing."
   Do NOT use the headings `## Actions`, `## Events`, `## Settings` or `## Data` (the guide page already has them).
   Do NOT list actions or events (the guide builds those tables from the contract).
5. Backticked names must exist: modules (`Exoforge.Std.Foo`), services (`:auth`), env vars (`EXOFORGE_X`). No invented names.
6. Plain English, short sentences, no marketing words ("powerful", "seamless", "robust"), no emoji.

After editing, run `cd extensions/exoforge_std_<name> && mix compile 2>&1 | tail -3` for each (it must compile).
Reply with only: the list of extensions you finished, and any you skipped with the reason. Do not commit.
