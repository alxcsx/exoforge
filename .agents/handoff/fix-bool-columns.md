# Fix menu-11: boolean resource/record columns round-trip as strings

Repo /Users/alexcs/projects/exoforge, branch projetao_mvp. Toolchain `/Users/alexcs/.local/bin/mise exec --`.
Full finding: .agents/samples-findings/phase2.md (menu-11). The live backend runs on SQLite (EXOFORGE_DATA_DIR).
A column declared "type":"boolean" (C# [ExoColumn] bool, e.g. player_settings.color_blind) stores
`true` and reads back "true" (string), via `exo resource create/list` and via the native
`Exo.Database.Get<T>` host call, so System.Text.Json fails "token type 'String' as a boolean".
Find where values are encoded/decoded for typed columns (extensions/exoforge_std_database adapters,
extensions/exoforge_std_resources, the native host_call db ops in
core/lib/drivers/runtime/native_extension_runner.ex) and make booleans come back as JSON booleans on SQLite
and Postgres (SQLite stores 0/1 or text - decode by the declared column type). Check integer/float/json columns
don't have the same problem and fix them in the same place if they do.
Do NOT touch the http router, ws socket_handler or transport (another worker owns them), or the arcade.
Tests: database/resources test - a boolean column written true/false reads back as true/false (both write
paths: resource_store create and a native-style db put/get); existing tests stay green.
Run only touched test files (`mix deps.compile --force` in an extension dir if a path dep is stale).
No SDK version bump needed unless you change C#. Commit "fix(database): ..."; do not push. Report <=15 lines.
