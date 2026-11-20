# wt/errors: one nested error shape on every surface  (worktree /Users/alexcs/projects/exoforge-wt/errors)
Read wt-common.md first. Today HTTP replies flat {"status":"error","error":"<code>","message":"..."} plus extra
top-level fields (required_scope, caller_scopes); WS nests error:{code,message}. Transport.action_error/1
(extensions/exoforge_std_transport) maps errors.
Want everywhere (HTTP router incl. webhook/file routes, WS socket_handler, any other ingress):
  {"status":"error","error":{"code":"forbidden_scope","message":"...","details":{...}},"rid":"..."}
- extra fields move into details; HTTP status codes unchanged; staff-only `logs` unchanged.
- Transport builds the shape in one function; HTTP and WS call it - no second copy.
- C# Exoforge.Client parses the nested shape and still reads the old flat and old string shapes
  (one release of compatibility); ExoActionException gets an optional Details. Keep the edit in the
  error-parsing code only (another branch adds token refresh to ExoClient.cs).
- Docs/skills/OpenAPI that show error replies updated.
Tests: transport/http/ws tests for the nested shape incl. forbidden_scope details; Client tests for all three shapes.
