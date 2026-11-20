# Documentation and Quickstart Follow-up

## Objective

Revise the Developer Guide after user review. The primary audience is Unity/C# developers using
Exoforge Studio, not repository operators or CLI users.

## Required changes

### Quickstart

- In “Before you start”, remove the requirement for a running/self-hosted cluster and all `just dev`
  or localhost instructions. The hosted Exoforge workflow is the default and self-hosting should not
  be encouraged here.
- Link the official .NET SDK download page and state that .NET 9 is the minimum required version.
- Remove the `exoforge.json` prerequisite; installing/configuring the extension through Unity Studio
  should be sufficient.
- Keep the tutorial Unity Studio-first. Remove `exo` CLI commands and CLI-only workflow from the
  Quickstart; describe the equivalent Studio actions instead.

### How-to

- Make every code snippet use the existing syntax-highlighting helper correctly, matching the
  rendering approach already used elsewhere in the docs.
- Remove CLI commands and describe Unity Studio workflows for authentication, build/deploy, sync,
  persistence/lifecycle, event subscriptions, and diagnostics.

### Hero and UI

- Fix the Quickstart hero layout on wide screens: the left and right content should be visually
  centered with balanced space rather than drifting toward opposite edges. Preserve responsive
  behavior and existing design tokens.
- Investigate why code snippets have incorrect syntax highlighting across the guide and fix the
  shared rendering/helper or its call sites, not just one example.

### C# attributes reference

- Re-audit the complete reference against:
  `sdk/csharp/Exoforge.Plugin.SDK/Attributes.cs`,
  `sdk/csharp/Exoforge.Plugin.Generator/ExoforgePluginGenerator.cs`, and relevant generator tests.
- Document newly available attributes and related surfaces, including (where applicable) the
  `ExoExtension`, `ExoWebhook`, `ExoCron`, `ExoDependency`, `ExoFileReference`, and
  `ExoInputType` attributes, plus `ExoInput`/`ExoRole` constants and newly supported properties.
- Correct stale defaults, names, examples, and terminology. Keep the reference technically precise.

## Constraints

- Do not invent hosted service URLs or claims not supported by the repository. Use a link to the
  official .NET download page only as requested.
- Preserve the Diátaxis split: Quickstart is a tutorial, How-to is task recipes, attributes and
  protocol are reference, and use cases/architecture are explanation.
- Do not add CLI instructions to the Unity-facing Quickstart or How-to page.
- Keep `.agents/`, `sdk/unity/Exoforge.SDK/Editor/Cli~/`, and `skills-lock.json` untracked.
- Avoid inline raw C# containing `<`/`>` directly in HEEx text; use the existing safe highlighted
  rendering helper or prose so the LiveView compiler remains valid.
- Add/update focused docs tests for the new How-to/reference content if needed.

## Verification and delivery

Run:

- `cd extensions/exoforge_std_docs && mix test`
- `cd extensions/exoforge_std_dashboard && mix test test/ui_standard_test.exs`
- `cd extensions/exoforge_std_dashboard && mix test`

Inspect the final diff for stale CLI/self-hosting claims and incorrect API names. Commit only the
documentation/UI source and focused docs tests, include the standard Copilot co-author trailer,
push `projetao_mvp`, and report the commit SHA and tests to this orchestrator.
