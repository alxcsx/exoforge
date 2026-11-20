# Q6 - wt/migrate: a redeploy that fails leaves the old version exactly as it was
Worktree /Users/alexcs/projects/exoforge-wt/migrate (branch wt/migrate, at a2d8b99 + whatever Q1 committed).
Rules: /Users/alexcs/projects/exoforge/.agents/handoff/wt-common.md. Gemini model. Touch only
extensions/exoforge_std_resources and extensions/exoforge_std_extension_manager (+ their tests).
Copilot review of the server diff, accepted findings:
1. resources: validate ALL of the extension's resources (duplicate-ignoring-case, primary_key) before running DDL for
   any of them; today an earlier valid resource runs DDL before a later invalid one is refused.
2. resources: compare existing table columns case-insensitively in reconcile_columns / repair_primary_key.
3. extension_manager redeploy: today the new files overwrite the old ones and unload happens first, so the "restore
   previous" path reboots the NEW binary with the OLD manifest and ignores a failed boot. Want: validate the new
   manifest's resources (pure, no DDL) before touching the running version; keep the previous extension directory as
   a backup until the new version has migrated and booted; on any failure restore the backup directory, re-register
   and reboot the previous version, check that boot succeeded, and return the original error plus rollback status.
   Remove the backup on success.
Rejected (do not change): primary_key "id" with no matching column stays allowed (implicit id).
Tests: one per point; for 3, a redeploy whose migration fails leaves the previous binary/manifest on disk and the
previous version running and answering an action; a redeploy whose new boot fails is rolled back the same way.
Run resources_test + extension_manager_test, commit, reply: ask --reply t7 "Q6: <=10 lines".
