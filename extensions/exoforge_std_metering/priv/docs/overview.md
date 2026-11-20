---
nav: Overview
summary: Usage per extension and action (invocations, errors, latency, bytes), persisted on the i.
---
# Metering

Usage per extension and action (invocations, errors, latency, bytes), persisted on the instance.

## Actions

| Action | Scope | Takes | What it does |
|---|---|---|---|
| `usage` | `studio` | `plugin_id`, `since` | Rolls up persisted usage per plugin and action for this title. |

## Events

It declares no events.

## Settings

It reads no settings.

## Data

- Table `usage_actions`
- Table `usage_plugins`
