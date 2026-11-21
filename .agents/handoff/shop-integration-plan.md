# 2d-shop integration plan (2026-11-20)

Goal: the shop sample shows (1) typed stubs between extensions, (2) ORM-style resources, (3) foreign keys usable in code and Studio.

## Findings
- loja_itens/inventario call `ExoServices.Actions.CallAction<T>("items","listar_catalogo",null)` (string names). brainrot_market already uses `ExoServices.Wallet.CreditAsync(...)` stubs.
- Resources use `Database.Query<T>("SELECT ... WHERE x = $1")`; `DatabaseTable<T>` (sdk/csharp/Exoforge.Plugin.SDK/DatabaseExtensions.cs ~400) has Get/All/Put/Delete/Query only.
- Manifest emits `foreign_key` and `references` ("itens.id") per column (ManifestEmitter.cs:276). Dashboard only links columns with a `role` via :resource_column hooks (generic_extension_view.ex ~782); no FK links or pickers. Row deep link exists: `/resources/<name>?focus=row:<id>`.

## Workstreams (parallel; review afterwards by a different model family)
A. omp (free) — stubs: replace every string CallAction in extensions/{loja_itens,inventario} with generated stubs (ExoServices.Items.*, ExoServices.Inventario.*), keep behaviour, regenerate stubs, update tools/smoke/shop.sh only if needed. Files: exoforge-arcade/extensions/{loja_itens,inventario}.
B. codex — ORM layer in Exoforge.Plugin.SDK (C#): typed `Where(x => ...)` (LINQ expression → parameterised SQL for ==, !=, <, >, &&, ||, !, bool members), `FindBy`, `Count`, `Exists`, ordering/limit, and FK navigation resolved from `[ExoColumn(ForeignKey, References / ReferencesType)]`: `table.Include(x => x.ItemId)` or `Ref<T>` helper that loads the referenced row via the typed repository (same extension) or the owning extension's stub. Tests in Exoforge.Plugin.SDK.Tests. Files: sdk/csharp/Exoforge.Plugin.SDK only.
C. claude — Studio FK UX (Elixir): a column with `references: "<resource>.<col>"` renders as a link to `/resources/<resource>?focus=row:<value>` (resolve the resource across extensions by table/resource name), show the referenced row's label in a tooltip when cheap, FK input in create/edit forms as a select/picker over the referenced resource, reverse "referenced by" list in the row drawer. Files: extensions/exoforge_std_dashboard/lib/exoforge/std/dashboard/{resource_live,generic_extension_view,resource_forms}.ex + tests + guide page.
D. after A+B (omp then reviewed by claude) — shop refactor to the ORM API: LojaOferta/InventarioItem/Item use Where/Include, no SQL strings; add a smoke assertion.
E. Review: B reviewed by claude, C reviewed by codex, A/D reviewed by claude. Then run `tools/smoke.sh --reset shop`.
