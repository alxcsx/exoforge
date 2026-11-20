---
nav: Recipes
group: Get started
icon: check
summary: Short answers to the things you do every day.
---
# Recipes

## Sign in a player

Always use `ExoforgeSDK.Auth`. It derives the device id, stores the token, and resumes the same account.

```csharp
var session = await ExoforgeSDK.Auth.LoginAnonymously();
if (!session.HasDisplayName)
    session = await ExoforgeSDK.Auth.SetDisplayName("Viper");
```

## Build and deploy an extension

1. Open the **Extensions** tab in Unity Studio.
2. On the extension card, click **Build & Deploy**.
3. Wait for the status to report **running**. Build errors stop the deploy before upload.

## Regenerate service stubs

Client stubs come from the live contract export. Studio generates server-side stubs for the dependencies declared in `manifest.json`.

1. Click **Sync Client** in the Unity toolbar to refresh the typed client.
2. In the **Extensions** tab, open the extension and click **Stubs** for its server-side dependencies.

## Add persistence and seed on startup

1. Declare the record with `[ExoResource]` and its columns with `[ExoColumn]`.
2. Deploy; the extension manager migrates the table before the extension starts.
3. Add an optional idempotent `OnExtensionStart()` to seed defaults through `Exo.Database`.

The hook runs again after a restart, so guard duplicate writes.

## Subscribe to events

A server extension receives events through `OnEvent`; Unity subscribes through the generated service client.

```csharp
// Server extension
public void OnEvent(string name, ScoreSubmitted evt) => Handle(evt);

// Unity
await ExoServices.Leaderboard.SubscribeAsync("scores:*");
ExoServices.Leaderboard.OnScoreSubmitted += evt => Debug.Log(evt.Score);
```

## Diagnose a failure

1. Open the **Extensions** tab and inspect the extension's status.
2. Open **Logs** for build, runtime and startup messages.
3. Use the inspector's **Actions**, **Events** and **Resources** tabs to confirm what the extension exposes.

A build failure is reported before upload. A startup-hook failure appears as `startup_failed` with its code and message.
## Document your extension

Put Markdown files in a `docs/` folder next to your extension's source (`exo extension new` creates `docs/overview.md`). When the extension is deployed (`exo extension push`), every `docs/*.md` file becomes a page of this guide under **Extensions**, listed by the extension's title; remove the extension and its pages go with it. An Elixir extension uses `priv/docs/` for the same thing.

```markdown
---
nav: Refunds
summary: How refunds and chargebacks work.
---
# Refunds
```

The front matter is optional (`nav` is the sidebar label, `summary` a one-line description). Pages are shown in file-name order, so prefix with `01_`, `02_` to order them; only files directly inside `docs/` are read, and plain text and a few headings are enough: the live API catalog already lists every action's signature.

## Where to go next

The [quickstart](guide:01_quickstart) walks through these once from scratch. For the properties behind each attribute see the [attribute reference](guide:03_csharp_attributes); to change a table that already has players in it, read [Versions & Migrations](guide:04_versions_and_migrations).
