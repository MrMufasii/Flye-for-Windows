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

# Wasmtime 33 exposes filesystem preopens on the `run` subcommand. Its
# mapping syntax is HOST::GUEST, so expose the selected host working directory
# as /work inside the container2wasm guest.
#
# container2wasm's emulated console exits when stdin is already at EOF.
# Flye does not consume stdin, so use the runtime's documented -no-stdin
# mode and supply the container command explicitly before Flye's options.
exec "$WASMTIME" run \
    --dir "$WORKDIR::/work" \
    -- \
    "$MODULE" \
    -no-stdin \
    /opt/flye/bin/flye \
    "$@"
