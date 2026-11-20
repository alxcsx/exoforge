# Web UI Improvement Pass

You are the implementation worker. Perform a read-only audit first, then implement the confirmed improvements in the same pass.

## Scope

Review the Producer Studio web UI, with special attention to:

- `extensions/exoforge_std_docs/lib/exoforge/std/docs/view.ex`
- `extensions/exoforge_std_dashboard/lib/exoforge/std/dashboard/`
- `extensions/exoforge_std_dashboard_views/lib/exoforge/std/dashboard_views/`
- `extensions/exoforge_std_dashboard/priv/static/vendor/exoforge-studio.css`
- `docs/design/ui-standard.md`
- `extensions/exoforge_std_dashboard/test/ui_standard_test.exs`

Inspect all dashboard/docs templates, not only the locations listed below. Include light/dark theme behavior, keyboard-visible states, reduced motion, narrow layouts, empty states, and representative modal/drawer states. Do not claim browser-rendered results unless you can actually verify them.

## Known issues to confirm and fix

1. **Light-theme contrast in Developer Guide**
   - `exoforge_std_docs/lib/exoforge/std/docs/view.ex` around lines 618–649 uses pale `bg-blue-50` / `bg-primary-50` surfaces with `text-white`, `text-gray-300`, and `text-blue-300`.
   - Replace with the project’s tinted-surface pairing or an appropriate `.exo-hero` surface. Preserve dark-mode remapping and remeasure the rendered light-theme pairs.

2. **Keyboard visibility for code-copy buttons**
   - Around lines 909, 964, 1019, 1073, and 1127, code-copy buttons are `opacity-0 group-hover:opacity-100`.
   - Ensure keyboard focus makes them visible and gives them a clear `focus-visible` ring. Use existing project tokens/classes; do not add a custom framework.

3. **Reduced-motion support**
   - The docs use inline `window.scrollTo({behavior: "smooth"})` in tab and deep-link controls, including around lines 126–176, 216, 399, 634, and 659.
   - Gate smooth scrolling behind `prefers-reduced-motion`, using instant scrolling when reduction is requested. Search the rest of the Studio for equivalent ungated motion.

4. **UI standard drift**
   - Replace `transition-all` with named transitions wherever only colors/opacity change.
   - Use `rounded-lg` for buttons, inputs, and small controls; keep `rounded-xl` for cards/panels.
   - Preserve intentional existing exceptions and do not mechanically change cards or modals.

5. **Documentation copy**
   - Correct the “6 production-grade C# patterns” claim if only five are presented.
   - Improve the API catalog empty state so it provides a direct next action/link to scaffolding or deployment where a real route/component exists.

6. **Typography consistency**
   - Review remaining `font-bold`/ad-hoc hierarchy in the docs and dashboard templates. Use the documented `font-normal` / `font-medium` / `font-semibold` roles where this is clearly interface text, without changing code samples or intentional display treatment.

## Constraints

- Follow `docs/design/ui-standard.md`; the dark theme uses the CSS remap, not `dark:` variants.
- Reuse existing `.exo-*` components/tokens and existing icon helpers.
- Do not add a new color system, radius scale, UI framework, or broad unrelated refactor.
- Use semantic native controls and preserve existing LiveView behavior.
- Keep fixes surgical. Do not alter generated artifacts or unrelated worktree changes.
- Preserve the user’s existing untracked `.agents/`, `sdk/unity/Exoforge.SDK/Editor/Cli~/`, and `skills-lock.json`; do not stage them.
- If an empty-state destination does not exist, improve the copy without inventing a route and report that limitation.

## Verification

Run the smallest relevant checks after editing:

- `cd extensions/exoforge_std_dashboard && mix test test/ui_standard_test.exs`
- The affected extension test suites or targeted tests for changed LiveView components.
- Any formatter/check command already used by the repository for changed Elixir/CSS.
- Use static checks for forbidden classes, missing focus-visible states, ungated smooth scrolling, and tinted background remaps.

Do not run live E2E unless a focused test requires it.

## Commit and report

Commit only the finished tracked implementation with explicit paths after tests pass. Do not commit this brief.

Use the repository co-author trailer:

`Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>`

Report to terminal `t17`:

`REPORT: UI improvement pass done, <audit scope>, <tests>, <commit sha>; <remaining limitations>`
