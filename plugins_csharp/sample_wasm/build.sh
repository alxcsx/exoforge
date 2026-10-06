#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Locate the Exoforge repo. The marker is the manifest generator itself, so finding it means the
# tool this script runs exists: it moved to Exoforge.Management/Tools~ in M29, and the old path here
# left ROOT empty and tried to source "/sdk/build/wasi-sdk.sh".
ROOT="$SCRIPT_DIR"
while [ "$ROOT" != "/" ] && [ ! -d "$ROOT/sdk/csharp/Exoforge.Management/Tools~/ManifestGen" ]; do
  ROOT="$(dirname "$ROOT")"
done

if [ ! -d "$ROOT/sdk/csharp/Exoforge.Management/Tools~/ManifestGen" ]; then
  echo "error: could not find the Exoforge repo above $SCRIPT_DIR" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$ROOT/sdk/build/wasi-sdk.sh"
WASI_CLANG="$(resolve_wasi_clang)"

echo "Building C# contract assembly..."
dotnet build "$SCRIPT_DIR/sample_wasm.csproj" -c Release

echo "Generating plugin manifest from C# attributes..."
dotnet run --project "$ROOT/sdk/csharp/Exoforge.Management/Tools~/ManifestGen" -- \
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
