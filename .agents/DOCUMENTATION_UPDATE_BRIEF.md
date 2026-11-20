# Documentation Audit and Diátaxis Update

Perform a repository-grounded documentation audit and update. Do not consult external websites or copy from external sources.

## Confirmed brief

- Primary document type: Tutorial
- Audience: Unity/C# developers new to Exoforge
- Reader goal: Create, deploy, generate client stubs for, and call a native C# extension from Unity
- Scope: Audit and update the full Developer Guide, prioritizing the Quickstart Flow. Include the current SDK/CLI, lifecycle hook, authentication, extension build/deploy, stubs, and Unity usage. Exclude unrelated backend internals and new feature design.

## Diátaxis structure

1. **Tutorial — Quickstart Flow**
   - Prerequisites and supported toolchain
   - Create/open a Unity project and connect with `ExoforgeSDK.Auth`
   - Scaffold a native C# extension
   - Implement a typed action and optional `OnExtensionStart()` hook where useful
   - Build/deploy with the current `exo` CLI or Studio workflow
   - Generate typed client stubs
   - Call the service from Unity and verify the result
   - Include recovery notes only where needed to complete the tutorial

2. **How-to material**
   - Anonymous authentication and display names
   - Build/deploy or push an extension
   - Regenerate service stubs
   - Add persistence/resources
   - Subscribe to events
   - Diagnose action/deployment failures

3. **Reference material**
   - C# attributes and action modes
   - Manifest fields and generated client surface
   - Authentication APIs and lifecycle hook
   - Protocol/capability details where already exposed to extension authors

4. **Explanation material**
   - Architecture and “what you can build” sections
   - Keep rationale separate from step-by-step procedures
   - Remove or qualify stale claims that cannot be supported by repository evidence

## Required audit

Read the current implementation and documentation before editing. At minimum inspect:

- `extensions/exoforge_std_docs/lib/exoforge/std/docs/view.ex`
- `extensions/exoforge_std_docs/lib/exoforge/std/docs/markdown.ex`
- `extensions/exoforge_std_docs/lib/exoforge/std/docs/architecture_graph.ex`
- `extensions/exoforge_std_docs/lib/exoforge/std/docs.ex`
- `extensions/exoforge_std_docs/test/`
- `docs/`
- `AGENTS.md`
- Current C# SDK, Unity SDK, management CLI, generator, and extension examples referenced by the guide
- Existing documentation tests and any codegen/scaffolding tests that pin command/API behavior

Inventory each existing section before changing it. Classify it as tutorial, how-to, reference, or explanation, then correct:

- Commands, paths, package/version numbers, API names, attribute names, action modes, generated code, and Unity usage.
- Authentication flow: `ExoforgeSDK.Auth.LoginAnonymously()` followed by `SetDisplayName`, not raw anonymous RPCs.
- Framework-dependent native extension workflow and current `exo extension build`, `push`, and `stubs` commands.
- Manifest and generated stub behavior.
- Optional `OnExtensionStart()` lifecycle behavior without presenting it as a required attribute.
- Outdated “6 patterns”/counts/claims, broken links, duplicate terminology, and mixed tutorial/reference instructions.
- Empty states and headings so each page has a clear next action and useful structure.

Use the project’s existing terminology: “extension”, not “plugin”, unless discussing a compatibility symbol that genuinely still exists.

## Editing constraints

- Keep all content in the existing Developer Guide/docs implementation unless a new small backing file is required by existing conventions.
- Follow `docs/design/ui-standard.md` for any HEEx classes touched; do not reintroduce `dark:`, retired hues, banned radii, gradients, or unremapped tinted backgrounds.
- Preserve functional LiveView events, anchors, code-copy behavior, PDF export, and syntax highlighting.
- Keep tutorial steps runnable from a clean checkout and make prerequisites explicit.
- Prefer short, direct copy and complete code examples. Do not invent APIs, routes, commands, or screenshots.
- Do not alter unrelated backend behavior.
- Do not stage or commit `.agents/`, `sdk/unity/Exoforge.SDK/Editor/Cli~/`, or `skills-lock.json`.

## Verification

Run focused checks after editing:

- `cd extensions/exoforge_std_dashboard && mix test test/ui_standard_test.exs`
- `cd extensions/exoforge_std_docs && mix test`
- `cd extensions/exoforge_std_dashboard && mix test`
- Relevant C# SDK/generator/management tests for any command or API corrections.
- Search for stale `plugin` terminology, old SDK versions, obsolete command names, broken internal links, and code snippets that no longer match current APIs.
- Run `mix format` on changed Elixir files.

Do not run live E2E unless a focused documentation test requires it.

## Commit and report

Commit only the finished tracked documentation/source changes with explicit paths after tests pass. Do not commit this brief.

Use:

`Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>`

Report to terminal `t17`:

`REPORT: documentation update done, <Diátaxis scope>, <tests>, <commit sha>; <remaining unverifiable items>`
