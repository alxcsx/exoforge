# Exoforge SDK — Basic Usage

Minimal integration sample.

## Setup

1. `Tools ▸ Exoforge ▸ Exoforge Studio` → **Plugins ▸ Initialize Workspace** (creates `Exoforge/exoforge.json`).
2. **Exoforge Studio ▸ Settings ▸ Generate / Relink Runtime Config** (links the workspace config into `Resources/exoforge.json`).
3. `Tools ▸ Exoforge ▸ Add Exoforge to Scene` (drops the standard **Exoforge** prefab).
4. Attach `BasicUsageController` to any GameObject and press Play.

The prefab's `ExoforgeManager` connects, authenticates (reusing the token in
`ExoTokenStore` when present), and pumps the dispatcher on the main thread. Gameplay code
only awaits `ExoforgeManager.Instance.GetClientAsync()` — there are no URLs, tokens, or
session calls in it.

## Typed client

This sample calls `SendActionAsync` directly so it compiles without code generation.
Run **Exoforge Studio ▸ Overview ▸ Sync Contracts & Generate C# Client** to generate the
strongly-typed client, then use `client.SampleWasm().IncrementAsync(...)` instead.
