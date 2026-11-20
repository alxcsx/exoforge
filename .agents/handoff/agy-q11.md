# Q11 - wt/migrate: an install that crashes still rolls back (after Q10)
Worktree /Users/alexcs/projects/exoforge-wt/migrate. Rules: .agents/handoff/wt-common.md. Gemini model.
Copilot on 9d6e2b9: extension_manager.ex ~L721 rollback is not protected against exceptions or a process crash, so a
crash mid-install leaves the backup and the half-installed version in place.
1. An exception or throw during install/redeploy runs the same rollback (try/rescue/catch around the install, not
   around the whole GenServer), and the caller gets {:error, ...} with the rollback status.
2. Serializer.init/1 (also after a supervisor restart) restores any leftover extension backup directory and
   re-registers/reboots that previous version before accepting calls; log what it recovered.
Tests: an install that raises mid-way leaves the previous version running; a Serializer started with a leftover
backup on disk restores it. Run extension_manager_test + resources_test. Reply: ask --reply t7 "Q11: <=8 lines".
