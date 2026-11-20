# Findings — doodle (level_share, Doodle Dash)

Repo lookups I had to make (a tarball user couldn't): `extensions/exoforge_std_file_bucket/lib/exoforge/std/file_bucket.ex`
and `extensions/exoforge_std_http/lib/exoforge/std/http/router.ex` (doodle-4, doodle-5, doodle-6).

### doodle-1 — `exo extension new` offers one template, the docs list four, and a second `new` overwrites silently
- **Kind**: contradiction
- **Where**: package skill `exoforge-extensions` §2 and `Agents~/AGENTS.md` (`--template persistent|basic|config|events`) vs `exo extension new --help`
- **What**: help says `Usage: exo extension new <name> [--template standard]` and `--template <t>   standard (default)`. `--template persistent` is accepted and printed as "Scaffolded C# extension 'level_share' (persistent)". Running `new level_share` again, with the extension already there, printed "Scaffolded … (standard)" and replaced `src/LevelShareExtension.cs` with no error and no prompt. The help also tells the user to run `just pack-sdk`, a repo recipe.
- **Impact**: someone re-running `new` loses their extension source; someone picking a template can't tell which names are real.
- **Workaround in the sample**: wrote the extension from scratch.
- **Suggested fix**: one template list in help and docs; refuse when `Exoforge/extensions/<name>` exists; drop the `just` mention.

### doodle-2 — The skill's extension sample doesn't compile (`Exo.Events.Publish`)
- **Kind**: doc-wrong
- **Where**: package skill `exoforge-extensions` §3 (`Exo.Events.Publish("daily_rewards.claimed", new { … })`)
- **What**: `dotnet build` against the packaged SDK: `error CS1061: 'IEventDispatcher' does not contain a definition for 'Publish'`. The real API is the extension method `Exo.Events.EmitAsync(record, topic?)` on a record marked `[ExoEvent("name", Topic = "…")]` (that is what the in-project sample extensions use). In the same snippet `[ExoService(...)] public partial class`, `Exo.Database.Get<T>("table", key)` and `Put("table", key, value)` compile. The README's scaffold uses the shorter `Get<T>(key)` / `Put(record)`, and the skill says `Exo.Database` has `Execute`/`Query` but not that both forms exist (matches F3/F4, now verified: Publish is the one that's wrong).
- **Impact**: first compile error for anyone, or any agent, following the skill.
- **Workaround in the sample**: `EmitAsync(...).GetAwaiter().GetResult()`.
- **Suggested fix**: replace `Publish` with an `[ExoEvent]` record + `EmitAsync` in the skill, and say actions are synchronous.

### doodle-3 — The default scope of `[ExoAction]` is stated two ways
- **Kind**: contradiction
- **Where**: skill `exoforge-extensions` §3 ("default or omitting scope permits public calls") vs the SDK XML doc `ExoActionAttribute.Scope` ("Defaults to \"player\" (requires player or higher authentication)")
- **What**: not tested at runtime (I always set `Scope`); the two statements can't both be true.
- **Impact**: an extension author can expose an action to the public by leaving the scope out, or the other way round.
- **Workaround in the sample**: every action sets `Scope` explicitly.
- **Suggested fix**: decide, then fix whichever side is wrong; see F6.

### doodle-4 — The file bucket has no client contract, no docs, and no tags
- **Kind**: missing
- **Where**: README §4 ("PNG goes to the file bucket with tags (`difficulty:hard`) and metadata"); `exo contracts` / `ExoforgeServices.g.cs`; docs chapters 01–04
- **What**: `exo extension list` shows `exoforge_std_file_bucket` with `"services": []`, so no `file_bucket` contract, no `ExoServices.*` stub. None of the four chapters served by `docs.get_chapter`, nor the package README, skills or `Samples~`, says how to upload or download. What exists, found by reflection on `Exoforge.Client.dll` and the repo's router: `ExoClient.UploadFileAsync(bucket, filename, bytes, contentType, metadata)`, `DownloadFileAsync(bucket, id, filename)` / `DownloadFileAsync(url)`, `POST /api/files/upload` (multipart `file`, or JSON `filename` + base64 `content`; `bucket`, `metadata`), `GET /api/files/<bucket>/<id>/<filename>`, and `exo call file_bucket upload_file|list_files|get_file_info|read_file|delete_file`. There is **no tag concept**: only free-form `metadata` (values come back as strings) and a bucket name. There is **no size limit** in the bucket; the only cap is the HTTP body limit of 100 MB (`router.ex:20`).
- **Impact**: the README's "tags" feature can't be done as written, and a developer can't discover uploads from the docs at all.
- **Workaround in the sample**: tag kept as a column on the `levels` row (`difficulty:hard`), the file's `metadata` carries author/width/height, the Unity bridge uses `ExoforgeSDK.Client.UploadFileAsync`.
- **Suggested fix**: a file-bucket chapter and a contract for it; either add `tags` or drop them from the README.

### doodle-5 — Any signed-in player can copy any server file into the bucket and download it
- **Kind**: bug (security)
- **Where**: `exoforge_std_file_bucket/lib/exoforge/std/file_bucket.ex` `upload_file` / `resolve_binary_data` (the `path` parameter)
- **What**: with an anonymous player token, `POST /api/file_bucket/upload_file` with `{"bucket":"x","filename":"h.txt","path":"/etc/hosts"}` returned 200 and a file record; `GET /api/files/x/<id>/h.txt` served it (checked, then deleted by me). The action takes any server-side path and the scope isn't restricted. Responses also leak `disk_path`. `GET /api/files/…` needs no token.
- **Impact**: arbitrary file read on the cluster host for every player, e.g. `.env`, tokens, the DB.
- **Workaround in the sample**: none possible; the sample uses the bucket as shipped.
- **Suggested fix**: accept `path` only for internal/admin calls; restrict `upload_file` scope; drop `disk_path` from responses.

### doodle-6 — Which route does `browse` have for `curl`? Only the router source says
- **Kind**: missing
- **Where**: README §4 ("the same catalog is reachable over plain HTTP"); package docs say nothing about HTTP
- **What**: every action is `POST /api/<service>/<action>` with `Authorization: Bearer <token>` and a JSON body (`router.ex:274`); there is no GET. A player token comes from `POST /api/auth/anonymous {"name":"…"}`. The envelope is `{"data":…,"status":"ok","rid":…,"logs":[…]}`, while `exo call` prints the bare data. `curl -X POST localhost:4001/api/level_share/browse -H "authorization: Bearer $T" -H 'content-type: application/json' -d '{"tag":"difficulty:hard","sort":"top","limit":5}'` works (see `tools/smoke/doodle.sh`). Without a token the root answers `401 unauthenticated … Use POST /api/auth/login or /api/auth/register`, which doesn't mention `/anonymous`.
- **Impact**: nobody can write the `curl` demo from the docs.
- **Workaround in the sample**: the route above, in the smoke script.
- **Suggested fix**: document the HTTP surface (route, auth, envelope) in the quickstart.

### doodle-7 — A record wrapping a list comes out as `JsonElement` in the stubs; a bare list is typed
- **Kind**: confusing
- **Where**: generated `ExoforgeServices.g.cs`
- **What**: `Browse` returning `record BrowseResult(IReadOnlyList<LevelSummary> Levels)` generated `public JsonElement Levels`. Returning `List<LevelSummary>` directly generated `Task<List<LevelSummary>> BrowseAsync(...)` with a typed `LevelSummary` class. Neither is documented.
- **Impact**: typed API silently degrades to raw JSON.
- **Workaround in the sample**: `Browse` returns `List<LevelSummary>`.
- **Suggested fix**: type nested records/lists in stubs, or document the rule.

### doodle-8 — Result types land in the global namespace with bare names
- **Kind**: bug
- **Where**: generated stubs: `public class PublishResult`, `RateResult`, `ClearResult` (taken from the C# return record name)
- **What**: request types are prefixed with the service (`LevelSharePublishRequest`), response types are not, so two extensions each returning `ClaimResult` / `ClearResult` collide in `Exoforge.Generated`.
- **Impact**: a second sample with the same record name breaks the project's compile, and names look unrelated to the service.
- **Workaround in the sample**: records named `Level…Result`.
- **Suggested fix**: prefix response types with the service, like requests.

### doodle-9 — Errors are rendered as Elixir tuples
- **Kind**: confusing
- **Where**: `exo call level_share publish …` and the HTTP envelope
- **What**: `ExoActionException("clear_required", "Clear the level…")` comes back as `{"error":"{:clear_required, \"Clear the level yourself before publishing it.\"}", …}`; the CLI prints `[http_error] {:clear_required, "…"}` and exits 1. The code isn't a separate field, so a `curl` user has to parse an Elixir term. Verified with `Exoforge.Client.dll` over WebSocket: the client throws `ExoActionException` with `Code == "http_error"` and `Message == "[http_error] {:clear_required, \"Clear the level…\"} (rid r_…)"`. The extension's own code `clear_required` never reaches `Code`, so Unity code can't branch on it.
- **Impact**: scripts and non-Unity clients can't branch on the error code.
- **Workaround in the sample**: the bridge shows `Message` (it contains the code); the smoke script prints the raw error.
- **Suggested fix**: `{"error":{"code":…,"message":…}}`, and `ExoActionException.Code` = the extension's code.

### doodle-10 — Testing helpers exist but no tarball doc mentions them
- **Kind**: missing
- **Where**: package README, skills, `Agents~/AGENTS.md`; only the SDK XML mentions `ExoTestHost`
- **What**: `ExoTestHost.Start("level_share")` → `ExoTestContext` with `Database`, `Events`, `Actions`, `Logger`, `CallerPlayerId` (settable), `Create<T>()` works from the tarball: 11 tests pass with xunit + `Exoforge.Plugin.SDK` and the extension project referenced. `InMemoryDatabase` supports `Get/Put/All` by table name; I did not use `Query`. A test project needs the same `nuget.config` as the extension (absolute PackageCache path, see F13) and its own `net10.0` target.
- **Impact**: nobody finds them unless they read the XML doc.
- **Workaround in the sample**: used as is, `level_share.Tests/`.
- **Suggested fix**: a "Testing" section in the skill, and `exo extension new` can scaffold a test project.

### doodle-11 — `record` doesn't compile in a game asmdef: `IsExternalInit` is internal to the SDK
- **Kind**: confusing
- **Where**: `Runtime/IsExternalInit.cs` in the package (internal to `Exoforge.SDK`); Unity 6000.6 asmdefs
- **What**: any asmdef of the game that declares `public record Foo(string A)` fails with `error CS0518: Predefined type 'System.Runtime.CompilerServices.IsExternalInit' is not defined or imported` (hit in `Samples.DoodleDash` and, at the same time, `Samples.BrainrotExchange`). The extension side (.NET 10) has no such problem, and the README sample uses `ExoSession` (a record) only as a consumer, so nothing warns about it.
- **Impact**: the "records for payloads" style the SDK itself uses can't be copied into gameplay code without a polyfill.
- **Workaround in the sample**: a public shim in `Assets/Samples/Common` (t7), referenced by every scene asmdef.
- **Suggested fix**: ship a public/`InternalsVisibleTo`-free polyfill asmdef, or note it in the README.

### doodle-12 — `ExoServices` and `ExoforgeSDK` live in different namespaces, and the docs only show one `using` set
- **Kind**: confusing
- **Where**: package README quickstart (`using Exoforge.Client; using Exoforge.Client.Unity;`); generated stubs (`ExoServices` in `Exoforge.Client`, in asmdef `Exoforge.Generated`); `ExoforgeSDK` in `Exoforge.Client.Unity`, asmdef `Exoforge.SDK`
- **What**: a gameplay asmdef has to reference both `Exoforge.SDK` and `Exoforge.Generated` by name; the README never says that an asmdef-using project needs them, and the Unity API profile lacks `Convert.ToHexString` / `SHA256.HashData`, which matters for anyone hashing level data client-side.
- **Impact**: first compile of any game code placed in an asmdef fails (`CS0103 ExoforgeSDK`, `CS0246`) until the references and usings are right.
- **Workaround in the sample**: asmdef references `Exoforge.SDK`, `Exoforge.Generated`, `Samples.Common`, `Unity.InputSystem`.
- **Suggested fix**: one README paragraph on asmdef references.

### doodle-13 — `ExoClient.UploadFileAsync(..., metadata)` makes the server answer 500 with an empty body
- **Kind**: bug
- **Where**: `Exoforge.Client.dll` `UploadFileAsync` (sends the metadata dictionary as one multipart field `metadata` holding a JSON **string**) vs `POST /api/files/upload` + `file_bucket.upload_file` (expect `metadata` as a map)
- **What**: `curl -i -F bucket=doodle_levels -F file=@level.png -F 'metadata={"author":"rt","width":32}' …/api/files/upload` → `HTTP/1.1 500 Internal Server Error`, `connection: close`, no body. The same upload without `metadata` → `201`. The client then calls `JsonDocument.Parse("")` and throws `JsonReaderException: The input does not contain any JSON tokens`, a message that mentions neither upload nor metadata. A `metadata[author]=…` form (a map) works, which the .NET client can't send. A client also needs `HttpBaseUri` set, else `InvalidOperationException: HttpBaseUri is not set on ExoClient`; the Unity `ExoforgeManager` sets it, a bare `ExoClient` doesn't.
- **Impact**: README §4's "metadata (author, width, height)" breaks on the first upload from Unity.
- **Workaround in the sample**: upload without metadata, then `SendActionAsync("file_bucket", "update_file", {bucket, id, metadata})`, which stores a real map.
- **Suggested fix**: client sends `metadata[key]` fields (or the server decodes a JSON string), and the server never returns an empty 500.

### doodle-14 — Any player can update or delete any file; names are claimed first-come
- **Kind**: bug (security)
- **Where**: `file_bucket.update_file` / `delete_file` called with an anonymous player token via `POST /api/file_bucket/…`
- **What**: `update_file` with someone else's file id succeeded for a different anonymous player; there is no owner on a file record. Also `POST /api/auth/anonymous {"name":"rt"}` answers `{"error":":name_taken"}` once any player has used the name, so an anonymous sign-in by name can fail (and the error is an Elixir atom string again, see doodle-9).
- **Impact**: published levels can be overwritten or deleted by anyone who knows the id (the ids are in `browse`).
- **Workaround in the sample**: none.
- **Suggested fix**: store the uploader's id and check it; restrict `delete_file`/`update_file` to the owner or admin.

### doodle-15 — Calling another service from an extension needs `[ExoDependency]`, which the skills never mention
- **Kind**: missing
- **Where**: skill `exoforge-extensions` (no mention); only docs chapter 02 shows `[ExoDependency("player_data")]`, as a boot-order hint
- **What**: `Exo.Actions.CallAction<JsonElement>("file_bucket", "get_file_info", …)` from `Publish` fails at runtime, not at build: `InvalidOperationException: Service 'file_bucket' is not declared in this extension's dependencies. Add 'file_bucket' to your extension dependencies and regenerate stubs.` The fix is `[ExoDependency("file_bucket")]` on the class. The message says "regenerate stubs", which isn't the fix, and chapter 02 describes the attribute as boot order and "client stub generation scope", not as a permission to call.
- **Impact**: the first cross-service call compiles, passes unit tests (the in-memory dispatcher doesn't check) and fails only on the cluster.
- **Workaround in the sample**: `[ExoDependency("file_bucket")]`, `[ExoDependency("player_data")]`.
- **Suggested fix**: document it in the skill; make `InMemoryActionDispatcher` enforce declared dependencies.

### doodle-16 — After a push the extension can end up `crashed: startup_failed … timeout` with no startup hook
- **Kind**: bug (flaky, seen once)
- **Where**: `exo extension push level_share` with two `[ExoDependency]` declared, while other workers were deploying to the same cluster
- **What**: `push` printed `Verified: 0.1.0+6.5a0f3760 loaded (native)` and the first action answered, then calls returned `{:extension_starting, :level_share}`, then `[http_error] {:extension_crashed, {:startup_failed, %{code: "timeout", message: "the startup hook did not finish"}}}`. The extension has no `OnExtensionStart`. `exo extension list` showed `status: crashed: …`. `exo extension reload level_share` brought it back.
- **Impact**: a green push isn't proof the extension stays up; the error is an Elixir term.
- **Workaround in the sample**: `exo extension reload`.
- **Suggested fix**: `push` should wait for the boot to settle; say what the "startup hook" is and why it timed out.

### doodle-17 — `get_file_info` is the only way to trust a client-supplied file id, and it has no contract
- **Kind**: missing
- **Where**: `file_bucket.get_file_info`, used by `level_share.Publish` to take sha256, content type and url from the file instead of from the client
- **What**: the record carries `sha256` computed by the bucket from the stored bytes, which lets the server tie a recorded clear to the exact image. The response shape (`{"file": {id, bucket, sha256, content_type, url, …}}`) is documented nowhere, so the extension reads raw `JsonElement`. The client has to hash the same bytes (`SHA256` of the PNG it uploads) to record the clear.
- **Impact**: trusted-file patterns are guesswork without a typed contract.
- **Workaround in the sample**: raw `JsonElement` read in `Publish`.
- **Suggested fix**: publish a `file_bucket` contract with typed responses.

---
## After server commit acc8d06 (players locked out of the file bucket)

Verified against the live backend: player `POST /api/files/upload` → 403; player `file_bucket.upload_file` → `forbidden_scope`; anonymous and player `GET /api/files/<bucket>/<id>/<name>` → 403; `ExoClient.UploadFileAsync` → `[upload_failed] forbidden_scope`; `DownloadFileAsync(bucket, id, name)` → `[download_failed] HTTP 403`. doodle-5 and doodle-14 (arbitrary `path` read, anyone updates/deletes files) are **resolved** by this; doodle-13 (client metadata → 500) is moot for players, still true for staff. doodle-4 changes: the contract exists now (`file_bucket` has typed stubs, `signed_url` and `authorize_download` are scope `server`, the rest `studio`). level_share now owns the rules: `upload_level` (PNG signature, IHDR exactly 32x18, ≤ 4096 bytes, ≤ 25 uploads per player, stored through `file_bucket.upload_file` with author/size metadata taken server-side), `publish` only for the caller's own upload, `get_level_url` returns a 300 s signed URL.

### doodle-18 — The generated `ExoServices` caches the first dispatcher in a static, so extension unit tests leak into each other
- **Kind**: bug
- **Where**: `src/Generated/PluginServices.g.cs` (`ExoServices.Services` is built once from `Context.Actions`; `ExoServices.Reset()` exists but nothing says when to call it)
- **What**: with `ExoTestHost.Start` per test and a fake `file_bucket.upload_file` that counts calls, the second test got ids from the first test's fake (`Expected "fl_1", Actual "fl_11"`): its `ExoServices.FileBucket` still pointed at the first test's `InMemoryActionDispatcher`. Calling `ExoServices.Reset()` at the start of each test fixes it. 22 of 24 tests passed and 2 failed with that message, a failure that looks like a bug in the extension.
- **Impact**: flaky or order-dependent tests for anyone using the typed stubs from an extension.
- **Workaround in the sample**: `ExoServices.Reset()` in the test fake setup.
- **Suggested fix**: `ExoTestHost.Start` resets the stubs (and `Dispose` does too), or `Services` reads the current dispatcher each time.

### doodle-19 — No client method downloads a signed URL; `DownloadFileAsync(string)` takes a file id and escapes it
- **Kind**: bug / confusing
- **Where**: `Exoforge.Client.dll` `ExoClient.DownloadFileAsync(string fileId, …)` builds `/api/files/{Uri.EscapeDataString(fileId)}`; the doc comment says "by its ID"
- **What**: passing the `url` that `file_bucket.signed_url` returns (`/api/files/doodle_levels/<id>/<name>.png?exp=…&sig=…`) gives `ExoActionException: [download_failed] HTTP 404`: the `?` and `&` are escaped and the signature is lost. The same URL from `curl` gives 200. (My earlier doodle-4 note said `DownloadFileAsync(url)` worked; it worked only while the route happened to accept the escaped path; wrong, and the argument is an id.) What works: `client.HttpClient.GetByteArrayAsync(new Uri(client.HttpBaseUri, signedUrl))` (both are public). Signed URLs need no `Authorization` header.
- **Impact**: the flow the server now prescribes (signed URL, then download) has no SDK call, and the obvious overload fails with a bare 404.
- **Workaround in the sample**: `HttpClient` + `HttpBaseUri` in `DoodleBridge`.
- **Suggested fix**: `DownloadUrlAsync(string url)` that resolves a relative URL against `HttpBaseUri` and keeps the query; or have the `FileId` overload accept signed URLs.

### doodle-20 — The generated extension stubs: wrong regenerate command, shadowed statics, everything optional is a `JsonElement`
- **Kind**: confusing
- **Where**: `exo extension stubs level_share` → `src/Generated/PluginServices.g.cs`
- **What**: (a) the header says "Regenerate with `exo plugin stubs <name>`"; the command is `exo extension stubs` (F5/F9 family: the old name). (b) The file, which lives inside the user's project, declares `Exoforge.Plugin.SDK.ExoServices` and `Exoforge.Plugin.SDK.Exo` static classes next to the SDK's own, and the build still passes, so which `Exo` a call binds to isn't obvious. (c) Every optional request field (`bucket`, `content`, `ttl_seconds`, `metadata`) is a `JsonElement`, so setting one needs `JsonSerializer.SerializeToElement(value)`; responses with nested objects (`file`) are `JsonElement` too (compare doodle-7). (d) The generated file is part of the extension source and has to be committed or regenerated after every contract change.
- **Impact**: the typed stub for `file_bucket.upload_file` is less typed than the raw call.
- **Workaround in the sample**: a small `Json(object)` helper; `Text(JsonElement, name)` for the response.
- **Suggested fix**: emit real C# types for optional and nested fields; fix the header.

### doodle-21 — The smoke's 403 checks show the refusals but the server answers them differently
- **Kind**: confusing
- **Where**: `tools/smoke/doodle.sh`
- **What**: the same refusal is `403` with an empty/other body for `POST /api/files/upload` and for `GET /api/files/…`, `forbidden_scope` inside a `{"error":…}` JSON for `POST /api/file_bucket/upload_file` (HTTP status checked only for the first two), and `[upload_failed] forbidden_scope` / `[download_failed] HTTP 403` from the .NET client.
- **Impact**: four shapes for one rule; scripts and clients need to know all four.
- **Workaround in the sample**: the script asserts the status code for HTTP routes and the `forbidden_scope` text for the action.
- **Suggested fix**: one error shape (see doodle-9).
