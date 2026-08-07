#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WASM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
IMAGE="${FLYE_NATIVE_IMAGE:-flye-wasm-native:2.9.6}"
MODULE="${FLYE_WASM_MODULE:-$WASM_DIR/dist/flye-2.9.6-complete.wasm}"
OUT="${FLYE_VERIFY_DIR:-$WASM_DIR/dist/verification}"
WASMTIME_BIN="${WASMTIME:-wasmtime}"
mkdir -p "$OUT"

native_version="$(docker run --rm "$IMAGE" --version 2>&1)"
wasm_version="$("$WASMTIME_BIN" -- "$MODULE" --version 2>&1)"
printf '%s\n' "$native_version" | tee "$OUT/native-version.txt"
printf '%s\n' "$wasm_version" | tee "$OUT/wasm-version.txt"
[[ "$native_version" == "$wasm_version" ]]

docker run --rm "$IMAGE" --help >"$OUT/native-help.txt" 2>&1
"$WASMTIME_BIN" -- "$MODULE" --help >"$OUT/wasm-help.txt" 2>&1
python3 "$SCRIPT_DIR/cli_parity.py" "$OUT/native-help.txt" "$OUT/wasm-help.txt"

# Verify the complete bundled toolchain exists and is executable inside the WASM guest.
"$WASMTIME_BIN" -- "$MODULE" --entrypoint=/bin/sh -lc \
  'set -eu; command -v python3; command -v flye; command -v flye-modules; command -v flye-minimap2; command -v flye-samtools; flye --version' \
  >"$OUT/wasm-toolchain.txt" 2>&1
cat "$OUT/wasm-toolchain.txt"
