---
nav: Auth & scopes
group: Build
icon: lock
summary: Who may call what, how tokens work, and how to give a server access.
---
# Authentication & Scopes

Every call to an action carries the identity of its caller. The `auth` extension decides who that is, and each action declares the role it needs.

---

## Roles and scopes

A caller's role is a rank, and an action's scope is the lowest rank allowed to run it:

| Scope | Who may call |
|---|---|
| `guest` | Anyone, signed in or not. |
| `player` | A signed-in player and above. |
| `studio` | Studio staff and above. |
| `admin` | The administrator only. |
| `service` | Trusted servers (a game server, a CI job), and the administrator. |
| `global` | No particular role is required. |
| `server` | Nobody outside the server: no transport can reach it, only calls from inside. |

The ladder is `admin` above `studio` above `player` above `guest`: a studio account can run `studio`, `player` and `global` actions, a player can run `player` and `global`. Set the scope on the action: `[ExoAction(Scope = "studio")]`. An action with no scope needs a `player`.

## Tokens

A credential looks like `exo_<kind>_<id>.<secret>`. The secret is shown once and only its hash is stored.

| Kind | For | Lifetime |
|---|---|---|
| `ses` | A player's access token. | About an hour. |
| `ref` | The refresh token, single use. | About 30 days. |
| `svc` | A service or developer. | 90 days unless you say otherwise. |

A client never handles this. `ExoforgeSDK.Auth.LoginAnonymously()` signs in and caches the tokens, and when a call answers `token_expired` the client renews the pair and retries once. Presenting a refresh token twice revokes the whole session, so a stolen refresh token ends the family it came from.

## Giving a server access

Servers and developers are ordinary accounts with a role:

```
exo user create build-bot@studio.example --role service
exo user token <id>
exo user token <id> --expires 30d
exo user tokens <id>
exo user token --revoke <token_id>
```

Tokens are listed and revoked by id, never by secret, and changing an account's role reaches every token it holds. The same actions are in the Studio under **Users**.

## The administrator

The `admin` account is set up by whoever runs the server, and every other account is created from it. Nobody can delete, re-scope or re-password the administrator through user actions.

> [!NOTE]
> Scripts that create test accounts should pass `disposable: true`, so `auth.purge_disposable` can remove exactly those.
