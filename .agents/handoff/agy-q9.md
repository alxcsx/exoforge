# Q9 - wt/migrate: last Copilot findings on the redeploy rollback (after Q7, Q8)
Worktree /Users/alexcs/projects/exoforge-wt/migrate. Rules: .agents/handoff/wt-common.md. Gemini model.
1. extension_manager.ex ~L622-647: the manifest-loader `[]` branch removes the backup although nothing replaced the
   previous version - restore it instead; a failed rm_rf of the backup is logged (warning) and reported, not ignored.
2. Concurrent pushes of the same extension can interleave (stale op restores over a newer good install). Serialize
   install/redeploy/remove per extension through ONE process (an existing GenServer if extension_manager has one,
   otherwise a small one under its supervisor) - no locks, no external coordination (AGENTS.md "No Distributed
   Locks"). Pushes of different extensions may still run concurrently if that is no more code; otherwise serialize all.
3. Document in the module doc and Agents.MD: a redeploy has a short window where the extension is not running
   (one instance by design); a failed redeploy brings the previous version back.
Tests: [] branch keeps/restores the previous version; two concurrent pushes of one extension end with the later
one installed and no stale restore. Run extension_manager_test + resources_test. Reply: ask --reply t7 "Q9: <=10 lines".
