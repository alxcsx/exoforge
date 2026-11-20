# wt/tooling: records CLI, rid on every error, Unity feed migration  (worktree /Users/alexcs/projects/exoforge-wt/tooling)
Read wt-common.md first. Do not touch exoforge_std_resources, extension_manager, the generator (wt/migrate owns them)
or ExoDeviceId/ExoTokenStore/ExoforgeAuth (wt/instances owns them).
1. `exo unity records [--asmdef <dir>] [--all]` in sdk/csharp/Exoforge.CLI over Exoforge.Management.ExoIsExternalInit:
   --asmdef writes the file for that assembly if missing; --all writes one per asmdef under Assets/ that declares a
   record or init accessor and has none; prints what it wrote/skipped; works from the project root with no Unity
   running. Also make the Studio/wizard show presence per target assembly instead of project-wide
   (ExoforgeIsExternalInit.PresentPath). Docs/skill: mention the command for fresh clones/CI.
2. rid on every error reply: the HTTP auth plug (exoforge_std_http router.ex ~L280-310: unauthenticated,
   token_expired) gets a rid before authenticating and sends its errors through Transport's shared error builder,
   so they have {status, error:{code,message,details}, rid} like every other error; same for any WS auth refusal.
3. Unity: after a domain reload, if Exoforge/nuget.config is not the static .feed one or any
   Exoforge/extensions/**/nuget.config exists, run ExoforgeIdeProjectGenerator.EnsureWorkspaceFeed once (it is
   idempotent); an upgraded project migrates without a CLI build.
Tests: Management test for the records command (--asmdef, --all, idempotent); http/ws tests for rid on 401s;
Management or editor-logic test for the migration trigger.
