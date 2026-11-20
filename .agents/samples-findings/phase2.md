# Phase 2 — samples on SDK 0.1.44

### menu-11 — Boolean resource columns come back as the strings `"true"`/`"false"`
- **Kind**: bug
- **Where**: cluster resource store, any `[ExoColumn]` bool (`player_settings.color_blind`). Reproduces with the CLI alone, so it is not the sample's code.
- **What**: writing a JSON boolean stores a string. `./exo resource create player_settings --data '{"player_id":"boolprobe","volume":10,"color_blind":true}' --json` → `{"row":{"color_blind":"true",...}}`; `./exo resource list player_settings --json` → `"color_blind": "true"`. The column is declared `"type":"boolean"` in `exo resource tables --json`.
- **Impact**: `game_menu.get_settings` then fails on the next read: `Exo.Database.Get<PlayerSettings>` deserializer sees a string token. README §0's settings panel works until the first `save_settings`, after which the player's menu can never load settings again. Any plugin record with a bool field has the same breakage.
- **Repro**: `POST /api/auth/anonymous {"player_id":"boolprobe","device_id":"boolprobe"}` → `POST /api/game_menu/get_settings` →
  `{"error":"{:json, \"The JSON value could not be converted to Exoforge.Extensions.PlayerSettings. Path: $.color_blind …\"}","logs":["[ERROR] System.Text.Json.JsonException: … Cannot get the value of a token type 'String' as a boolean. …"]}`
- **Sample state**: `tools/smoke/menu.sh` asserts the read-back and stays red until bool columns round-trip as JSON booleans. Not worked around in `PlayerSettings`.

### Verification of the phase-2 SDK fixes in this slice
- BUG-1: `ExoServices.Wallet.CreditAsync` on a rejected `wallet.credit` now throws `ExoActionException("invalid_amount")` inside `game_menu` (seen in `exo extension logs game_menu`), so `ClaimGift` maps it to `wallet_rejected` and records no claim. The old `(await …)!` workaround is gone; `game_menu.Tests` covers both a zero row and an arbitrary wallet error.
- BUG-2 / SEC-3 / BUG-17 / CONF-9 / BUG-14: not exercised by this slice (no webhook, cron, OnEvent or record shim here; tests run with default xunit parallelism).
- Unchanged from phase 1: failing actions still reply `{"error":"{:code, \"message\"}"}` (menu-5). The smoke script parses the atom; Unity's client parsing was not checked headlessly.
