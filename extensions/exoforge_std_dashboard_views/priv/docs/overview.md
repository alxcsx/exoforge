---
nav: Overview
summary: The views that other standard extensions contribute to the Studio: users, extension mana.
---
# Studio views

The views that other standard extensions contribute to the Studio: users, extension manager, auth, player data and more. It has no actions of its own beyond the view contract.

## Actions

| Action | Scope | Takes | What it does |
|---|---|---|---|
| `resolve_view` | `server` | `id` | Resolves the LiveView component module for a given service or extension id. |
| `list_views` | `server` | - | Lists all registered custom dashboard view modules. |
| `get_dashboard_mount` | `server` | `view_id` | Retrieves dashboard mount specification: {:live, Module} | {:hook, config} | {:iframe, config} |
| `get_dashboard_data` | `server` | `view_id` | Retrieves data payload for hydrating the dashboard view. |

## Events

It declares no events.

## Settings

It reads no settings.

## Data

It creates no tables of its own.
