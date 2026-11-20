---
nav: Overview
summary: Runs the schedules declared with `[ExoCron]` and lets the Studio list and trigger them.
---
# Cron

Runs the schedules declared with `[ExoCron]` and lets the Studio list and trigger them.

## Actions

| Action | Scope | Takes | What it does |
|---|---|---|---|
| `status` | `studio` | - | Returns status and count of active cron jobs. |
| `list_jobs` | `studio` | - | Lists all scheduled cron jobs. |
| `trigger_job` | `studio` | `job_id` | Manually triggers a scheduled job by its name or id. |

## Events

It declares no events.

## Settings

It reads no settings.

## Data

It creates no tables of its own.
