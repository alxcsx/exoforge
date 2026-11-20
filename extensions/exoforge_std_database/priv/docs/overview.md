---
nav: Overview
summary: The helper every extension uses for `Get`, `Put`, `All`, `Delete`, `Query` and `Execute.
---
# Database

The helper every extension uses for `Get`, `Put`, `All`, `Delete`, `Query` and `Execute` on its own isolated schema. It sits on top of `lldb`.

## Actions

| Action | Scope | Takes | What it does |
|---|---|---|---|
| `execute` | `server` | `operation`, `arguments`, `plugin` | Executes a driver-agnostic query or data operation. |
| `table_columns` | `server` | `table`, `plugin` | Lists the columns of a table in a plugin's isolated database (M33 Fix 9). |

## Events

It declares no events.

## Settings

It reads no settings.

## Data

It creates no tables of its own.
