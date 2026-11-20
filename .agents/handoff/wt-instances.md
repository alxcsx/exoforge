# wt/instances: one identity per player instance on one machine  (worktree /Users/alexcs/projects/exoforge-wt/instances)
Read wt-common.md first. CONF-10/F28: sdk/unity/Exoforge.SDK/Runtime ExoDeviceId and ExoTokenStore persist to
PlayerPrefs with no namespace, so two game instances on one machine (Multiplayer Play Mode clones, two editors, two
standalone builds) are the same device and share one session; with rotating refresh tokens (merged wt/tokens) one
instance can replay a refresh token the other already rotated and the server revokes the whole family.
Want: a profile key that namespaces both stores (PlayerPrefs keys get a suffix; default profile keeps today's keys so
existing players keep their account):
 - MPPM: the clone/player id when the project runs under Multiplayer Play Mode (detect without a hard package
   dependency - reflection or a scripting define guard);
 - else a `-exoProfile <name>` command-line argument (standalone builds, CI);
 - else default. `ExoforgeSDK.Auth.Profile` exposes the active one; ExoDeviceId.Impersonate/Mask keep working within it.
 - Docs: multi-instance local testing section in the Unity skill/README.
Do not touch sdk/csharp/Exoforge.Client refresh gate code except if a profile must flow through it.
Tests: pure C# tests (Exoforge.Client.Tests or a small runtime-logic test with a fake prefs store): two profiles get
different device ids and tokens; default profile reads the legacy keys; arg parsing.
