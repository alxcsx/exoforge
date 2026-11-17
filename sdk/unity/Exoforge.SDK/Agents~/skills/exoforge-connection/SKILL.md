---
name: exoforge-connection
description: Inspect and configure cluster environments, connection credentials, contract discovery, ad-hoc RPC testing, and connectivity diagnostics.
---

# Exoforge Connection & Environment Management

This skill covers managing target environments, authenticating with Exoforge clusters, inspecting deployed contracts, invoking ad-hoc actions, and resolving connection issues.

## 1. Environment Management

Exoforge workspaces in `Exoforge/exoforge.json` support multiple target environments (e.g., `local`, `staging`, `production`).

### Listing Environments
```bash
./exo env list --json
```

### Adding an Environment
Register a new environment with its WebSocket and HTTP REST endpoints:

```bash
./exo env add staging --ws wss://staging.game.internal:4000 --http https://staging.game.internal:4001 --json
```

### Switching Active Environment
Set the current environment used by subsequent CLI commands:

```bash
./exo env use staging --json
```

## 2. Authentication & Connection Setup

Connect to a cluster, authenticate administrator or developer credentials, and save the session token:

```bash
./exo connect --ws ws://localhost:4000 --http http://localhost:4001 --email admin@example.com --password admin_password --save --json
```

The `--save` flag writes the authenticated token and endpoints into `Exoforge/exoforge.json` under the active environment.

## 3. Verifying Cluster Status

Check the health and responsiveness of the active cluster:

```bash
./exo status --json
```

Output contains:
- `reachable`: Boolean indicating whether the cluster is accepting connections.
- `latency_ms`: Roundtrip ping duration.
- `version`: Server release version.
- `active_extensions`: Count and list of loaded extension processes.

## 4. Contract Discovery

List all active service contracts, exposed actions, parameter schemas, and published event topics:

```bash
./exo contracts --json
```

Use this command to discover:
- Available service identifiers (e.g., `auth`, `player_data`, `daily_rewards`).
- Action names and parameter expectations.
- Required authorization scopes (`player`, `admin`, or public).

## 5. Ad-Hoc Action Invocation (`exo call`)

Execute an RPC action directly from the terminal to verify logic before or during client integration:

```bash
./exo call auth register --data '{"email":"test@game.com","password":"secretpassword123"}' --json
```

Example with authenticated player action:
```bash
./exo call daily_rewards claim_reward --data '{"streakDay":1}' --json
```

The CLI automatically supplies the active session token stored in `exoforge.json`.

## 6. Users and service accounts

Accounts are ordinary user accounts that an admin manages with the saved admin session of the active environment (`exo connect --save`). The same actions back the Studio's users view.

```bash
./exo user list --search arcade --limit 20
./exo user create dev@studio.local --password '<password>' --name "Dev" --role studio
./exo user role <user_id> --role player
./exo user token <user_id>
./exo user delete <user_id>
```

Roles: `player`, `studio`, `service`, `admin`. `--json` prints the raw reply; without it `list` prints one line per account, and `token` prints only the token on stdout.

A token is a credential. It acts as the account until the account is deleted, and `exo user role` changes the scopes of tokens already issued. Keep tokens out of version control.

### A service account for a trusted game server

A trusted game server (the one that reports kills, hits or purchases) calls actions declared `Scope = "service"`. Players cannot call them: a player token gets `forbidden_scope`. The server gets its own account, never a player's or an admin's:

```bash
./exo user create game-server@studio.local --password '<password>' --name "Game server" --role service
./exo user list --search game-server        # note the user id
./exo user token <user_id> > Exoforge/game-server.token
```

Add `Exoforge/game-server.token` to `.gitignore`, read it only from server-side code or Editor-only tooling (never from `Assets/` and never in a build), and delete the account with `exo user delete <user_id>` when the server is retired.

## 7. Common Troubleshooting Scenarios

### Cluster Offline or Unreachable
- **Symptom**: `exo status` returns connection refused or timeout errors.
- **Diagnostic Steps**:
  1. Verify the cluster process or Docker container is running.
  2. Verify endpoint URLs in `Exoforge/exoforge.json` (`ws` on port 4000, `http` on port 4001 by default).
  3. Check network firewalls or container port mappings (`-p 4000:4000 -p 4001:4001`).

### Authentication Token Expired or Invalid
- **Symptom**: `exo call` or `exo extension push` fails with `unauthorized` or `invalid_token`.
- **Resolution**:
  1. Re-run `exo connect` with valid credentials:
     ```bash
     ./exo connect --email <staff_email> --password <password> --save --json
     ```
  2. Verify that the user account exists in the cluster database.

### Desynchronized Client Stubs
- **Symptom**: Unity compiler reports missing methods or mismatched parameter signatures when calling `ExoServices.<Service>`.
- **Resolution**:
  1. Confirm the updated extension is deployed:
     ```bash
     ./exo extension push <name> --json
     ```
  2. Regenerate Unity C# bindings:
     ```bash
     ./exo sync --json
     ```
  3. In the Unity Editor, trigger compilation or asset refresh (`Ctrl+R` / `Cmd+R` or **Exoforge ▸ Repair & Regenerate Client**).
