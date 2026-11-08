# Exoforge Developer Quickstart

From zero to live online multiplayer backend services in 60 seconds.

Exoforge allows game developers to write clean, strongly-typed native C# backend extensions that compile locally, hot-reload into an actor concurrency microservices runtime, and sync seamlessly into client code without manual networking boilerplate.

---

## 1. Connect & Authenticate

Sign in anonymously using device credentials or authenticate players with seamless token caching.

### Two-Stage Anonymous Login & Zero-Wiring Setup

1. **Zero Scene Wiring**: You do not need to manually instantiate prefabs in your scene. `ExoforgeManager` initializes automatically on demand when your game invokes any `ExoforgeSDK` method.
2. **Stage 1 (Device Anonymous Login)**: `ExoforgeSDK.Auth.LoginAnonymously()` enters or registers an account keyed by the device identifier (`ExoDeviceId` derives a stable, hashed id from `SystemInfo.deviceUniqueIdentifier`). The same machine always resolves to the same player even if credentials are lost.
3. **Stage 2 (Display Name)**: A new account returns with `session.HasDisplayName == false`. Call `ExoforgeSDK.Auth.SetDisplayName("Viper")` to name the player.

```csharp
using UnityEngine;
using Exoforge.SDK;

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

In Unity Studio, navigate to the **Extensions** tab and click **New Extension...** (or run `exo extension new <name>`). This creates an isolated solution in `Exoforge/extensions/<name>/` outside `Assets/`, allowing modern C# and .NET features without polluting Unity.

```csharp
using System;
using System.Threading.Tasks;
using Exoforge.Plugin.SDK;

[ExoService("gameplay_calculator", Title = "Gameplay Calculator", Icon = "🧮", Version = "1.0.0")]
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
> Extensions execute as native .NET microservices with actor supervision. Use modern C# records, type-safe APIs, and throw canonical `ExoActionException`.

---

## 3. Build & Hot-Deploy

Fast local compilation and zero-downtime hot reloading.

### 1-Click Deploy in Studio
In Exoforge Studio or the Extensions Window, find your extension card and click **Build & Deploy**. Your local .NET compiler publishes the binary and uploads it directly to the cluster.

### CLI Deployment
```bash
exo extension push gameplay_calculator
exo extension logs gameplay_calculator
```

---

## 4. Generate Typed Stubs

Whenever an extension action or schema changes, update your typed code contracts:

### Client Game Stubs (Unity)
Click **Sync Client** in the Unity toolbar (or the Exoforge Studio menu). This queries live cluster contracts and generates `Assets/Exoforge/Generated/ExoforgeServices.g.cs`. Your Unity project immediately gains strongly-typed methods (`ExoforgeSDK.Client.GameplayCalculator()`) for every action (both main-thread callbacks and async overloads) and typed models for every return record!

### Extension-to-Extension Stubs (Server)
Run `exo extension stubs <name>` to generate typed client stubs for services declared in your extension's `manifest.json` dependencies, writing to `src/Generated/ExtensionServices.g.cs`.

---

## 5. Call from Unity Gameplay Code

```csharp
using UnityEngine;
using System.Threading.Tasks;
using Exoforge.SDK;
using Exoforge.Generated;

public class GameplayRewardController : MonoBehaviour
{
    void OnLevelCompletedWithCallback(int points, int multiplier)
    {
        var client = ExoforgeSDK.Client.GameplayCalculator();

        // Style A: Unity Main-Thread Callback
        client.CalculateScore(
            new CalculateScoreRequest(points, multiplier),
            onComplete: res => Debug.Log($"Final Score: {res.TotalScore}"),
            onError: err => Debug.LogError($"Calculation failed: {err.Message}")
        );
    }

    async Task OnLevelCompletedAsync(int points, int multiplier)
    {
        // Style B: Task Async/Await Overload
        try
        {
            var res = await ExoforgeSDK.Client.GameplayCalculator()
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
