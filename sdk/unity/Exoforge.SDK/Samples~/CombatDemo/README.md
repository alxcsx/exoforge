# Exoforge Combat Demo Sample

This sample demonstrates end-to-end communication between a Unity game client and the Exoforge backend:
- Connecting to the high-performance WebSocket ingress (`exoforge_std_ws`)
- Session authentication with bearer tokens (`exoforge_std_auth`)
- Invoking game logic actions running sandboxed in C# WebAssembly (`combat_wasm`)
- Emitting and receiving cluster events (`player_damaged`) pumped safely onto Unity's main thread via `ExoDispatcher`.

## How to Run in Unity
1. Attach `CombatDemoController.cs` to an empty GameObject in your scene.
2. Ensure your Exoforge server is running (`just dev` or `mix run --no-halt`).
3. Press **Play** in the Unity Editor.
4. Watch the Unity Console log the connection, authentication, action execution, and event callback!
