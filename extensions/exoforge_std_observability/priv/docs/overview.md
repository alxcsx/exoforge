---
nav: Overview
summary: Event history, request timelines, failure groups and the live tail, with an archive and .
---
# Observability

Event history, request timelines, failure groups and the live tail, with an archive and retention.

## Actions

| Action | Scope | Takes | What it does |
|---|---|---|---|
| `recent_events` | `studio` | `limit` | The most recent cluster events, newest first. |
| `error_groups` | `studio` | `service`, `action`, `caller`, `rid`, `limit` | Failures grouped by fingerprint: counts, first/last seen, callers, and a sample request. |
| `capture` | `studio` | `kind`, `value`, `seconds` | Starts a deep capture for one player, one action, or the whole cluster, for a few minutes. |
| `captures` | `studio` | - | The active deep captures, with their remaining seconds. |
| `stop_capture` | `studio` | `kind`, `value` | Stops one capture (or every capture when kind is global and the value is blank). |
| `replay` | `studio` | `id` | Replays a captured invocation's full request as the caller who made it. |
| `health` | `studio` | `limit` | Per-action health: 30-minute rates, lifetime p50/p95, and what needs attention. |
| `events` | `studio` | `rid`, `player`, `event`, `status`, `since_ms`, `until_ms`, `limit`, `offset` | One page of stored events, filtered; ranges older than the hot window come from the archive. |
| `timeline` | `studio` | `rid`, `player`, `since_ms`, `limit` | One request's timeline (or one caller's recent activity): calls, events, logs and failures. |
| `clear_events` | `studio` | - | Drops the in-memory ring and the persisted event history. |
| `purge_events` | `admin` | `origin` | Drops one caller's hot events (account deletion); archived files are left untouched. |

## Events

It declares no events.

## Settings

- Environment variable `EXOFORGE_DATA_DIR`
- Environment variable `EXOFORGE_EVENT_ARCHIVE_DIR`
- Environment variable `EXOFORGE_EVENT_HOT_DAYS`

## Data

- Table `does`
