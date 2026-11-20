# Fix F13: an SDK upgrade leaves every extension unbuildable (stale feed path in nuget.config)

Repo /Users/alexcs/projects/exoforge, branch projetao_mvp. Toolchain: `/Users/alexcs/.local/bin/mise exec --`.
Repro (a tarball user, /Users/alexcs/projects/exoforge-arcade): after Packages/manifest.json moved
0.1.42 -> 0.1.43 and a headless Unity import, every Exoforge/extensions/**/nuget.config still has
  <add key="exoforge" value=".../Library/PackageCache/com.exoforge.sdk@ef2c84f07731/Editor/Plugins/NuGet~" />
(the old hash dir, now deleted), so `exo extension build wallet` (tarball CLI) and `dotnet build` fail NU1301.
Writers: sdk/csharp/Exoforge.Management/ExoScaffolder.cs EnsureLocalFeed (~L189, only at scaffold) and
sdk/unity/Exoforge.SDK/Editor/ExoforgeIdeProjectGenerator.cs (~L81-180, per-dir extNuget; not run by a
headless import).

Want: upgrading the package needs no manual step on either path.
 - CLI: `exo extension build|push|test` refresh the workspace's and the extension's nuget.config feed
   (ResolveDefaultFeed) before restoring, rewriting an exoforge source whose dir no longer exists.
 - Unity: the generator also runs when the package version changes on domain reload ([InitializeOnLoad],
   compare ExoforgePackageVersion with a stored value), headless included.
 - Prefer not writing a hash path at all if the feed can be resolved relative/stably; your call, shortest diff.
Tests: Management test - a nuget.config pointing at a missing feed dir is rewritten by the build path.
Bump SDK 0.1.43 -> 0.1.44 (package.json + ExoforgePackageVersion.cs), then `just pack-unity` with
COPYFILE_DISABLE=1, check `tar tzf dist/com.exoforge.sdk-0.1.44.tgz | grep -c '/\._'` is 0.
Proof: dotnet test sdk/csharp/Exoforge.Management.Tests; then in the arcade copy the tgz to Packages/,
set manifest to 0.1.44, run `bash tools/unity.sh` (exit 0), then the NEW tarball CLI
`dotnet Library/PackageCache/com.exoforge.sdk@*/Editor/Cli~/exo.dll extension build wallet` succeeds
with no hand edit of any nuget.config. Do not edit arcade source otherwise; other workers own it.
Commit in exoforge "fix(sdk): ..."; do not push. Report <=15 lines.
