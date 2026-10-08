# background_change

An Exoforge plugin. Actions are declared with attributes and discovered at build time.

## Layout

| Path | What it is |
| :--- | :--- |
| `src/BackgroundChangePlugin.cs` | the plugin: `[ExoAction]` methods are what callers invoke |
| `src/Generated/` | typed service stubs and the JSON context (`exo plugin stubs background_change`) |
| `manifest.exs` | generated from the attributes; do not edit |
| `background_change` | the staged native binary; generated |

## Working on it

```bash
exo plugin build background_change     # compile
exo plugin push  background_change     # build, deploy, verify
exo plugin dev   background_change     # redeploy on every save
exo plugin logs  background_change     # what the plugin just did
```

In Unity: **Tools ▸ Exoforge ▸ Exoforge Studio**, then the Plugins tab.