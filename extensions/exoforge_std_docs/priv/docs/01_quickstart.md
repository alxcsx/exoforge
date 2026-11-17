# Exoforge Developer Quickstart

A hands-on tutorial: create a native C# extension, deploy it to a running cluster, generate typed Unity client stubs, and call the service from a MonoBehaviour.

## Prerequisites

- Unity 2022.3 or newer with the **Exoforge SDK** package installed (`com.exoforge.sdk` 0.1.41+).
- The .NET 9 SDK (`dotnet --version` reports 9.x). The Unity editor validates this before building an extension.
- A running Exoforge cluster. For local development, run `just dev`; open Producer Studio at `http://localhost:4005`.
- An `exoforge.json` workspace at the Unity project root (or its `Exoforge/` directory). The Unity Studio **Extensions** tab creates it for you.

Exoforge lets you write strongly-typed native C# extensions that compile locally, deploy into a supervised extension runtime, and sync into Unity client code without manual networking boilerplate.

---

## 1. Connect & Authenticate

Sign in anonymously using device credentials or authenticate players with seamless token caching.

### Two-Stage Anonymous Login & Zero-Wiring Setup

1. **Zero Scene Wiring**: You do not need to manually instantiate prefabs in your scene. `ExoforgeManager` initializes automatically on demand when your game invokes any `ExoforgeSDK` method.
2. **Stage 1 (Device Anonymous Login)**: `ExoforgeSDK.Auth.LoginAnonymously()` enters or registers an account keyed by the device identifier (`ExoDeviceId` derives a stable, hashed id from `SystemInfo.deviceUniqueIdentifier`). The same machine always resolves to the same player even if credentials are lost.
3. **Stage 2 (Display Name)**: A new account returns with `session.HasDisplayName == false`. Call `ExoforgeSDK.Auth.SetDisplayName("Viper")` to name the player.

```csharp
using UnityEngine;
using Exoforge.Client.Unity;

public class GameInitializer : MonoBehaviour
{
    async void Start()
    {
        // Stage 1: Connect & claim or resume anonymous session keyed by stable device hash
        var session = await ExoforgeSDK.Auth.LoginAnonymously();
        Debug.Log($"Signed in as Player ID: {session.PlayerId}");

        // Stage 2: Prompt new players for a display name if not yet assigned
        if (!session.HasDisplayName)
        {
            session = await ExoforgeSDK.Auth.SetDisplayName("Viper");
            Debug.Log($"Welcome {session.DisplayName}!");
        }
    }
}
```

---

## 2. Scaffold a Native C# Extension

Scaffold clean, modern C# backend services in seconds.

In Unity Studio, navigate to the **Extensions** tab and click **New Extension...**, or run `exo extension new <name> --template standard`. The extension is created in the workspace's `extensions/<name>/` directory; the Unity sample uses `Exoforge/extensions/<name>/`. It lives outside `Assets/`, so modern C# and .NET features work without Unity compiling them.

```csharp
using System;
using System.Threading.Tasks;
using Exoforge.Plugin.SDK;

[ExoService("gameplay_calculator", Title = "Gameplay Calculator", Icon = "🧮", Version = "0.1.0")]
public class GameplayCalculatorExtension
{
    [ExoAction(Scope = "player")]
    public CalculateScoreResponse CalculateScore(CalculateScoreRequest req)
    {
        if (req.Multiplier <= 0)
            throw new ExoActionException("invalid_multiplier", "Multiplier must be positive.");

        int finalScore = (req.BasePoints * req.Multiplier) + req.Bonus;
        return new CalculateScoreResponse(finalScore, DateTime.UtcNow);
    }
}

public record CalculateScoreRequest(int BasePoints, int Multiplier, int Bonus = 0);
public record CalculateScoreResponse(int TotalScore, DateTime CalculatedAt);
```

> [!NOTE]
> Extensions execute as supervised native .NET processes. Use modern C# records, type-safe APIs, and throw canonical `ExoActionException` for domain errors.

If the extension needs to seed data or warm a cache after the protocol handshake, add an optional parameterless hook:

```csharp
public void OnExtensionStart()
{
    // Runs once per extension process after the handshake and resource migration.
    // Keep it idempotent; it also runs after a restart.
}
```

`OnExtensionStart()` needs no attribute. It is optional, and an extension without it starts normally.

---

## 3. Build & Hot-Deploy

Fast local compilation and zero-downtime hot reloading.

### 1-Click Deploy in Studio
In Exoforge Studio or the Extensions Window, find your extension card and click **Build & Deploy**. Your local .NET compiler publishes the binary and uploads it directly to the cluster.

### CLI Deployment
```bash
exo extension build gameplay_calculator
exo extension push gameplay_calculator
exo extension logs gameplay_calculator
```

`exo extension push` builds before uploading. It fails the deploy when the build fails, so a stale binary is never uploaded. Use `--rid linux-musl-x64` when deploying to an Alpine container.

---

## 4. Generate Typed Stubs

Whenever an extension action or schema changes, update your typed code contracts:

### Client Game Stubs (Unity)
Click **Sync Client** in the Unity toolbar (or the Exoforge Studio menu), or run `exo sync` from the workspace. This queries live cluster contracts and generates `Assets/Exoforge/Generated/ExoforgeServices.g.cs`. Player- and global-scoped actions are emitted; studio/admin actions are excluded by default. Pass `--include-studio` to `exo sync` when a tool needs the full surface. The generated file provides static accessors (`ExoServices.GameplayCalculator`) and client extensions (`ExoforgeSDK.Client.GameplayCalculator()`) with main-thread callbacks and async overloads.

### Extension-to-Extension Stubs (Server)
Run `exo extension stubs <name>` to generate typed client stubs for services declared in your extension's `manifest.json` dependencies, writing to `src/Generated/PluginServices.g.cs`. Only those dependencies are generated; `--services a,b` overrides the list.

---

## 5. Call from Unity Gameplay Code

```csharp
using UnityEngine;
using System.Threading.Tasks;
using Exoforge.Client;
using Exoforge.Client.Unity;

public class GameplayRewardController : MonoBehaviour
{
    void OnLevelCompletedWithCallback(int points, int multiplier)
    {
        var client = ExoServices.GameplayCalculator;

        // Style A: Unity Main-Thread Callback
        client.CalculateScore(
            new CalculateScoreRequest(points, multiplier),
            onComplete: res => Debug.Log($"Final Score: {res.TotalScore}"),
            onError: err => Debug.LogError($"Calculation failed: {err.Message}")
        );
    }

    async Task OnLevelCompletedAsync(int points, int multiplier)
    {
        // Style B: Task Async/Await Overload (via ExoServices or ExoforgeSDK.Client)
        try
        {
            var res = await ExoServices.GameplayCalculator
                .CalculateScoreAsync(new CalculateScoreRequest(points, multiplier));
            Debug.Log($"Score calculated: {res.TotalScore}");
        }
        catch (ExoActionException err)
        {
            Debug.LogError($"Calculation failed: {err.Message}");
        }
    }
}
```

Enter Play Mode and trigger the call. The Unity Console prints the returned score; the same request appears in Studio's extension inspector and in `exo extension logs gameplay_calculator`. If the action is missing, confirm the extension was pushed and `exo sync` ran after the build.
