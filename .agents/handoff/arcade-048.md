# Arcade on SDK 0.1.48 (nested errors, new tokens, versioned feed, IsExternalInit per assembly)

Project /Users/alexcs/projects/exoforge-arcade (own repo, branch master). You are a tarball user: only
Library/PackageCache/com.exoforge.sdk@*/ (0.1.48) and its CLI Editor/Cli~/exo.dll. Backend :4001 is running the
new server. Toolchain: prefix dotnet with `/Users/alexcs/.local/bin/mise exec --`. Unity only via tools/unity.sh
(`bash tools/unity.sh` compiles; `bash tools/unity.sh ArcadeSetup.SetUpAll` sets up scenes).
No workarounds: if Exoforge is wrong, leave the check failing and append it to
/Users/alexcs/projects/exoforge/.agents/samples-findings/phase3.md. Never commit Exoforge/exoforge.json or
Exoforge/mock-game-server.token.

1. Records: the SDK's IsExternalInit is internal now, so Assets/Samples/BrainrotExchange/Market.cs and
   DoodleDash/DoodleGame.cs fail CS0518. Give each sample assembly (asmdef) that declares records or init its
   own `IsExternalInit.cs`, exactly the file the SDK's Studio ▸ Settings ▸ C# Records Support button writes
   (see Library/PackageCache/com.exoforge.sdk@*/Editor/ExoforgeIsExternalInit.cs and the Management
   ExoIsExternalInit it calls: guarded #if !NET5_0_OR_GREATER, internal, System.Runtime.CompilerServices).
   Check every asmdef under Assets/Samples. `bash tools/unity.sh` must exit 0.
2. Feed: the CLI migrated the workspace to Exoforge/.feed + a static Exoforge/nuget.config (value=".feed") and
   bumps each csproj to Exoforge.Plugin.SDK 0.1.48 on build. Update .gitignore so Exoforge/nuget.config is
   committed and Exoforge/.feed/ is ignored; build every extension once with the CLI so all csproj references
   move; no per-extension nuget.config remains. Record in phase3.md whether the Unity editor did the same
   migration by itself after step 1 compiled (check before you build with the CLI).
3. Error shape is now {"status":"error","error":{"code","message","details"},"rid"} on HTTP; logs only for staff.
   Update tools/smoke/*.sh checks (they match "error":"<code>" substrings and {:code ...} strings) to read
   error.code / error.details properly (parse JSON, don't substring-match).
4. Tokens: anonymous login now returns an access token plus refresh_token; tokens look exo_<kind>_<id>.<secret>.
   Keep smoke logins working; Exoforge/mock-game-server.token holds an old (legacy, migrated) token - replace
   it with a fresh one: `exo user token usr_d8777e6e71be --expires 30d` (write only the token line to the file).
   Add one smoke check per relevant sample that an expired/garbage token gets 401 with error.code.
5. Redeploy every extension (`exo extension push <name>`), then: dotnet test Exoforge/extensions/Exoforge.Extensions.sln,
   bash tools/smoke.sh, bash tools/unity.sh ArcadeSetup.SetUpAll. All green = done.
6. README: Running-them section (records file per assembly, .feed), What-red-means rows still accurate.
Commit per topic in the arcade repo. Report <=15 lines with test/smoke/unity output via the reply command.
