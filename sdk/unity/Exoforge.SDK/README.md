# Exoforge Unity SDK

High-performance Unity client and editor integration for the Exoforge game backend platform.

---

## ⚡ Quickstart in 60 Seconds

```
Install Package ──▶ Connect & Auth ──▶ Scaffold Extension ──▶ Build & Deploy ──▶ Call from C#
```

### 1. Connect & Configure
Open **Tools ▸ Exoforge ▸ Exoforge Studio** or let the **Exoforge Setup Wizard** run on package import:
- Set your Instance URL (`localhost` for local Docker daemon or cloud URL).
- Sign in with developer credentials or email/password.
- Ensure the active scene contains an `ExoforgeManager` (**Tools ▸ Exoforge ▸ Add Exoforge to Scene**).

### 2. Create Your First Extension
In **Exoforge Studio**, click **⚡ New Extension...**:
- Name: `daily_rewards`
- Template: `Basic Service`

This creates `Exoforge/extensions/daily_rewards/` with a clean, single-action C# service:

```csharp
using Exoforge.Plugin.SDK;

namespace Exoforge.Extensions;

[ExoExtension("daily_rewards", Version = "0.1.0")]
public class DailyRewardsExtension
{
    [ExoAction]
    public DailyRewardsReward GetReward(int level) =>
        new("coins", 10 + level);
}

public record DailyRewardsReward(string Kind, int Amount);
```

### 3. Build & Deploy
Click **🚀 Build & Deploy** on the `daily_rewards` card in Exoforge Studio.
The extension compiles via your local .NET SDK (`>= 9.0`) and hot-loads into the Exoforge cluster.

### 4. Call from Unity Gameplay Code

```csharp
using UnityEngine;
using Exoforge.Client.Unity;

public class DailyRewardsController : MonoBehaviour
{
    private async void Start()
    {
        // 1. Wait for Exoforge client to connect and authenticate
        await Exoforge.Ready;

        // 2. Invoke your extension action with full type safety
        var response = await Exoforge.Client.DailyRewards()
            .ClaimDailyRewardAsync(new() { Level = 5 });

        if (response.Success && response.Reward != null)
        {
            Debug.Log($"Granted {response.Reward.Amount} {response.Reward.Kind}!");
        }
        else
        {
            Debug.Log($"Daily reward unavailable: {response.Message}");
        }
    }
}
```

---

## 🧭 The Two Unity Surfaces

- **Exoforge Studio** (**Tools ▸ Exoforge ▸ Exoforge Studio**):
  - Daily developer cockpit.
  - Connection status, cluster ping, player session.
  - Extension cards with 1-click Build & Deploy.
  - Client stub generation status.
- **Extensions Debugger** (**Tools ▸ Exoforge ▸ Extensions**):
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
