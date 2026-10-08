#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Locate the Exoforge repo, for the WASI toolchain the guest is compiled with.
ROOT="$SCRIPT_DIR"
while [ "$ROOT" != "/" ] && [ ! -d "$ROOT/sdk/build" ]; do
  ROOT="$(dirname "$ROOT")"
done

if [ ! -d "$ROOT/sdk/build" ]; then
  echo "error: could not find the Exoforge repo above $SCRIPT_DIR" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$ROOT/sdk/build/wasi-sdk.sh"
WASI_CLANG="$(resolve_wasi_clang)"

# The manifest is written by Exoforge.Plugin.Generator during this build, so there is no separate
# generator tool to locate or invoke.
echo "Building C# contract assembly..."
dotnet build "$SCRIPT_DIR/sample_wasm.csproj" -c Release

echo "Compiling guest ($(basename "$WASI_CLANG"))..."
"$WASI_CLANG" -O2 -mexec-model=reactor \
  -Wl,--export=ping \
  -Wl,--export=increment \
  -Wl,--export=echo \
  -o "$SCRIPT_DIR/sample_wasm.wasm" \
  "$SCRIPT_DIR/guest.c"

echo "Built $SCRIPT_DIR/sample_wasm.wasm successfully!"
