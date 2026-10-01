#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WASI_CLANG="${WASI_SDK_PATH:-/Users/alexcs/.wasi-sdk/wasi-sdk-25.0}/bin/wasm32-wasip1-clang"

echo "Building C# assembly..."
dotnet build "$SCRIPT_DIR/combat_wasm.csproj" -c Release

echo "Generating plugin manifest from C# attributes..."
dotnet run --project "$SCRIPT_DIR/../../sdk/csharp/Exoforge.ManifestGen" -- \
  "$SCRIPT_DIR/bin/Release/net10.0/combat_wasm.dll" \
  "$SCRIPT_DIR/manifest.exs"

echo "Compiling WASM binary..."
"$WASI_CLANG" -O2 -mexec-model=reactor \
  -Wl,--export=attack \
  -Wl,--export=ping \
  -o "$SCRIPT_DIR/combat_wasm.wasm" \
  -x c - << 'EOF'
#include <string.h>
#include <stdio.h>

__attribute__((import_module("env"), import_name("host_emit_event")))
extern int host_emit_event(const char* topic, int topic_len, const char* event, int event_len, const char* payload, int payload_len);

__attribute__((import_module("env"), import_name("host_log")))
extern int host_log(int level, const char* msg, int msg_len);

__attribute__((export_name("ping")))
int ping() {
    return 42;
}

__attribute__((export_name("attack")))
int attack(int attacker_id, int target_id, int damage) {
    int applied = damage > 0 ? damage : 1;
    const char* topic = "combat:events";
    const char* event = "player_damaged";
    char payload[128];
    int len = snprintf(payload, sizeof(payload), "{\"attacker_id\":%d,\"target_id\":%d,\"damage\":%d}", attacker_id, target_id, applied);
    
    host_emit_event(topic, (int)strlen(topic), event, (int)strlen(event), payload, len);
    return applied;
}
EOF

echo "Built $SCRIPT_DIR/combat_wasm.wasm successfully!"
