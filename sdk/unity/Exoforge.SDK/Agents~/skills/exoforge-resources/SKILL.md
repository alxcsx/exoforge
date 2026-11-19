---
name: exoforge-resources
description: Model [ExoResource] entities and manage persisted cluster database records and migrations using the Exoforge CLI.
---

# Exoforge Resource & Data Management

This skill covers defining persisted entities in C# extensions and performing schema migrations and CRUD operations using `exo resource`.

## 1. Modeling Resources in C#

In Exoforge, data schemas can be declared directly in extension assemblies using the `[ExoResource]` attribute. The cluster registers these schemas and provisions underlying tables:

```csharp
using System;
using Exoforge.Plugin.SDK;

namespace Exoforge.Extensions;

[ExoResource("leaderboard_entries", PrimaryKey = "player_id")]
public record LeaderboardEntry(
    string PlayerId,
    int Score,
    int Rank,
    DateTime UpdatedAt
);

[ExoSingletonResource("season_config")]
public record SeasonConfig(
    int SeasonNumber,
    DateTime StartsAt,
    DateTime EndsAt,
    int Multiplier
);
```

- `[ExoResource("table_name", PrimaryKey = "id")]`: Defines a multi-row table schema (emits `schema_hash` and per-column `storage`, `primary_key`, `unique`, `indexed`, `nullable`, `default`, `choices`, `foreign_key`, `references` in `manifest.json`).
- `[ExoColumn(PrimaryKey = true, Unique = true, Indexed = true)]`: Configures per-column constraints and indexes on resource properties.
- `[ExoSingletonResource("table_name")]`: Defines a singleton configuration resource accessible via `Exo.Database.First<T>()`.

## 2. Reconciling Database Schemas (Migrate)

Apply and reconcile resource schema definitions with the cluster database:

```bash
./exo resource migrate --json
```

This verifies existing table structures, applies column additions, and creates required indices without manual SQL scripts.

## 3. Inspecting Tables

List all registered resource tables across all active services:

```bash
./exo resource tables --json
```

Output includes table names, primary keys, and schema definitions.

## 4. Querying and Listing Records

### Paginated Listing
List records from a specific table with optional limits, offsets, and search filters:

```bash
./exo resource list leaderboard_entries --limit 25 --offset 0 --json
```

### Searching Records
Filter records containing matching terms:

```bash
./exo resource list leaderboard_entries --search "player_100" --limit 10 --json
```

### Retrieving by Primary Key
Fetch a single record by its primary key ID:

```bash
./exo resource get leaderboard_entries player_100 --json
```

## 5. Inserting and Modifying Records

### Creating a Record
Insert a new record into a resource table:

```bash
./exo resource create leaderboard_entries --data '{"PlayerId":"player_100","Score":1250,"Rank":1,"UpdatedAt":"2026-11-16T12:00:00Z"}' --json
```

### Updating a Record
Update existing fields of a record by primary key:

```bash
./exo resource update leaderboard_entries player_100 --data '{"Score":1500,"Rank":1}' --json
```

### Upserting a Record
Insert a record or update it if the primary key already exists:

```bash
./exo resource upsert leaderboard_entries --data '{"PlayerId":"player_100","Score":1600,"Rank":1,"UpdatedAt":"2026-11-16T12:30:00Z"}' --json
```

## 6. Deleting Records

### Deleting a Single Record
Delete a specific row by primary key:

```bash
./exo resource delete leaderboard_entries player_100 --json
```

### Clearing a Table
Truncate all rows in a resource table (requires `--yes` to confirm):

```bash
./exo resource clear leaderboard_entries --yes --json
```
