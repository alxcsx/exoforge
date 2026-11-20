# Exoforge Arcade inventory (read-only)

## Scenes (Assets/Scenes/*.unity)
- MainMenu.unity -> 2d-hub (uses GameMenu, Wallet, ResourceStore)
- BrainrotExchange.unity -> 2d-hub (BrainrotMarket, Wallet, DailyRewards, ResourceStore)
- EchoDungeon.unity -> 2d-echo-dungeon (AdventureWorld, Achievements; mocks game server)
- DoodleDash.unity -> 2d-doodle-dash (LevelShare, ExoforgeSDK.Client)

## Samples asmdefs
- Samples.MainMenu (refs Exoforge.SDK, Exoforge.Generated, Samples.Common) -> 2d-hub
- Samples.BrainrotExchange (refs + Samples.Common, Unity.InputSystem) -> 2d-hub
- Samples.EchoDungeon (refs + Samples.Common, Unity.InputSystem) -> 2d-echo-dungeon
- Samples.DoodleDash (refs + Samples.Common, Unity.InputSystem) -> 2d-doodle-dash
- Samples.Common (refs Exoforge.SDK, Exoforge.Generated, Unity.InputSystem) -> SHARED (all 2D)
- Editor asmdefs mirror sample ownership; DoodleDash.Editor also refs Samples.Common (Assets/Samples/DoodleDash/Editor/Samples.DoodleDash.Editor.asmdef)

## Exoforge SDK/generated
- Assets/Exoforge/Generated/Exoforge.Generated.asmdef + ExoforgeServices.g.cs -> SHARED (regenerated via exo sync)
- Assets/Editor (ArcadeSetup.cs:9 SceneOrder lists MainMenu/BrainrotExchange/EchoDungeon/DoodleDash) -> 2d-hub only; per-project setup scripts in each sample Editor/

## Common (Assets/Samples/Common)
- AchievementToast.cs (ExoServices.Achievements feed) and SamplePlayer.cs; used by BrainrotExchange/EchoDungeon/DoodleDash/MainMenu asmdefs + Assets/Scenes/EchoDungeon.unity; AchievementToast subscribes Achievements.OnAchievementUnlocked (Common/AchievementToast.cs:22-23) -> SHARED

## Hard-coded path/scene assumptions
- Assets/Editor/ArcadeSetup.cs:9 SceneOrder includes all 4 scenes -> split per project
- README.md:10,163 scene names; AGENTS.md references extensions; tools/smoke.sh + tools/smoke/*.sh run samples against one cluster -> per-project smoke
- Assets/Resources/exoforge.json runtime profile shared across all -> SHARED/copy per project

## Exoforge config
- Exoforge/exoforge.json project_name=ExoforgeArcade, codegen output Assets/Exoforge/Generated/ExoforgeServices.g.cs, extensions_dir=extensions -> SHARED workspace root
- Assets/Resources/exoforge.json only ws/http urls (no token) -> SHARED runtime config

## Build settings
- ProjectSettings/EditorBuildSettings.asset lists MainMenu, BrainrotExchange, EchoDungeon, DoodleDash -> split scene lists per project

## Extensions (Exoforge/extensions) and callers
- game_menu -> MainMenu (MenuBridge.cs:32,42,55,66,70)
- wallet -> MainMenu, BrainrotExchange
- daily_rewards -> BrainrotExchange (ExchangeBridge.cs:55,63)
- brainrot_market -> BrainrotExchange
- adventure_world -> EchoDungeon (DungeonBridge.cs:19)
- achievements -> EchoDungeon + Common toast (AchievementToast.cs:22)
- level_share -> DoodleDash (DoodleBridge.cs:49,56,57,66,75,87)
- world_boss -> new 3d-snowball-siege (not in this repo; pays via wallet)

## Mapping table
| Item | Destination |
|---|---|
| Assets/Scenes/MainMenu.unity + BrainrotExchange.unity | 2d-hub |
| Assets/Scenes/EchoDungeon.unity | 2d-echo-dungeon |
| Assets/Scenes/DoodleDash.unity | 2d-doodle-dash |
| Assets/Samples/MainMenu, BrainrotExchange | 2d-hub |
| Assets/Samples/EchoDungeon | 2d-echo-dungeon |
| Assets/Samples/DoodleDash | 2d-doodle-dash |
| Assets/Samples/Common | SHARED |
| Assets/Editor/ArcadeSetup.cs | per-project setup |
| Assets/Exoforge/*, Assets/Resources/exoforge.json | SHARED |
| Exoforge/ (extensions, config) | SHARED workspace |
| tools/smoke* | per-project |
| ProjectSettings/EditorBuildSettings.asset | per-project scene lists |
| world_boss extension | 3d-snowball-siege |
