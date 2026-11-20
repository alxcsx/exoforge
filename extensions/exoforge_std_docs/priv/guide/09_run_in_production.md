---
nav: Run in production
group: Operate
icon: globe
summary: The stack, the settings to change, and what to back up.
---
# Run in Production

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
| `EXOFORGE_SCHEMA_CHANGE_MODE` | `refuse` | What an unsafe change to a typed table does. `refuse` fails that extension alone and says where; `reset` drops and rebuilds the table and loses its rows. Keep `refuse` in production. See [Versions & Migrations](guide:04_versions_and_migrations). |
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
