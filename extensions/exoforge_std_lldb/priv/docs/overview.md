---
nav: Overview
summary: The storage driver layer: connections, pools, schemas, roles, DDL and the migration runn.
---
# Storage driver layer

The storage driver layer: connections, pools, schemas, roles, DDL and the migration runner. It is engine specific; Postgres is the supported engine. Other std extensions reach storage through it and through `database`.

## Actions

| Action | Scope | Takes | What it does |
|---|---|---|---|
| `exec` | `server` | `operation`, `arguments`, `namespace` | Runs an operation inside a namespace: a SQL statement with arguments, or a key-value command. |
| `provision_namespace` | `server` | `namespace` | Creates, or refreshes, the isolated namespace (and its access rules) for an extension. |
| `drop_namespace` | `server` | `namespace` | Removes an extension's namespace and everything in it. |
| `transaction` | `server` | `statements`, `namespace` | Runs statements (SQL with positional arguments) in order in one transaction, all or nothing; a failure names the statement index. |
| `introspect` | `server` | `table`, `namespace` | Describes a table in engine-neutral terms: columns with logical types, nullability and the primary key. |
| `dialect` | `global` | - | How to write SQL for this engine: placeholder and quoting style, upsert strategy and type names. |
| `apply_schema` | `server` | `resources`, `migrations`, `version`, `namespace` | Applies the safe changes that bring a namespace's tables in line with declared resources (logical `storage` types); an unsafe change applies nothing and is reported. |
| `run_migrations` | `server` | `namespace`, `migrations` | Applies an extension's hand-written SQL migrations in version order. |
| `reset_table` | `server` | `table`, `namespace` | Drops a table of a namespace, and its schema history. |
| `table_columns` | `server` | `table`, `namespace` | Lists the columns of a table in a namespace. |
| `connection_config` | `server` | `namespace` | Retrieves namespaced database connection details. |
| `health_check` | `global` | - | Performs a low-level ping to verify the database is reachable. |

## Events

| Event | Payload | What it means |
|---|---|---|
| `connection_lost` | `reason`, `timestamp` | Fired when the underlying database pool drops connection. |

## Settings

- Environment variable `DATABASE_URL`
- Environment variable `EXOFORGE_DB_POOL_SIZE`
- Environment variable `EXOFORGE_DB_POOL_SIZES`
- Environment variable `EXOFORGE_DB_ROLE_SECRET`
- `config :exoforge_std_lldb, :schema_lock_timeout`

## Data

It creates no tables of its own.
