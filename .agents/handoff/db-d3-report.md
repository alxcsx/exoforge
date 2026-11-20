# D3 Report: Batched Atomic Writes (`db_batch`)

- **Branch / Commit**: `wt/d3` @ `f43c17e` (`feat(database): add Transaction/ExecuteBatch and atomic db_batch host call`)
- **SDK Changes**:
  - `sdk/csharp/Exoforge.Plugin.SDK/Interfaces.cs:27-39,77-110` — `ITransaction` (write-only recorder: `Execute`, `Put`, `Delete`; no reads), `IDatabase.Transaction(Action<ITransaction>)`, `IDatabase.ExecuteBatch(IEnumerable<DbBatchOperation>)`.
  - `sdk/csharp/Exoforge.Plugin.SDK/DatabaseExtensions.cs:197-288,550-644` — `ITransaction.ExecuteSql(FormattableString)`, entity `Put<T>`/`Delete<T>`, `IDatabase.ExecuteBatch(IEnumerable<FormattableString>)`, `IDatabase.ExecuteBatch(IEnumerable<(string Sql, object?[]? Args)>)`, `DbBatchOperation`.
  - `sdk/csharp/Exoforge.Plugin.SDK/HostBridge.cs:307-320`, `PluginHost.cs:58-63,1112-1121,1201-1213`, `PluginContext.cs:152-212`, `Exceptions.cs:17-105`, `Testing.cs:84-130` — `db_batch` wire call, `ExoDatabaseException.FailedIndex`/`Index`, `InMemoryDatabase` atomic rollback.
- **Host & Postgres Changes**:
  - `core/lib/drivers/runtime/native_extension_runner.ex:667-732,839-886` — `run_host_call("db_batch", ...)` with `Manifest.allows_service?(manifest, "database")` gate, extension-schema isolation (`manifest.id`), and structured error `%{ok: false, index: idx, error: %{code: ..., index: idx, message: ...}}`.
  - `extensions/exoforge_std_database/lib/exoforge/std/database/adapters/postgres.ex:146-330` & `database.ex:173-176` — `Postgrex.transaction` batch execution over `tx_conn` rolling back all preceding SQL and KV writes on failure and returning `{:error, %{index: idx, reason: reason, message: message}}`.
- **Docs**: `Agents.MD:211,263-269`, `sdk/unity/Exoforge.SDK/Agents~/skills/exoforge-extensions/SKILL.md:80` (no SDK version bump).
- **Acceptance**:
  - `dotnet test sdk/csharp/Exoforge.Plugin.SDK.Tests`: PASS (`Failed: 0, Passed: 106, Total: 106`; failed before with 3 compile errors before implementation).
  - `cd core && mix test test/native_extension_runner_test.exs test/extension_protocol_test.exs`: PASS (`Result: 39 passed`; failed before with `36/39 passed, Failed: 3 tests`).
  - `cd extensions/exoforge_std_database && mix test` (temp Postgres on 54330): PASS (`Result: 24 passed`; failed before with `21/24 passed, Failed: 3 tests`).
  - `dotnet build extensions_csharp/sample_plugin`: PASS (`Build succeeded. 0 Warning(s), 0 Error(s)`).
  - `git log --oneline -1 wt/d3`: `f43c17e feat(database): add Transaction/ExecuteBatch and atomic db_batch host call`.
