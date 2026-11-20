---
nav: Versions & migrations
group: Build
icon: archive
summary: Change tables and code while players are online.
---
# Versions & Migrations

How a game keeps working while its extensions and its data change: what a version means in Exoforge, what Exoforge does for you when you change a table, and what you declare yourself when a change cannot be automatic.

---

## Two kinds of version

| | What it is | Who sets it |
|---|---|---|
| **Extension version** | The `Version` of an `[ExoService]` / `[ExoExtension]` (`"1.4.0"`). The server always runs the **latest** build of each extension: there is one process per extension, never two side by side. | You, in the attribute. |
| **Game version** | A release of your game (`"1.3"`), the one the player's client reports. Each game version **locks** the extension version it was built against, for example `{ "achievements": "1.2.0" }`. | You, in the `versioning` extension (Studio). |

The extension version describes *the data and the code on the server*. The game version describes *which clients are still out there*. The rule that ties them together: the server may change anything for the latest extension, but it must not break a game version that is still being served.

![Game versions lock an extension version; one process serves them all and rows carry the version that wrote them](diagram:versions-locks)

## What Exoforge does for you

(The attributes used below are listed in the [attribute reference](guide:03_csharp_attributes#exoresource-exocolumn).)

Every table of a typed resource (an `[ExoResource]` whose columns declare their storage) carries a hidden column `_v`: the extension version the row was last written under. Reads return it, writes set it, and you never declare it.

When you deploy a new extension version, Exoforge compares your declaration with the live table:

| Your change | What happens |
|---|---|
| Add a nullable column, add a column with a default, widen a type | Applied on deploy, in one transaction. |
| Remove a property from the record | The column is **retired**, not dropped: no SQL runs and old clients that still read it keep working. |
| Rename a column, narrow a type, add `NOT NULL` without a default, drop a column | **Refused** until you declare it (next section). The deploy of that extension fails alone and the message names the table, the column and the file to write. |

A deploy never loses data silently. A development server can be set to rebuild the table instead, which loses its rows; a production server never does.

## Declaring a change Exoforge cannot guess

A migration leads *to* an extension version. Put each one in its own file, next to the record it changes:

```csharp
// Migrations/V1_2.cs  -  applied on the deploy that reaches 1.2.0
[ExoMigration(typeof(AchievementDef), To = "1.2.0")]
[ExoRename("trigger", "event_name")]
[ExoFill("category", "general")]
public static class V1_2 { }
```

| Operation | Does |
|---|---|
| `[ExoRename(from, to)]` | Renames a column. |
| `[ExoConvert(column, ExoType.X)]` | Changes a column's type. |
| `[ExoFill(column, value)]` | Adds a column and gives every existing row `value`. |
| `[ExoSetNotNull(column)]` | Makes a column `NOT NULL`, filling rows that have none first. |
| `[ExoDrop(column)]` | Removes a column and its data (see the gate below). |

Migrations run in order of `To`, all inside one transaction, and the result is verified: if the table still does not match the declaration afterwards, everything rolls back.

### The gate on destructive changes

`[ExoDrop]` is refused while it could still hurt someone:

- any row is stamped with a version **below** the migration (the data has not caught up), or
- a game version that is still served locks the extension **below** the migration (that client still reads the column).

The message says which game versions and how many rows. If the `versioning` extension is installed but does not answer, the drop is refused too: the answer is unknown and a drop cannot be undone.

## Game versions and old clients

The client sends its game version when it signs in (Unity uses `Application.version`). The `versioning` extension keeps the list:

| Status | Meaning |
|---|---|
| `dev` | Pre-production. Its locks can still change (`versioning.set_locks`). |
| `live` | The current release. |
| `outdated` | Replaced, still served while players update. |
| `blocked` | Not served: the client gets `upgrade_required` (HTTP 426, WebSocket close 4001), the Unity client raises `OnUpgradeRequired`. |

At most three versions are not blocked (`max_active_versions`). Promoting a new one blocks the oldest `outdated`. With **no** game version registered, versioning is off and every client is served: you opt in by registering your first version.

## Advanced

<details>
<summary>Changing data per row, keeping old clients working, and tables you own</summary>

### When a row needs code: `[ExoRowMigration]`

Some changes are not an `ALTER`: splitting a field, recomputing a value. Write a static method that turns the old row into the new record:

```csharp
[ExoRowMigration(typeof(AchievementDef), To = "2.0.0")]
public static AchievementDef Up(JsonElement oldRow) =>
    new(oldRow.GetProperty("id").GetString()!, ...);
```

The SDK runs it the first time a row stamped below `2.0.0` is read (`Get`, `All`, `Query<T>`) and writes the result back once, guarded so two callers cannot both win. A background sweeper migrates the rows nobody reads, 100 every 2 seconds, so a later `[ExoDrop]` is not blocked by players who never return.

Do not use a declarative migration and a row migration for the same version.

### Keeping old clients working

Two things protect an old client from new data:

- **Action revisions.** Keep the old behavior under the same name with `[ExoAction("score", FromVersion = "2.0.0")]` on the new method. A caller whose game version locks the extension below `2.0.0` gets the previous method, everyone else the newest. Delete a revision once no served game version needs it.
- **`client_outdated`.** If a row has already been through a row migration that the caller's game version predates, the read answers `client_outdated` instead of returning a shape the old client cannot understand. The client raises the same `OnUpgradeRequired` path.

### Opting out: tables you own

```csharp
[ExoResource("orders", SchemaVersioningMode = SchemaVersioningMode.Manual)]
```

A `Manual` resource gets no `_v`, no automatic ALTERs, no gate. You write plain SQL files `migrations/0001_name.sql` and apply them with `exo db migrate <extension>`. At deploy Exoforge only checks that the table matches the record; a mismatch fails that extension alone and is never rebuilt, even in `reset` mode. Auto and Manual resources can sit side by side in one extension.

</details>

To add rules of your own around actions or data (an audit trail, a per-version rule), write a [plug](guide:03_csharp_attributes#plugs).

> [!NOTE]
> The versioning extension, row stamps and migrations apply to the extensions **you** write. The standard extensions that ship with the server (`auth`, `player_data`, `metering`, ...) are versioned by the server release instead and are `Manual`: their tables change with their own SQL migrations.
