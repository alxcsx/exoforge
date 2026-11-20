# Feature: bucket visibility is a property of the bucket (no addressables special case)

Repo /Users/alexcs/projects/exoforge, branch projetao_mvp. Toolchain: prefix mix/dotnet with
`/Users/alexcs/.local/bin/mise exec --`. Do NOT touch sdk/csharp/Exoforge.Plugin.SDK, the generator,
core/lib/drivers/runtime/native_extension_runner.ex (another worker owns them).

Today: players can't read files; a download needs a staff token, a signed_url, or the bucket being in
`config :exoforge_std_file_bucket, public_buckets: ["sdk"]` (file_bucket.ex:349 public_bucket?/1).
Unity Addressables (sdk/unity/sample_unity/Exoforge/extensions/unity_addressables, snake_config fallback
SnakeRemoteConfig.DownloadFileAsync) breaks because its bucket is private.

Want:
1. Each bucket has a visibility, `public` (anyone may download by URL) or `private` (default; staff, or a
   signed_url). Stored by file_bucket in its own table so it survives restarts; `public_buckets` config
   stays as the boot-time seed (sdk stays public). authorize_download reads the stored value.
2. Contract actions in core/lib/std/services.ex `file_bucket`: `set_bucket_visibility(bucket, visibility)`
   scope :studio, `list_buckets` (or extend an existing listing) returning visibility. Players still cannot
   upload, list, or read raw. An extension may set its own bucket public at start through an internal
   call (dispatch_internal / native host call) - that is the generic route addressables uses.
3. Studio: the file bucket view (find it under extensions/exoforge_std_dashboard*) shows a Public/Private
   badge per bucket and lets staff toggle it (respect docs/design/ui-standard.md; run test/ui_standard_test.exs).
4. unity_addressables (and snake_config if it reads that bucket) declare their bucket public via the generic
   route; no file_bucket code mentions addressables. Update Agents.MD file_bucket row and any skill/doc
   under sdk/unity/Exoforge.SDK/Agents~ or docs/ that describes file access.

Proof (run, paste results):
  mise exec -- mix test in extensions/exoforge_std_file_bucket, exoforge_std_http (file tests),
  exoforge_std_dashboard (dashboard_files_test + ui_standard_test). Run `mix deps.compile --force` first
  if a path dep looks stale. Tests: player 403 on private bucket, 200 after set public, 403 again after
  private; player cannot call set_bucket_visibility; persists across restart of the extension.
  Build the unity_addressables extension: mise exec -- dotnet build sdk/unity/sample_unity/Exoforge/extensions/Exoforge.Extensions.sln
Commit as "feat(file_bucket): ...". Do not push. Report <=15 lines, file:line refs, commits, results.
