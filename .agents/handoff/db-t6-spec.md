# T6 v2: versioned resources, ALTER-first migrations, one file each

Rules (user, 2026-11-19): (1) use ALTER TABLE for every migration case PostgreSQL can express; where it cannot, the deploy is blocked unless a
migration FUNCTION exists; (2) resources are versioned and that identifies a migration; (3) each migration lives in its own file; (4) existing data is
resettable, so the legacy/bag/quarantine machinery of v1 is parked.

## Resource version
`[ExoResource("items", Version = 2)]` (default 1). The manifest carries `version`; `_exo_schema` records the version applied to each table.
A new table starts at the manifest's version. Live version < manifest version means a chain of migrations must lead from one to the other.

## A migration: static, in its own file, nothing runs at runtime
```csharp
// Migrations/Items/V1ToV2.cs
[ExoMigration(typeof(Item), From = 1, To = 2)]      // To must be From + 1
[Rename("nm", "name")]                               // ALTER TABLE .. RENAME COLUMN
[Convert("price", ExoType.Decimal)]                  // ALTER COLUMN .. TYPE numeric USING price::numeric  (only casts PostgreSQL defines)
[Fill("rarity", "common")]                           // ADD COLUMN .. NOT NULL DEFAULT 'common'  (instant on PG >= 11)
[Drop("legacy_flag")]                                // DROP COLUMN
public static class ItemsV2 { }
```
Attributes are read by the generator (Roslyn), so the manifest lists every migration and its ordered ops before the extension runs, and the server applies them as
plain ALTERs. Other ops: `SetNotNull(col, Fill = x)` (UPDATE then SET NOT NULL), `Index`, `Unique`.
Where the ALTER cannot do it (a text like "12,5 USD" to a decimal), the migration needs a C# FUNCTION (row level, runs in the extension; a later slice): until one exists, that change cannot be deployed.

## The deploy gate (runs when the extension is uploaded or booted; failing it fails only that deploy)
Compare the live table with the manifest:
- additive and safe (new table, new nullable column, new index, safe widening): applied automatically, no version bump needed (as T2 does today);
- anything else: needs `manifest.version > live.version` AND a migration chain live -> manifest. The chain's ops are applied to the live table in ONE transaction
  (PostgreSQL DDL is transactional); then the result is compared with the manifest (the verify gate); any remaining difference rolls everything back and blocks the deploy,
  naming what is still different. No chain: the error names the change, the file to add and the attribute to put on it.
- version equal but schema different and unsafe: "bump Version and add a migration"; version LOWER than live: refused (an older server over a newer schema);
- `EXOFORGE_SCHEMA_CHANGE_MODE=reset` still rebuilds the table in development.
Locks: ALTER takes ACCESS EXCLUSIVE and a type change rewrites the table (accepted for now). `lock_timeout` makes a blocked ALTER fail the deploy instead of queueing every
query behind it; the message says to retry at low traffic. `exo db plan` (later) will say which steps rewrite.

## Files and tooling
One migration class per file, `Migrations/<Resource>/V<from>To<to>.cs` by convention (found by attribute, anywhere in the project). Build errors: duplicate (resource, From);
`To != From + 1`; an op naming a column the resource does not have in its CURRENT shape is NOT checkable at build (no history), so the gate catches it at deploy.
`exo db migration new Item --from 1 --to 2` scaffolds the file (from `plan_schema` when a cluster is reachable).

## Game clients on several versions at once (the real constraint)
Clients never touch tables; they call typed actions. So a table migration breaks an old client only if it changes what an ACTION returns or accepts. The thing to version is the action contract.
- Supabase: PostgREST exposes tables as the API (schema == API), so they rely on expand/contract and versioned schemas/views (PostgREST `Accept-Profile` picks the schema), versioned
  Edge Function routes, and tools like pgroll (old and new schema served at once). Nothing retires old apps for you.
- PlayFab: CloudScript REVISIONS: each client call can pin Live / Latest / a specific revision, so old clients keep running old server logic; Title/Player data is schemaless JSON migrated on read.
- Nakama, Firebase, UGS Cloud Save: JSON documents, additive changes, migrate-on-read, and a minimum client version enforced by a remote config or an RPC.
Ours: (1) action revisions: `[ExoAction(Since = 1, Until = 3)]` or `GetItemV1/V2` in their own files with adapters between the old DTO and the current storage; the client SDK sends its contract
level in the handshake and the server dispatches the matching revision. (2) a per-title `min_client_version` (warn, then block) so retiring a version is a decision, and active client
versions are visible in observability, which tells you when an `Until` can be reached. (3) tables are then free to change; the deprecation window applies to action revisions.
(4) No dual-write / expand-contract is needed on one server instance. Running two server code versions side by side (PlayFab-style) is possible later, not now.

## Slices
S1 C# SDK + generator: `Version`, `[ExoMigration]` + op attributes, manifest `version` and `migrations`, build diagnostics. S2 driver: ledger `version`, apply a chain in one transaction, verify, `lock_timeout`.
S3 resource_store: pass versions and migrations, deploy-gate errors with the file to add. S4 end-to-end on the sample extension (bump, rename, deploy blocked without the file).
Later: migration functions, `exo db migration new`, action revisions + client version handshake + `min_client_version`.
