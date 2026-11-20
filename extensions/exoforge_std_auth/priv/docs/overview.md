---
nav: Overview
summary: Accounts, sessions (an access token plus a single-use refresh token), roles and scopes.
---
# Auth

Accounts, sessions (an access token plus a single-use refresh token), roles and scopes. It also reconciles the `admin` account at every boot.

## Actions

| Action | Scope | Takes | What it does |
|---|---|---|---|
| `authenticate` | `global` | `token` | Authenticates a client credential or token. |
| `refresh` | `global` | `token` | Exchanges a refresh token for a fresh access/refresh pair. |
| `login` | `global` | `email`, `password` | Authenticates an account with email and password. |
| `verify_scope` | `global` | `required_scope`, `user_id`, `player_id` | Verifies whether a player or user has the required authorization scope. |
| `register` | `global` | `user_id`, `player_id`, `name`, `email`, `password`, `scopes` | Registers a new user account and profile in both auth and player_data. |
| `create_player` | `global` | `user_id`, `player_id`, `name`, `email`, `password`, `scopes` | Creates a new player or user account with authentication credentials. |
| `anonymous` | `global` | `player_id`, `name` | Creates or resumes an anonymous player session. |
| `set_display_name` | `global` | `name`, `player_id` | Sets the signed-in player's display name. |
| `issue_token` | `admin` | `player_id`, `user_id`, `scopes`, `expires_in` | - |
| `list_tokens` | `admin` | `user_id`, `player_id` | Lists the tokens issued for an account: id, kind, creation, last use and expiry. |
| `revoke_token` | `admin` | `token_id` | Revokes a token (and the session it belongs to). |
| `purge_tokens` | `server` | - | Deletes expired and revoked token rows. Cron calls this. |
| `list_users` | `studio` | `query`, `limit` | Lists all registered user accounts and their assigned authorization scopes. |
| `reset_password` | `admin` | `password`, `user_id`, `player_id` | Resets the password for an existing account. |
| `update_user_roles` | `admin` | `user_id`, `player_id`, `scopes`, `role` | Updates authorization scopes/roles for a user account. |
| `delete_user` | `admin` | `user_id`, `player_id` | Deletes a user account and associated auth credentials. |
| `purge_disposable` | `studio` | `dry_run` | - |

## Events

It declares no events.

## Settings

- Environment variable `EXOFORGE_ADMIN_EMAIL`
- Environment variable `EXOFORGE_ADMIN_PASSWORD`
- Environment variable `EXOFORGE_STUDIO_EMAIL`
- Environment variable `EXOFORGE_STUDIO_PASSWORD`

## Data

It creates no tables of its own.
