---
nav: Overview
summary: Turns `[ExoResource]` declarations into tables, reconciles them on deploy, and serves th.
---
# Resource store

Turns `[ExoResource]` declarations into tables, reconciles them on deploy, and serves the resource browser in the Studio.

## Actions

| Action | Scope | Takes | What it does |
|---|---|---|---|
| `migrate` | `studio` | `resource`, `extension` | Creates/updates the tables backing all declared resources (additive migrations). |
| `provision` | `studio` | `extension` | Provisioning step before an extension starts: makes the tables of its typed resources (those that declare column storage types). |
| `list` | `player` | `resource`, `filter`, `search`, `sort`, `limit`, `offset` | Lists rows for a resource with filtering, sorting, and pagination. |
| `get` | `player` | `resource`, `id`, `optional` | Fetches one row by primary key. |
| `create` | `studio` | `resource`, `attributes` | Creates a row. |
| `update` | `studio` | `resource`, `id`, `attributes` | Updates a row by primary key. |
| `delete` | `studio` | `resource`, `id` | Deletes a row by primary key. |
| `upsert` | `studio` | `resource`, `attributes` | Inserts or updates a row on conflict. |
| `clear` | `studio` | `resource` | Removes every row of a resource, table-backed or KV-backed, without dropping the table. |

## Events

It declares no events.

## Settings

- Environment variable `EXOFORGE_SCHEMA_CHANGE_MODE`

## Data

It creates no tables of its own.
