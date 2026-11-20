# wt/tokens: expiring, revocable, hashed tokens  (worktree /Users/alexcs/projects/exoforge-wt/tokens)
Read wt-common.md first. Today (extensions/exoforge_std_auth/lib/exoforge/std/auth.ex): a token is 24 random
bytes stored in plaintext (id = token), never expires, scopes copied into each row (rewritten on role change
at ~L598), one more row per login/`exo user token`, no per-token revoke; issue_token accepts any user_id.
Want:
1. Format `exo_<kind>_<token_id>.<secret>` (kind: ses = player access, ref = refresh, svc = service).
   Table tokens(token_id, user_id, kind, secret_hash, expires_at, created_at, last_used_at, revoked_at,
   family_id, device_id). Verify = lookup token_id, constant-time compare sha256(secret); cache as today.
2. Scopes come from the account (cached, flushed on role change/delete as today), not the token row;
   drop the per-token scope rewrite.
3. Players: access token ~1h + rotating refresh token ~30d (configurable). New action `auth.refresh`
   (refresh token -> new pair). Reusing a rotated refresh token revokes its whole family. Expired access
   -> error code `token_expired`. A new login for the same device replaces that device's session;
   cap sessions per account (config, e.g. 10, evict oldest).
4. Service tokens: no refresh, expiry default 90d, `exo user token <id> [--expires 30d]`,
   `exo user tokens <id>` (list: token_id, kind, created, last_used, expires), `exo user token --revoke
   <token_id>`. Matching auth actions are admin scope. Studio Users view: list + revoke per user.
5. issue_token refuses a user_id with no account (`unknown_user`). Cron (exoforge_std_cron) purges expired
   and revoked rows.
6. Migration: existing plaintext rows are hashed in place (whole old token = secret, kind legacy) and get a
   30-day expiry; nothing is invalidated on upgrade.
7. Client: sdk/csharp/Exoforge.Client + sdk/unity/Exoforge.SDK/Runtime (ExoforgeAuth/ExoTokenStore) store the
   refresh token, call auth.refresh on `token_expired` and retry the call once; WS reconnects with the new
   token. Keep the ExoClient.cs edit small and local (another branch edits its error parsing).
Tests: auth_test (format, hash at rest, expiry, refresh rotation, family revoke on reuse, device replace,
cap, revoke, unknown_user, migration, role change applies without rewriting tokens), Management tests for
the CLI commands, Client test for refresh-and-retry.
