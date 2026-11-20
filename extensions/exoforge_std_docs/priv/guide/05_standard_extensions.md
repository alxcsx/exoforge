---
nav: Standard extensions
group: Build
icon: box
summary: What ships with the server, and the Studio.
---
# Standard Extensions & the Studio

Everything above the kernel is an extension, including what ships with the server. The standard extensions below are **builtin**: they live in the server image, they are not installed on a developer's machine, and your code reaches them through their service contracts (`ExoServices.PlayerData`, `Exo.Services.Auth`, ...). A studio may replace or remove any of them with its own implementation of the same contract.

---

## What ships with the server

| Extension | Service | What it is for |
|---|---|---|
| `exoforge_std_lldb` | `lldb` | The storage driver layer: connections, pools, schemas, roles, DDL, the migration runner. Engine specific; Postgres is the supported engine. |
| `exoforge_std_database` | `database` | The helper your extensions use for `Get`, `Put`, `All`, `Delete`, `Query` and `Execute` on their own isolated schema. |
| `exoforge_std_resources` | `resource_store` | Turns `[ExoResource]` declarations into tables, reconciles them on deploy, and serves the resource browser in the Studio. |
| `exoforge_std_auth` | `auth` | Accounts, sessions (an access token plus a single-use refresh token), roles and scopes. |
| `exoforge_std_player_data` | `player_data` | The canonical player profile and key-value store, with lifecycle events. |
| `exoforge_std_ws` | `ws` | The realtime transport (WebSocket): actions and event subscriptions. |
| `exoforge_std_http` | `http` | The REST transport , with OpenAPI routes derived from the service contracts. |
| `exoforge_std_transport` | `transport` | The shared gateway behind `ws` and `http`: framing, dispatch, and the game-version check. |
| `exoforge_std_versioning` | `versioning` | Game versions (`dev`, `live`, `outdated`, `blocked`) and the extension version each one locks. See [Versions & Migrations](guide:04_versions_and_migrations). |
| `exoforge_std_cron` | `cron` | Runs the `[ExoCron]` schedules. |
| `exoforge_std_file_bucket` | `file_bucket` | Binary assets with metadata. A bucket is `public` or `private`; private buckets need staff access or a signed URL. |
| `exoforge_std_metering` | `metering` | Usage per extension and action, persisted on the instance. |
| `exoforge_std_observability` | `observability` | Event history, request timelines, failure groups and live tail. |
| `exoforge_std_extension_manager` | `extension_manager` | Upload, reload and export of extensions; rolls back a failed redeploy. |
| `exoforge_std_docs` | `docs` | This guide, the live API catalog and the PDF export. |
| `exoforge_std_dashboard`, `exoforge_std_dashboard_views` | `dashboard`, `dashboard_view` | The Producer Studio and the views extensions contribute to it. |

Each standard extension documents itself: open **Extensions** in the sidebar for its actions, events, settings and data.

### How they depend on each other

![The standard extensions and what each is built on](diagram:extension-dependencies)

An extension of yours declares the services it calls with `[ExoDependency]`; the server starts everything in dependency order.

## The Producer Studio

The Studio is a web app served by the `dashboard` extension and is where a producer or designer works without touching code. Its top bar has **Overview** and **Extensions**, and you can pin up to four extension views next to them. Every other screen is a view that an extension contributes, which is why replacing an extension also replaces its screen.

| Screen | Comes from | Use it to |
|---|---|---|
| **Overview** | `dashboard` | See server health, the actions that need attention (error rate, p95 latency) and recent activity. |
| **Extensions** | `extension_manager` | Deploy, reload or remove an extension, and open its inspector: actions, events, resources, contracts, logs and docs, plus the game versions that lock it. |
| **Users** | `auth` | Create accounts and tokens, assign roles, list and revoke sessions. |
| **Data** | `resources` | Lists every `[ExoResource]` table with its owner and row count; **Browse rows** opens it to search, edit and export. `[ExoColumn]` decides labels, sorting, filters and input widgets. The same link is in each extension's inspector, under *Resources*. |
| **Files** | `file_bucket` | Upload to buckets and switch a bucket between public and private. |
| **Timeline and health** | `observability` | Paste a request id (`rid`) to see the calls, events, queries and logs of one request; turn on deep capture for one player and replay a captured request. |
| **Developer Guide** | `docs` | This guide, plus the live catalog of every service and action registered on this server. |

The `admin` account is an ordinary account set up by whoever runs the server; developers and trusted servers get their own accounts with a role (`exo user create <email> --role service`, then `exo user token <id>`).

> [!NOTE]
> Test accounts that scripts create should say so with `disposable: true`, so `auth.purge_disposable` can remove exactly those and never a real player.
