---
nav: Overview
summary: Upload, reload and removal of extensions, and the export of their manifests.
---
# Extension manager

Upload, reload and removal of extensions, and the export of their manifests. A failed redeploy is rolled back to the previous version.

## Actions

| Action | Scope | Takes | What it does |
|---|---|---|---|
| `list_extensions` | `studio` | - | Lists all registered extensions with their metadata and contracts. |
| `get_extension` | `studio` | `id` | Retrieves details and contract metadata for a single extension. |
| `get_system_info` | `studio` | - | Retrieves runtime node health, memory, and cluster stats. |
| `upload_extension` | `admin` | `name`, `binary`, `manifest` | Uploads and installs a new extension binary. |
| `remove_extension` | `admin` | `id` | Removes an installed extension. |
| `restart_system` | `admin` | - | Triggers a system re-index and reload of all extensions. |
| `logs` | `studio` | `id`, `limit` | Returns the most recent log lines an extension emitted. |
| `reload_extension` | `admin` | `id` | Re-boots an installed extension from its staged files, without re-uploading it. |
| `export_extension_info` | `studio` | - | Exports the complete catalog of extensions and contracts for external tools (CLI/Unity). |
| `csharp_attributes` | `studio` | - | Exports C# companion attributes and types provided by loaded extensions. |

## Events

It declares no events.

## Settings

- Environment variable `EXOFORGE_DATA_DIR`
- Environment variable `EXOFORGE_TARGET_RID`
- Environment variable `EXTENSIONS_PATH`
- Environment variable `UPLOADED_EXTENSIONS_PATH`
- `config :exoforge_std_extension_manager, :upload_dir`

## Data

It creates no tables of its own.
