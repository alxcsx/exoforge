---
nav: Overview
summary: The canonical player profile and key-value store, with lifecycle events for creation and.
---
# Player data

The canonical player profile and key-value store, with lifecycle events for creation and deletion.

## Actions

| Action | Scope | Takes | What it does |
|---|---|---|---|
| `get_player` | `global` | `player_id` | Retrieves player profile record. |
| `create_player` | `global` | `player_id`, `user_id`, `profile` | Creates a player profile record, optionally linked to a user account. |
| `delete_player` | `admin` | `player_id` | Deletes a player profile record. |
| `retain_player` | `admin` | `player_id` | Unlinks user and marks player record as retained/orphaned for data retention policies. |
| `list_players` | `studio` | `filter`, `user_id`, `limit` | Lists all registered player profiles with optional filtering (all, valid, orphaned). |
| `update_player` | `global` | `player_id`, `data` | Updates player profile record. |
| `get_data` | `global` | `player_id`, `key` | Retrieves a fine-grained key-value JSON state entry for a player. |
| `set_data` | `global` | `player_id`, `key`, `value` | Sets a fine-grained key-value JSON state entry for a player. |
| `delete_data` | `global` | `player_id`, `key` | Deletes a fine-grained key-value JSON state entry for a player. |
| `get_all_data` | `global` | `player_id` | Retrieves all key-value state entries for a player as a map. |

## Events

| Event | Payload | What it means |
|---|---|---|
| `player_created` | `player_id`, `timestamp` | Emitted when a new player account is created. |
| `player_deleted` | `player_id`, `timestamp` | Emitted when a player account is deleted. |

## Settings

It reads no settings.

## Data

- Table `player_kv`
- Table `players`
