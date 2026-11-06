# Exoforge Unity SDK

High-performance Unity client and editor integration for the Exoforge game backend platform.

---

## ⚡ Quickstart in 60 Seconds

```
Install Package ──▶ Connect & Auth ──▶ Scaffold Extension ──▶ Build & Deploy ──▶ Call from C#
```

### 1. Connect & Configure
Open **Exoforge ▸ Studio**:
- Connect to your server instance.
- Sign in with your staff account credentials.
- Ensure the active scene contains an `ExoforgeManager` (**Exoforge ▸ Add Exoforge to Scene**).

### 2. Create Your First Extension
In **Exoforge Studio**, click **⚡ New Extension...**:
- Name: `daily_rewards`
- Template: `Basic Service`

This creates `Exoforge/extensions/daily_rewards/` with a clean, single-action C# service:

```csharp
using System;
using Exoforge.Plugin.SDK;

namespace Exoforge.Extensions;

[ExoExtension("daily_rewards", Version = "0.1.0")]
public class DailyRewardsExtension
{
    [ExoAction]
    public DailyRewardsReward ClaimDailyReward(int level)
    {
        var playerId = ExoServices.Context.CurrentPlayerId;
        if (string.IsNullOrEmpty(playerId))
            throw new ExoActionException("unauthorized", "Player session is required.");

        var existing = ExoServices.Database.Get<DailyRewardsClaim>(playerId);
        if (existing != null)
            throw new ExoActionException("already_claimed", "Daily reward has already been claimed.");

        var reward = new DailyRewardsReward("coins", 10 + level);
        ExoServices.Database.Put(new DailyRewardsClaim(playerId, DateTime.UtcNow));
        return reward;
    }
}

public record DailyRewardsReward(string Kind, int Amount);
public record DailyRewardsClaim(string Id, DateTime ClaimedAt);
```

### 3. Build & Deploy
Click **🚀 Build & Deploy** on the `daily_rewards` card in Exoforge Studio.
The extension compiles via your local .NET SDK (`>= 9.0`) and hot-loads into the Exoforge cluster.

### 4. Call from Unity Gameplay Code

```csharp
using UnityEngine;
using Exoforge.Client.Unity;
using Exoforge.Plugin.SDK;

public class DailyRewardsController : MonoBehaviour
{
    private async void Start()
    {
        // 1. Wait for Exoforge client to connect and authenticate
        await Exoforge.Ready;

        // 2. Invoke your extension action with type safety and error handling
        try
        {
            var reward = await Exoforge.Client.DailyRewards()
                .ClaimDailyRewardAsync(new() { Level = 5 });

            Debug.Log($"Granted {reward.Amount} {reward.Kind}!");
        }
        catch (ExoActionException ex)
        {
            Debug.LogWarning($"Daily reward failed [{ex.Code}]: {ex.Message}");
        }
    }
}
```

---

## 🧭 The Two Unity Surfaces

- **Exoforge Studio** (**Exoforge ▸ Studio**):
  - Daily cockpit.
  - Connection status, cluster ping, player session.
  - Extension cards with 1-click Build & Deploy.
  - Client stub generation status.
- **Extensions Debugger** (**Exoforge ▸ Extensions & Resources**):
  - Deep diagnostic inspector.
  - Raw contracts & manifest schemas.
  - Resource table explorer (query, insert, update, delete).
  - Parameterized action sandbox with timing diagnostics.
  - Real-time PubSub event stream.
  - Extension process logs (stdout/stderr).

---

## 📚 Core Guides

1. **Connecting a Unity Project**: Keep your `Exoforge/exoforge.json` in version control; the SDK generates `Assets/Resources/exoforge.json` for runtime builds.
2. **ExoforgeManager Lifecycle**: Dropping `Exoforge.prefab` into your first scene ensures background reconnects, main-thread callback dispatching, and persistent state (`DontDestroyOnLoad`).
3. **Working Offline**: Developing offline is supported for tests and branching, but BaaS capabilities (remote sync, live cluster deploy, telemetry) require an online cluster.
