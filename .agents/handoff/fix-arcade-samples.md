# Phase 2: bring the arcade samples onto the fixed SDK (no workarounds)

Project /Users/alexcs/projects/exoforge-arcade (own git repo). You are a tarball user: use only
Packages/com.exoforge.sdk-0.1.43.tgz and the CLI inside it
(dotnet Library/PackageCache/com.exoforge.sdk@*/Editor/Cli~/exo.dll), never the exoforge repo's source.
Backend: http://localhost:4001 (already running, admin session saved in Exoforge/exoforge.json).
Toolchain: prefix dotnet with `/Users/alexcs/.local/bin/mise exec --`.

1. Packages/manifest.json -> file:com.exoforge.sdk-0.1.43.tgz (the tarball is placed in Packages/ for you).
   Run Unity headless only through tools/unity.sh (it serializes and passes -quit); recompile + SetUpAll.
2. Delete Assets/Samples/Common/IsExternalInit.cs (BUG-14 fixed in the SDK). Records must still compile.
3. Keep the code best-practice and let fixed SDK behaviour carry it: wallet failures now throw
   ExoActionException (BUG-1) - brainrot_market/game_menu must not catch-and-ignore them; [ExoWebhook]
   takes WebhookPayload (BUG-2); [ExoCron] is server-only (SEC-3); OnEvent is no longer re-entered (BUG-17);
   ExoTestHost is parallel-safe (CONF-9). Remove anything that only existed to dodge those.
4. tools/smoke/*.sh must ASSERT, not print: dungeon.sh must fail unless kills 3/chests 1/zones 1; the
   "no token" message must say `exo user create <email> --role service --password ...` then
   `exo user token <id>` (not auth issue_token). Same for any other script that only echoes.
5. README "What red means" table: drop rows that are fixed; keep any that are still red, with proof.
6. Redeploy every extension with the tarball CLI (`exo extension push <name>`), then run:
     mise exec -- dotnet test Exoforge/extensions/Exoforge.Extensions.sln
     tools/smoke.sh
     tools/unity.sh -executeMethod Arcade.Editor.ArcadeSetup.SetUpAll   (0 compile errors)
   All green is the acceptance. If something is still red because Exoforge is wrong, do NOT patch around
   it: leave it failing and write it to /Users/alexcs/projects/exoforge/.agents/samples-findings/phase2.md.
Commit in the arcade repo per sample ("fix(<sample>): ..."). Report <=15 lines with test/smoke output.
