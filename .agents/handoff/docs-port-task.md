# Task: port two hand-written HEEx guide sections to Markdown (write only the two output files named below)

Source: `extensions/exoforge_std_docs/lib/exoforge/std/docs/view.ex` (Phoenix HEEx, HTML with Tailwind classes).
Convert the VISIBLE TEXT and code to plain GitHub-flavoured Markdown. Do not invent, summarise or reword content; keep every
sentence, list item, table row and code block. Drop only HTML wrappers, Tailwind classes and icons. Keep `<code>` as backticks,
`<strong>` as `**`, tables as pipe tables, code blocks as fenced ```csharp / ```json etc. Callout boxes become
`> [!NOTE]` / `> [!TIP]` / `> [!CAUTION]` blockquotes. Replace HEEx expressions `{...}`/`<%= ... %>` by their literal text if they
are constants, otherwise leave a line `<!-- dynamic: <what it showed> -->`.

1. Lines 720-797 of view.ex (`subpage_how_to`, six short recipes: sign in, build and deploy, regenerate stubs, persistence and
   seed, subscribe to events, diagnose a failure). Output: `extensions/exoforge_std_docs/priv/docs/_port_recipes.md`, starting with
   `# Recipes`, one `##` per recipe.
2. The `Database Access Paradigms: Table Repository vs. Parameterized SQL` block that begins at line 2186 of view.ex and ends at
   the end of `subpage_attributes` (before line 2231). Output: `extensions/exoforge_std_docs/priv/docs/_port_db_paradigms.md`,
   starting with `## Database Access Paradigms: Table Repository vs. Parameterized SQL`.

When done run: `wc -w` on both outputs and reply with only the two paths and word counts. Do not edit view.ex or any other file.
