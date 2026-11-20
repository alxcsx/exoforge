# Q10 - wt/tooling: Haiku re-review of 60c33d4 (after Q9)
Worktree /Users/alexcs/projects/exoforge-wt/tooling. Rules: .agents/handoff/wt-common.md. Gemini model.
One test per point, failing before the fix. Reply: ask --reply t7 "Q10: <=8 lines".
1. ExoIsExternalInit.cs ~L41-42: only a DECLARATION counts. `record` followed by an identifier must be in a type
   declaration position (start of statement or after modifiers/attributes: public/internal/private/protected/sealed/
   abstract/static/partial/readonly/file/unsafe/new, `]`), optionally `record class|struct`; never after `.` and never
   before is/as/in/when/with/and/or/not/switch. `init` only as an accessor (`init;` / `init =>` / `init {`).
   Tests: `if (record is null)`, `record as X`, `x in record`, `obj.record is Y`, `var r = record switch` do not count;
   `public sealed record Foo(int A);`, `record struct P(int X);`, `[Serializable] record Bar;`, `{ get; init; }` count.
2. ExoforgeIsExternalInit.PresentPath / ExoIsExternalInit.FindInAssembly: a target outside Assets returns null (and
   the Studio shows "outside Assets/") instead of throwing from OnGUI every repaint. Ensure still refuses it.
3. Path comparisons ignore case on every OS (macOS APFS is case-insensitive by default; a wrong-case path that does
   not exist finds nothing anyway).
4. ExoScaffolder ~L233 IsStaleExoforgeNugetConfig: a config is stale only if its exoforge source points into
   Library/PackageCache/... or .../Plugins/NuGet~ (absolute), not merely because it has key="exoforge".
