# Q8 - review fixes from Copilot (wt/instances and wt/tooling)
Rules: .agents/handoff/wt-common.md. Gemini model. One test per point, failing before the fix.
Reply after both parts: ask --reply t7 "Q8: <=10 lines".
A. wt/instances (/Users/alexcs/projects/exoforge-wt/instances):
 1. sdk/unity/Exoforge.SDK/Runtime/ExoTokenStore.cs is in namespace Exoforge.Client and uses ExoProfile from
    Exoforge.Client.Unity without a using - CS0103 in Unity. Fix the reference; grep every Runtime/Editor file that
    uses ExoProfile/ExoProfileResolver for the same mistake. There is no Unity here: compile the Runtime files with a
    throwaway netstandard2.1 csproj that stubs UnityEngine (PlayerPrefs, Application, Debug, SystemInfo) to prove they
    build, and say so in the reply.
 2. The Studio token keys (ExoTokenStore.cs ~L33-36, Exoforge.Studio.*) are profile-insensitive, so two MPPM editor
    instances share and rotate one Studio refresh token. Suffix them with the profile like the player keys
    (default profile keeps the legacy keys).
 3. ExoProfileResolver (Exoforge.Client ~L38-54): accept only ASCII [A-Za-z0-9_-], length cap kept.
B. wt/tooling (/Users/alexcs/projects/exoforge-wt/tooling), extensions/exoforge_std_ws:
 1. socket_handler.ex ~L35: a ?token= that is invalid or expired is treated as anonymous. Refuse it at connect with
    the nested error {status, error:{code: "token_expired" | "invalid_token", ...}, rid} (close or first frame -
    follow how the WS currently reports errors and what the C# client's reconnect path expects; the client must be
    able to tell expired from invalid and refresh). No token at all stays anonymous. ws_test for each case.
