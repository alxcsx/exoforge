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
- Template: `Basic Service` (or choose `Blank / Minimal`, `Persistent Data`, `Config & State`, `Event Producer`)

This creates `Exoforge/extensions/daily_rewards/` with a clean, single-action C# service (and standalone `.sln`):

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
        var playerId = Exo.Context.CallerPlayerId;
        if (string.IsNullOrEmpty(playerId))
            throw new ExoActionException("unauthorized", "Player session is required.");

        var existing = Exo.Database.Get<DailyRewardsClaim>(playerId);
        if (existing != null)
            throw new ExoActionException("already_claimed", "Daily reward has already been claimed.");

        var reward = new DailyRewardsReward("coins", 10 + level);
        Exo.Database.Put(new DailyRewardsClaim(playerId, DateTime.UtcNow));
        return reward;
    }
}

public record DailyRewardsReward(string Kind, int Amount);
public record DailyRewardsClaim(string Id, DateTime ClaimedAt);
```

### 3. Build & Deploy
Click **🚀 Build & Deploy** on the `daily_rewards` card in Exoforge Studio.
The extension compiles via your local .NET SDK (`>= 9.0`) and hot-loads into the Exoforge cluster.
Click **Edit** anytime to open its standalone solution directly in Rider or Visual Studio.

### 4. Call from Unity Gameplay Code

```csharp
using UnityEngine;
using Exoforge.Client;
using Exoforge.Client.Unity;

public class DailyRewardsController : MonoBehaviour
{
    private async void Start()
    {
        // 1. Authenticate player via device ID
        var session = await ExoforgeSDK.Auth.LoginAnonymously();
        if (!session.HasDisplayName)
        {
            await ExoforgeSDK.Auth.SetDisplayName("Viper");
        }

        // 2. Invoke your extension action with type safety and error handling
        try
        {
            var reward = await ExoServices.DailyRewards.ClaimDailyRewardAsync(5);
            // or: await ExoforgeSDK.Client.DailyRewards().ClaimDailyRewardAsync(5);

            Debug.Log($"Granted {reward.Amount} {reward.Kind}!");
        }
        catch (ExoActionException ex)
        {
            Debug.LogWarning($"Daily reward failed [{ex.Code}]: {ex.Message}");
        }
    }
}
```

`ExoActionException` keeps the server's fields apart: `Code` is the stable code to branch on
(`already_claimed`), `Message` is the server's message to show the player, and `RequestId` is the
rid that joins the call to the server's timeline. Extension log lines (`logs`) are attached only
for staff callers, so a player's error is the code and message without server internals.

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
4. **Records in Game Code**: Unity's profile has no `System.Runtime.CompilerServices.IsExternalInit`, so a `record` or an `init` setter fails with CS0518. **Exoforge ▸ Studio ▸ Settings ▸ C# Records Support** (and the setup wizard) writes `Assets/Exoforge/IsExternalInit.cs` for you. The type is internal, so it belongs to one assembly: an asmdef that declares records needs its own copy in its folder — the SDK's copy is internal to the SDK and does not help your assembly. On fresh clones or in CI (without Unity running), run `exo unity records --all` (or `--asmdef <dir>`).


## Testing several players on one machine

MPPM clones are detected automatically from the Editor's data path (`Library/VP/<id>`); each clone gets its own device id and token store. Standalone builds/CI use `-exoProfile <name>` on the command line. The default profile keeps the legacy PlayerPrefs keys, so existing players keep their account.

---

## AI Agent Tooling & Embedded CLI (Opt-In)

`com.exoforge.sdk` bundles the `exo` CLI (`Editor/Cli~/exo`, `exo.cmd`, `exo.dll`) and agent guide/skills (`Agents~/AGENTS.md`, `Agents~/skills/`) inside the package without writing anything to your project root automatically on import, initialization, scaffold, or build.

To opt in and install skills, `AGENTS.md`, and `./exo` wrappers into your Unity project:

- **Unity Editor**: **Exoforge ▸ Agents ▸ Install Agent Skills & CLI...**
- **Headless Unity (CI / automation)**:
  ```bash
  Unity -batchmode -quit -nographics -projectPath <path> -executeMethod Exoforge.Unity.Editor.ExoforgeAgentTools.InstallAgentSkillsAndCliHeadless
  ```
- **Embedded CLI** (explicit target flags required; running without flags prints help and installs nothing):
  ```bash
  dotnet Packages/com.exoforge.sdk/Editor/Cli~/exo.dll agents install --claude   # or --gemini, --agents, --all
  ```

Installation is idempotent and appends a marked `.gitignore` block (`# >>> EXOFORGE-AGENT-TOOLING:START` / `# <<< EXOFORGE-AGENT-TOOLING:END`) listing the generated artifacts (`.agents/`, `.claude/`, `.gemini/`, `AGENTS.md`, `exo`, `exo.cmd`).
