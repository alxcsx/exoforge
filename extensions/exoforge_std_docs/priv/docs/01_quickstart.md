# Exoforge Developer Quickstart

From zero to live online multiplayer backend services in 60 seconds.

Exoforge allows game developers to write clean, strongly-typed native C# backend extensions that compile locally, hot-reload into an actor concurrency microservices runtime, and sync seamlessly into client code without manual networking boilerplate.

---

## 1. Connect & Authenticate

Sign in anonymously using device credentials or authenticate players with seamless token caching.

### Anonymous Login & Scene Setup

1. In your game's first scene, click **Exoforge ▸ Add Exoforge to Scene**. This creates the persistent `Exoforge.prefab`.
2. By default, `anonymousOnConnect: true` automatically mints an anonymous player session using the unique device identifier (`ExoDeviceId.Get()`) without requiring passwords.
3. Or call `Exoforge.Auth.LoginAnonymously()` programmatically from script.
4. Once authenticated, the session is cached locally in `ExoTokenStore` and `Exoforge.IsReady` becomes true.

```csharp
using UnityEngine;
using Exoforge.SDK;

public class GameInitializer : MonoBehaviour
{
    async void Start()
    {
        // Connect & claim or resume anonymous session keyed by stable device hash
        var session = await ExoforgeSDK.Auth.LoginAnonymously();
        Debug.Log($"Signed in as Player ID: {session.PlayerId}");

        if (!session.HasDisplayName)
        {
            await ExoforgeSDK.Auth.SetDisplayName("Viper");
        }
    }
}
```

---

## 2. Scaffold a Native C# Extension

Scaffold clean, modern C# backend services in seconds.

In Unity Studio, navigate to the **Extensions** tab and click **New Extension...** (or run `exo extension new <name>`). This creates an isolated solution in `Exoforge/extensions/<name>/`.

```csharp
using System.Threading.Tasks;
using Exoforge.SDK;

[ExoExtension("gameplay_calculator", Version = "1.0.0")]
public class GameplayCalculatorExtension
{
    [ExoAction]
    public CalculateScoreResponse CalculateScore(CalculateScoreRequest req)
    {
        if (req.Multiplier <= 0)
            throw new ExoActionException("invalid_multiplier", "Multiplier must be positive.");

        int finalScore = (req.BasePoints * req.Multiplier) + req.Bonus;
        return new CalculateScoreResponse(finalScore, System.DateTime.UtcNow);
    }
}

public record CalculateScoreRequest(int BasePoints, int Multiplier, int Bonus = 0);
public record CalculateScoreResponse(int TotalScore, System.DateTime CalculatedAt);
```

> [!NOTE]
> Extensions execute as native .NET microservices with actor concurrency supervision. Use modern C# records, type-safe APIs, and throw canonical `ExoActionException`.

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

## 4. Generate Client Stubs

Whenever an extension action or schema changes, click **Sync Client** in the Unity toolbar (or run `exo sync`).

> [!IMPORTANT]
> This queries live cluster contracts and generates `Assets/Exoforge/Generated/ExoforgeServices.g.cs`. Your Unity project immediately gains strongly-typed methods for every action (both main-thread callbacks and async overloads) and typed models for every return record!

---

## 5. Call from Unity Gameplay Code

```csharp
using UnityEngine;
using Exoforge.SDK;
using Exoforge.Generated;

public class GameplayRewardController : MonoBehaviour
{
    void OnLevelCompleted(int points, int multiplier)
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
        // Style B: Task Async/Await
        var res = await ExoforgeSDK.Client.GameplayCalculator()
            .CalculateScoreAsync(new CalculateScoreRequest(points, multiplier));
        Debug.Log($"Score calculated: {res.TotalScore}");
    }
}
```
