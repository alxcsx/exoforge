# Operating Exoforge (maintainers and self-hosters)

> This page is for people who run the server. It is not part of the Developer Guide, which is written for game developers who use an Exoforge instance and never see the repository, the Justfile or the container image.

## Run in production

Exoforge ships as one container image plus a PostgreSQL database. This page covers the stack as the repository's `docker-compose.yml` defines it, the settings you must change before real players arrive, and what to back up.

---

## The stack

`just compose-up` builds the extensions and starts two services, and `just compose-down` stops them:

| Service | What it is | Port |
|---|---|---|
| `postgres` | PostgreSQL 16, database `exoforge_prod`. | 5432 |
| `backend` | The Exoforge server image: kernel, the standard extensions and yours. | 4005 Studio, 4000 WebSocket, 4001 REST |

Two volumes hold everything that must survive a restart: `postgres_data` (the database) and `exoforge_uploads` (the extensions you deploy with `exo extension push`).

## Settings to change first

The compose file ships development defaults. Change these before exposing the stack:

| Setting | Compose default | Why change it |
|---|---|---|
| `EXOFORGE_ADMIN_EMAIL`, `EXOFORGE_ADMIN_PASSWORD` | `admin` / `admin` | They create the administrator account at every boot. Leave the password unset and the account is removed. |
| `POSTGRES_PASSWORD` | `postgres` | The database password, also used in `DATABASE_URL`. |
| `SECRET_KEY_BASE`, `LIVEVIEW_SIGNING_SALT` | development values | They sign Studio sessions. |
| `RELEASE_COOKIE` | `exoforge_cluster_cookie` | The secret of the Erlang cluster. |

## Settings that shape behavior

| Setting | Default | Effect |
|---|---|---|
| `EXOFORGE_SCHEMA_CHANGE_MODE` | `refuse` | What an unsafe change to a typed table does. `refuse` fails that extension alone and says where; `reset` drops and rebuilds the table and loses its rows. Keep `refuse` in production. See [Versions & Migrations](../extensions/exoforge_std_docs/priv/guide/04_versions_and_migrations.md). |
| `EXOFORGE_DB_POOL_SIZE` | `4` | Connections each extension may hold. |
| `EXOFORGE_DB_POOL_SIZES` | `auth=8` | Per-extension override of the pool size. |
| `POSTGRES_MAX_CONNECTIONS` | `300` | Every extension connects as its own role with its own pool (pool size plus 2), so the database needs room for all of them. |
| `EXTENSIONS_PATH` | `/app/builtin_extensions,/app/uploaded_extensions` | Where extensions are loaded from. |
| `UPLOADED_EXTENSIONS_PATH` | `/app/uploaded_extensions` | Where `exo extension push` writes. |

## Built-in and uploaded extensions

The standard extensions are compiled into the image under `builtin_extensions` (read-only). The extensions you deploy land in `uploaded_extensions`, which is a volume, so an image update never removes them. When the same extension id exists in both places, the higher version wins, and on equal versions the uploaded one wins.

Redeploying an extension stops the old process before the new one starts, so the extension is briefly unavailable. A redeploy that fails restores the previous version.

## What to back up

Back up the two volumes: the database holds every player's data, and `exoforge_uploads` holds the extensions you deployed. Run `pg_dump` against `exoforge_prod` for the database.

> [!NOTE]
> A table you declared `SchemaVersioningMode.Manual` is changed only by your own SQL files, applied with `exo db migrate <extension>`. Run that as a deliberate release step, before the new extension version is pushed.

## Settings and tables of the standard extensions

Generated from the code; the Developer Guide does not show these because they are the operator's, not the game developer's.

| Extension | Environment variables | Application config | Tables it creates |
|---|---|---|---|
| `exoforge_std_lldb` | `DATABASE_URL`, `EXOFORGE_DB_POOL_SIZE`, `EXOFORGE_DB_POOL_SIZES`, `EXOFORGE_DB_ROLE_SECRET` | `:schema_lock_timeout` | - |
| `exoforge_std_database` | - | - | - |
| `exoforge_std_resources` | `EXOFORGE_SCHEMA_CHANGE_MODE` | - | - |
| `exoforge_std_auth` | `EXOFORGE_ADMIN_EMAIL`, `EXOFORGE_ADMIN_PASSWORD`, `EXOFORGE_STUDIO_EMAIL`, `EXOFORGE_STUDIO_PASSWORD` | - | - |
| `exoforge_std_player_data` | - | - | `player_kv`, `players` |
| `exoforge_std_ws` | - | - | - |
| `exoforge_std_http` | - | - | - |
| `exoforge_std_transport` | - | - | - |
| `exoforge_std_versioning` | - | `:max_active_versions` | `game_versions` |
| `exoforge_std_cron` | - | - | - |
| `exoforge_std_file_bucket` | - | `:public_buckets`, `:sdk_dist_dir`, `:storage_dir`, `:url_secret` | - |
| `exoforge_std_metering` | - | - | `usage_actions`, `usage_plugins` |
| `exoforge_std_observability` | `EXOFORGE_DATA_DIR`, `EXOFORGE_EVENT_ARCHIVE_DIR`, `EXOFORGE_EVENT_HOT_DAYS` | - | - |
| `exoforge_std_extension_manager` | `EXOFORGE_DATA_DIR`, `EXOFORGE_TARGET_RID`, `EXTENSIONS_PATH`, `UPLOADED_EXTENSIONS_PATH` | `:upload_dir` | - |
| `exoforge_std_docs` | - | - | - |
| `exoforge_std_dashboard` | `EXOFORGE_ADMIN_EMAIL` | - | - |
| `exoforge_std_dashboard_views` | - | - | - |
