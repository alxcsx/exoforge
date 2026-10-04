# Exoforge SDK — Basic Usage

Minimal integration sample.

## Setup

1. `Tools ▸ Exoforge ▸ Initialize Workspace` (creates `Assets/Exoforge/exoforge.json`).
2. `Tools ▸ Exoforge ▸ Sync Runtime Config` (links the workspace config into `Resources/exoforge.json`).
3. `Tools ▸ Exoforge ▸ Add Exoforge to Scene` (drops the standard **Exoforge** prefab).
4. Attach `BasicUsageController` to any GameObject and press Play.

The prefab's `ExoforgeBehaviour` connects, authenticates (reusing the token in
`ExoTokenStore` when present), and pumps the dispatcher on the main thread. Gameplay code
only awaits `ExoforgeBehaviour.Instance.GetClientAsync()` — there are no URLs, tokens, or
session calls in it.

## Typed client

This sample calls `SendActionAsync` directly so it compiles without code generation.
Run `Tools ▸ Exoforge ▸ Sync Client Bindings` (or the Control Center) to generate the
strongly-typed client, then use `client.SampleWasm().IncrementAsync(...)` instead.
