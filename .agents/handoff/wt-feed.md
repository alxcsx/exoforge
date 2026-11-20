# wt/feed: a versioned SDK package and a stable feed  (worktree /Users/alexcs/projects/exoforge-wt/feed)
Read wt-common.md first. Today the tarball ships Editor/Plugins/NuGet~/Exoforge.Plugin.SDK.0.1.0.nupkg - always
0.1.0 whatever the SDK version - and extensions reference Version="0.1.0"; nuget.config files point at the
hash-named Library/PackageCache/com.exoforge.sdk@<hash>/... dir, so they are machine-specific, git-ignored and
rewritten (ExoScaffolder.EnsureLocalFeed/EnsureBuildFeed, ExoDeployer.PublishNative ~L1400,
ExoforgeIdeProjectGenerator InitializeOnLoad refresh from d3e99c3). NuGet caches by id+version, so a fixed
0.1.0 can only work by evicting its cache.
Want:
- The nupkg version = the SDK version (from sdk/unity/Exoforge.SDK/package.json at pack time; `just pack-unity`
  / build-unity-sdk). Directory.Build.targets ExoforgePluginSdkVersion follows it.
- The CLI (build/push/test/new) and the Unity editor copy that nupkg into a project-relative feed
  `Exoforge/.feed/` (only when missing) and the workspace nuget.config is a static file:
  <add key="exoforge" value=".feed" /> plus nuget.org - relative, committable, never rewritten. Per-extension
  nuget.config files are not needed (NuGet walks up); stop writing them, and remove the stale-path refresh
  machinery that becomes dead.
- Scaffolded extensions reference the SDK version; upgrading the package updates the reference (CLI and Unity)
  so the new version is restored and the old one stays in NuGet's cache, untouched. Find and remove anything
  that evicts exoforge.plugin.sdk from the global packages folder (it was re-extracted at every build).
- Keep the master Exoforge.Extensions.sln generator change from 62e5140 (it keeps *.Tests projects).
Tests: Management tests (nupkg version stamping, feed copy, static relative nuget.config, upgrade updates the
reference); pack the tarball with COPYFILE_DISABLE=1 and show `tar tzf` lists Exoforge.Plugin.SDK.<version>.nupkg.
