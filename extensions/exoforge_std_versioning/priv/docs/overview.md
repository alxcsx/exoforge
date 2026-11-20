---
nav: Overview
summary: Game versions (`dev`, `live`, `outdated`, `blocked`, at most three not blocked) and the .
---
# Versioning

Game versions (`dev`, `live`, `outdated`, `blocked`, at most three not blocked) and the extension version each one locks.

## Actions

| Action | Scope | Takes | What it does |
|---|---|---|---|
| `register` | `studio` | `version`, `locks` | Registers a game version in `dev`, with the extension versions it locks. |
| `set_locks` | `studio` | `version`, `locks` | Changes the locks of a `dev` game version. Live, outdated and blocked versions are immutable. |
| `promote` | `studio` | `version` | Makes a `dev` game version live. The previous live one becomes `outdated`. |
| `block` | `studio` | `version` | Blocks a game version: its clients are told to upgrade. |
| `list` | `studio` | - | Lists game versions, newest first. |
| `resolve` | `player` | `version` | Status and extension locks of one game version, as a client reports it. |

## Events

It declares no events.

## Settings

- `config :exoforge_std_versioning, :max_active_versions`

## Data

- Table `game_versions`
