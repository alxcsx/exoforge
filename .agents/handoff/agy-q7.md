# Q7 - wt/tooling review fixes (Haiku review of ff3282c and 35c52c9)
Worktree /Users/alexcs/projects/exoforge-wt/tooling. Rules: .agents/handoff/wt-common.md. Gemini model.
One test per point, each failing before the fix. Commit, reply: ask --reply t7 "Q7: <=10 lines".
A. exo unity records / ExoIsExternalInit (sdk/csharp/Exoforge.Management/ExoIsExternalInit.cs, Exoforge.CLI/Program.cs):
 1. Ensure/ResolveDirectory (~L49, L109-125): reject a target directory that does not resolve under
    AssetsPath(projectRoot) (rooted paths, `..`, a rooted /Assets/... on Windows); the wizard's free-text field uses
    the same path, so the refusal is a clear message there too.
 2. RecordOrInitPattern (~L37): `// record the score`, `var record = ...`, "record" in a string must not count;
    strip comments and string/char literals (incl. verbatim/raw strings) before matching.
 3. AssemblyRoot (~L101, L128-139): case-insensitive path compare on Windows so a differently-cased target still
    finds its asmdef.
 4. Program.cs help text: alignment and the blank line before "Options:".
B. NeedsFeedMigration (sdk/csharp/Exoforge.Management/ExoScaffolder.cs ~L27-32, L75-82; ExoforgeIdeProjectGenerator.cs ~L51-60, L90-92):
 1. The predicate and the cleanup must agree: needs migration only for what EnsureBuildFeed actually fixes
    (workspace nuget.config not the static .feed one; top-level extensions/<x>/nuget.config that names the exoforge
    feed without .feed). A user's own nuget.config (private feed, deeper dirs) is left alone and does not keep the
    predicate true.
 2. After one migration the next reload does nothing (no RegenerateProjectFiles); test that two consecutive checks
    after EnsureBuildFeed return false even with a user nuget.config present.
 3. Compare the workspace nuget.config ignoring line endings (CRLF checkout).
