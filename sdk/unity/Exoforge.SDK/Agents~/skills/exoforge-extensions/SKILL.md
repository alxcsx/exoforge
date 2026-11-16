---
name: exoforge-extensions
description: Create, build, deploy, inspect, and remove server-side C# extensions in Unity projects using the Exoforge CLI.
---

# Exoforge Server-Side Extensions

This skill covers the end-to-end development cycle of server-side C# extensions for Exoforge from within a Unity project.

## 1. Extension Placement & Architecture

Server-side extensions reside in `Exoforge/extensions/<name>/` at the project root, **outside** of the Unity `Assets/` directory.

- Extensions target standard .NET (9.0+) and run as native backend processes on the Exoforge cluster.
- Extensions are never compiled or imported by Unity's AssetDatabase.
- Gameplay scripts in Unity interact with extensions through strongly-typed client stubs in `Assets/Exoforge/Generated/ExoforgeServices.g.cs`.

## 2. Scaffolding an Extension

Create a new extension project using `exo extension new`:

```bash
./exo extension new daily_rewards --template persistent --json
```

Available templates:
- `persistent`: Includes database access (`Exo.Database`) and state persistence patterns.
- `basic`: Minimal stateless RPC service with action handlers.
- `config`: Demonstrates singleton configuration resources (`[ExoSingletonResource]`).
- `events`: Demonstrates real-time event publishing (`Exo.Events.Publish`).

## 3. Authoring the Extension in C#

An extension is a standard C# project referencing `Exoforge.Plugin.SDK`. Actions and services are defined using attributes:

```csharp
using System;
using Exoforge.Plugin.SDK;

namespace Exoforge.Extensions;

[ExoService("daily_rewards", Category = "Gameplay", Title = "Daily Rewards")]
public partial class DailyRewardsExtension
{
    [ExoAction(Scope = "player")]
    public ClaimResult ClaimReward(int streakDay)
    {
        string playerId = Exo.Context.CallerPlayerId;
        if (string.IsNullOrEmpty(playerId))
        {
            throw new ExoActionException("unauthorized", "Valid player session is required.");
        }

        string key = $"claim:{playerId}";
        var existing = Exo.Database.Get<DailyClaimRecord>("daily_claims", key);
        if (existing != null && existing.ClaimedAt.Date == DateTime.UtcNow.Date)
        {
            throw new ExoActionException("already_claimed", "Daily reward already claimed today.");
        }

        int rewardAmount = streakDay * 50;
        var claim = new DailyClaimRecord(playerId, DateTime.UtcNow, rewardAmount);
        Exo.Database.Put("daily_claims", key, claim);

        Exo.Events.Publish("daily_rewards.claimed", new { playerId, amount = rewardAmount });

        return new ClaimResult(true, rewardAmount);
    }
}

public record DailyClaimRecord(string PlayerId, DateTime ClaimedAt, int Amount);
public record ClaimResult(bool Success, int Amount);
```

### Core SDK Attributes & APIs:
- `[ExoService("name")]`: Registers the class as a service contract with the host.
- `[ExoAction(Scope = "player")]`: Exposes a public method as an RPC action. `Scope = "player"` requires a valid authenticated player session; `Scope = "admin"` restricts access to administrator credentials; default or omitting scope permits public calls.
- `Exo.Database`: Typed storage interface (`Get<T>`, `Put`, `Query<T>`, `Execute`).
- `Exo.Context`: Provides runtime metadata such as `CallerPlayerId` and caller context.
- `Exo.Events`: Publishes events to the cluster pub/sub bus (`Publish`).

## 4. Building the Extension

Compile the extension locally to verify IL generation and Roslyn manifest creation:

```bash
./exo extension build daily_rewards --json
```

To cross-compile for a Linux VPS or container host:
```bash
./exo extension build daily_rewards --rid linux-musl-x64 --json
```

## 5. Deploying (Push) to Cluster

Deploy the built extension into the active Exoforge cluster:

```bash
./exo extension push daily_rewards --json
```

This command:
1. Compiles the extension if modified.
2. Packages the manifest and binary payload.
3. Uploads the artifact to the cluster via the management endpoint.
4. Hot-loads the extension process in the cluster.

## 6. Updating Unity Client Stubs

After deploying or updating an extension, regenerate the strongly-typed C# client stubs for Unity gameplay code:

```bash
./exo sync --json
```

This writes updated bindings to `Assets/Exoforge/Generated/ExoforgeServices.g.cs`, allowing gameplay scripts to invoke the new action:

```csharp
var result = await ExoServices.DailyRewards.ClaimRewardAsync(3);
```

## 7. Inspecting Logs

Stream or inspect recent log output from an extension running on the cluster:

```bash
./exo extension logs daily_rewards --json
```

## 8. Removing an Extension

To remove an installed extension from the cluster:

```bash
./exo extension remove daily_rewards --json
```
