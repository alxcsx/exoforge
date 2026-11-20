# Common rules for the wt/* workers

- You work ONLY in your own worktree /Users/alexcs/projects/exoforge-wt/<task> (branch wt/<task>).
  Never edit /Users/alexcs/projects/exoforge or another worktree. Never push, never merge.
- Toolchain: prefix mix/dotnet/just with `/Users/alexcs/.local/bin/mise exec --`. A fresh worktree
  needs `mix deps.get` once in the dirs you test; run `mix deps.compile --force` if a path dep is stale.
- Do NOT bump the SDK version (package.json / ExoforgePackageVersion.cs); t7 bumps once at merge.
- Do NOT touch the running backend on :4001 or /Users/alexcs/projects/exoforge-arcade.
- Follow AGENTS.md: shortest diff, match surrounding style, delete what the change makes dead,
  update docs/skills that describe the old behaviour (Agents.MD, docs/, sdk/unity/Exoforge.SDK/Agents~).
- Each change gets a test that fails before it. Run only the test files you touch, paste results.
- Commit on your branch ("feat(...)/fix(...): ..."). Report <=15 lines: commits, file:line, test
  output, risks, via `ask --reply t7 "<report>"`.
