# Arcade example inventory

Extensions under /Users/alexcs/projects/exoforge-arcade/extensions:

- achievements: extensions/achievements/src/AchievementsExtension.cs
- adventure_world: extensions/adventure_world/src/AdventureWorldExtension.cs
- brainrot_market: extensions/brainrot_market/src/BrainrotMarketExtension.cs
- daily_rewards: extensions/daily_rewards/src/DailyRewardsExtension.cs
- game_menu: extensions/game_menu/src/GameMenuExtension.cs
- level_share: extensions/level_share/src/LevelShareExtension.cs
- wallet: extensions/wallet/src/WalletExtension.cs
- world_boss: extensions/world_boss/src/WorldBossExtension.cs (+ BossModels.cs, BossStore.cs)

Each uses ExoService/ExoAction/ExoResource patterns consistent with Attributes.cs. Snippets: service declaration in AchievementsExtension.cs; action scope in LevelShareExtension.cs; resource+columns in WorldBoss BossModels.cs; event publish/subscribe in DailyRewards; cron in DailyRewards; dependency call in level_share Generated/PluginServices.g.cs; singleton config in WorldBoss; seed/start hook in GameMenu; Unity side calls ExoServices.* (search sample_unity).

Counts: WRONG/STALE not applicable (inventory). All attribute names verified against Attributes.cs.