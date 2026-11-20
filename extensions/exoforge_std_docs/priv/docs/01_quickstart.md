# Exoforge Developer Quickstart

A hands-on tutorial: create a native C# extension, deploy it with Unity Studio, generate typed Unity client stubs, and call the service from a MonoBehaviour.

## Prerequisites

- Unity 2022.3 or newer with the **Exoforge SDK** package installed (`com.exoforge.sdk`, a current release).
- .NET 9 is the minimum required SDK. Install it from the [official .NET download page](https://dotnet.microsoft.com/download). The Unity editor validates it before building an extension.

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

In Unity Studio, navigate to the **Extensions** tab and click **New Extension...**. Choose the standard template. Studio creates the extension solution outside `Assets/`, so modern C# and .NET features work without Unity compiling them.

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

### Deploy in Unity Studio
In the **Extensions** tab, find your extension card and click **Build & Deploy**. Your local .NET compiler publishes the binary and uploads it. Wait for the status to report **running**.

If the build fails, the deploy stops before upload. Open the extension's **Logs** tab to see the compiler output or a startup error.

---

## 4. Generate Typed Stubs

Whenever an extension action or schema changes, update your typed code contracts:

### Client Game Stubs (Unity)
Click **Sync Client** in the Unity toolbar (or the Exoforge Studio menu). This queries live cluster contracts and generates `Assets/Exoforge/Generated/ExoforgeServices.g.cs`. Player- and global-scoped actions are emitted; studio/admin actions are excluded from the game surface by default. The generated file provides static accessors (`ExoServices.GameplayCalculator`) and client extensions (`ExoforgeSDK.Client.GameplayCalculator()`) with main-thread callbacks and async overloads.

### Extension-to-Extension Stubs (Server)
In the **Extensions** tab, open your extension and click **Stubs**. Studio generates typed client stubs for the services declared in the extension's `manifest.json` dependencies, writing to `obj/exoforge/PluginServices.g.cs`. Only those dependencies are generated.

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

Enter Play Mode and trigger the call. The Unity Console prints the returned score; the same request appears in Studio's extension inspector and its **Logs** tab. If the action is missing, confirm the extension is **running** and click **Sync Client** after the build.
