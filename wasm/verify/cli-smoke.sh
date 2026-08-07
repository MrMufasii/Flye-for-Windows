#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WASM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
IMAGE="${FLYE_NATIVE_IMAGE:-flye-wasm-native:2.9.6}"
MODULE="${FLYE_WASM_MODULE:-$WASM_DIR/dist/flye-2.9.6-complete.wasm}"
OUT="${FLYE_VERIFY_DIR:-$WASM_DIR/dist/verification}"
WASMTIME_BIN="${WASMTIME:-wasmtime}"
mkdir -p "$OUT"

run_logged() {
  local output="$1"
  shift
  local status

  set +e
  "$@" >"$output" 2>&1
  status=$?
  set -e

  if (( status != 0 )); then
    printf 'command failed with exit code %d:' "$status" >&2
    printf ' %q' "$@" >&2
    printf '\n' >&2
    if [[ -s "$output" ]]; then
      cat "$output" >&2
    else
      printf 'captured output is empty: %s\n' "$output" >&2
    fi
    return "$status"
  fi
}

run_logged "$OUT/native-version.txt" \
  docker run --rm "$IMAGE" /opt/flye/bin/flye --version
run_logged "$OUT/wasm-version.txt" \
  "$WASMTIME_BIN" -- "$MODULE" -no-stdin /opt/flye/bin/flye --version

native_version="$(tr -d '\r' <"$OUT/native-version.txt")"
wasm_version="$(tr -d '\r' <"$OUT/wasm-version.txt")"
printf 'Native Flye version: %s\n' "$native_version"
printf 'WASM Flye version:   %s\n' "$wasm_version"

if [[ "$native_version" != "$wasm_version" ]]; then
  printf 'Flye version output differs between the native image and WASM.\n' >&2
  diff -u \
    <(printf '%s\n' "$native_version") \
    <(printf '%s\n' "$wasm_version") >&2 || true
  exit 1
fi

run_logged "$OUT/native-help.txt" \
  docker run --rm "$IMAGE" /opt/flye/bin/flye --help
run_logged "$OUT/wasm-help.txt" \
  "$WASMTIME_BIN" -- "$MODULE" -no-stdin /opt/flye/bin/flye --help
python3 "$SCRIPT_DIR/cli_parity.py" "$OUT/native-help.txt" "$OUT/wasm-help.txt"

# With no image ENTRYPOINT, the c2w runtime's positional command is the
# complete process to execute, allowing the bundled toolchain to be checked.
run_logged "$OUT/wasm-toolchain.txt" \
  "$WASMTIME_BIN" -- "$MODULE" -no-stdin /bin/sh -lc \
  'set -eu; command -v python3; command -v flye; command -v flye-modules; command -v flye-minimap2; command -v flye-samtools; flye --version'
cat "$OUT/wasm-toolchain.txt"
