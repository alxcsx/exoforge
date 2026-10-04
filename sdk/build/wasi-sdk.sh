#!/usr/bin/env bash
# Resolves the WASI SDK clang for the host platform, downloading a pinned release if needed.
#
# Resolution order:
#   1. $WASI_SDK_PATH
#   2. wasm32-wasip1-clang on PATH
#   3. a previously downloaded copy in $EXOFORGE_WASI_CACHE (default ~/.cache/exoforge/wasi-sdk)
#   4. ~/.wasi-sdk/wasi-sdk-<version>-*
#   5. download the pinned release for this OS/arch
#
# Source this file, then call: WASI_CLANG="$(resolve_wasi_clang)"

WASI_SDK_VERSION="${WASI_SDK_VERSION:-25.0}"

wasi_sdk_host() {
  case "$(uname -s)-$(uname -m)" in
    Darwin-arm64) echo "arm64-macos" ;;
    Darwin-x86_64) echo "x86_64-macos" ;;
    Linux-x86_64) echo "x86_64-linux" ;;
    Linux-aarch64 | Linux-arm64) echo "arm64-linux" ;;
    *) echo "" ;;
  esac
}

resolve_wasi_clang() {
  if [ -n "${WASI_SDK_PATH:-}" ] && [ -x "$WASI_SDK_PATH/bin/wasm32-wasip1-clang" ]; then
    echo "$WASI_SDK_PATH/bin/wasm32-wasip1-clang"
    return 0
  fi

  if command -v wasm32-wasip1-clang >/dev/null 2>&1; then
    command -v wasm32-wasip1-clang
    return 0
  fi

  local cache="${EXOFORGE_WASI_CACHE:-$HOME/.cache/exoforge/wasi-sdk}"
  local dir

  for dir in "$cache"/wasi-sdk-"$WASI_SDK_VERSION"-* "$HOME"/.wasi-sdk/wasi-sdk-"$WASI_SDK_VERSION"-*; do
    if [ -x "$dir/bin/wasm32-wasip1-clang" ]; then
      echo "$dir/bin/wasm32-wasip1-clang"
      return 0
    fi
  done

  local host
  host="$(wasi_sdk_host)"

  if [ -z "$host" ]; then
    echo "wasi-sdk: unsupported host $(uname -s)-$(uname -m). Set WASI_SDK_PATH." >&2
    return 1
  fi

  local url="https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-${WASI_SDK_VERSION}/wasi-sdk-${WASI_SDK_VERSION}-${host}.tar.gz"

  echo "wasi-sdk: downloading ${WASI_SDK_VERSION} (${host})..." >&2
  mkdir -p "$cache"

  if ! curl -fsSL "$url" | tar -xz -C "$cache"; then
    echo "wasi-sdk: download failed ($url). Set WASI_SDK_PATH." >&2
    return 1
  fi

  local resolved
  resolved="$(find "$cache" -maxdepth 3 -type f -name wasm32-wasip1-clang | head -1)"

  if [ -z "$resolved" ]; then
    echo "wasi-sdk: extraction produced no compiler." >&2
    return 1
  fi

  chmod +x "$resolved" 2>/dev/null || true
  echo "$resolved"
}
