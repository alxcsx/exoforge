#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Locate the Exoforge repo (the directory containing the ManifestGen project).
ROOT="$SCRIPT_DIR"
while [ "$ROOT" != "/" ] && [ ! -d "$ROOT/sdk/csharp/Exoforge.ManifestGen" ]; do
  ROOT="$(dirname "$ROOT")"
done

# shellcheck source=/dev/null
source "$ROOT/sdk/build/wasi-sdk.sh"
WASI_CLANG="$(resolve_wasi_clang)"

echo "Building C# contract assembly..."
dotnet build "$SCRIPT_DIR/sample_wasm.csproj" -c Release

echo "Generating plugin manifest from C# attributes..."
dotnet run --project "$ROOT/sdk/csharp/Exoforge.ManifestGen" -- \
  "$SCRIPT_DIR/bin/Release/net10.0/sample_wasm.dll" \
  "$SCRIPT_DIR/manifest.exs"

echo "Compiling guest ($(basename "$WASI_CLANG"))..."
"$WASI_CLANG" -O2 -mexec-model=reactor \
  -Wl,--export=ping \
  -Wl,--export=increment \
  -Wl,--export=echo \
  -o "$SCRIPT_DIR/sample_wasm.wasm" \
  "$SCRIPT_DIR/guest.c"

echo "Built $SCRIPT_DIR/sample_wasm.wasm successfully!"
