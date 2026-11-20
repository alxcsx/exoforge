---
nav: Overview
summary: The Producer Studio web app (port 4005), hosting the Overview, the extension inspector a.
---
# Studio

The Producer Studio web app (port 4005), hosting the Overview, the extension inspector and the views other extensions contribute.

## Actions

| Action | Scope | Takes | What it does |
|---|---|---|---|
| `get_dashboard_mount` | `server` | `view_id` | Retrieves dashboard mount specification: {:live, Module} | {:hook, config} | {:iframe, config} |
| `get_dashboard_data` | `server` | `view_id` | Retrieves data payload for hydrating the dashboard view. |
| `get_project_metadata` | `studio` | - | Retrieves global project metadata. |
| `update_project_metadata` | `admin` | `project_name`, `studio_name`, `description`, `website_url`, `custom` | Updates global project metadata. |

## Events

| Event | Payload | What it means |
|---|---|---|
| `project_metadata_updated` | `metadata` | Broadcast when project metadata is updated. |

## Settings

- Environment variable `EXOFORGE_ADMIN_EMAIL`

## Data

It creates no tables of its own.
