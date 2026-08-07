#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE="${FLYE_WASM_MODULE:-$SCRIPT_DIR/dist/flye-2.9.6-complete.wasm}"
WORKDIR="${FLYE_WASM_WORKDIR:-$PWD}"
WASMTIME="${WASMTIME:-wasmtime}"

if ! command -v "$WASMTIME" >/dev/null 2>&1; then
    printf 'error: wasmtime is not installed or not on PATH\n' >&2
    exit 127
fi
if [[ ! -f "$MODULE" ]]; then
    printf 'error: WebAssembly module not found: %s\n' "$MODULE" >&2
    exit 2
fi

mkdir -p "$WORKDIR/.tmp"
WORKDIR="$(cd "$WORKDIR" && pwd)"

# The left side is the path seen by Flye inside the WebAssembly guest;
# the right side is the host directory exposed through WASI.
#
# container2wasm's emulated console exits when stdin is already at EOF.
# Flye does not consume stdin, so use the runtime's documented -no-stdin
# mode and supply the container command explicitly before Flye's options.
exec "$WASMTIME" \
    --mapdir "/work::$WORKDIR" \
    -- \
    "$MODULE" \
    -no-stdin \
    /opt/flye/bin/flye \
    "$@"
