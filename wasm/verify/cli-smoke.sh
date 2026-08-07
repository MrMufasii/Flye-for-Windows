#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WASM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
IMAGE="${FLYE_NATIVE_IMAGE:-flye-wasm-native:2.9.6}"
MODULE="${FLYE_WASM_MODULE:-$WASM_DIR/dist/flye-2.9.6-complete.wasm}"
OUT="${FLYE_VERIFY_DIR:-$WASM_DIR/dist/verification}"
WASMTIME_BIN="${WASMTIME:-wasmtime}"
EXPECTED_VM_MEMORY_MB="${FLYE_WASM_VM_MEMORY_MB:-2048}"
C2W_TMP="$OUT/c2w-tmp"
mkdir -p "$OUT" "$C2W_TMP"

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

run_wasm_logged() {
  local output="$1"
  shift
  run_logged "$output" \
    "$WASMTIME_BIN" run \
    --dir "$C2W_TMP::/tmp" \
    -- \
    "$MODULE" \
    -no-stdin \
    "$@"
}

run_logged "$OUT/native-version.txt" \
  docker run --rm "$IMAGE" /opt/flye/bin/flye --version
run_wasm_logged "$OUT/wasm-version.txt" \
  /opt/flye/bin/flye --version

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
run_wasm_logged "$OUT/wasm-help.txt" \
  /opt/flye/bin/flye --help
python3 "$SCRIPT_DIR/cli_parity.py" "$OUT/native-help.txt" "$OUT/wasm-help.txt"

# With no image ENTRYPOINT, the c2w runtime's positional command is the
# complete process to execute, allowing the bundled toolchain to be checked.
run_wasm_logged "$OUT/wasm-toolchain.txt" \
  /bin/sh -lc \
  'set -eu; command -v python3; command -v flye; command -v flye-modules; command -v flye-minimap2; command -v flye-samtools; flye --version'
cat "$OUT/wasm-toolchain.txt"

# container2wasm v0.8.4 defaults the emulated Linux VM to only 128 MiB. Confirm
# that the Flye module was built with the requested production memory size.
run_wasm_logged "$OUT/wasm-memory-kib.txt" \
  /bin/sh -lc \
  'while read -r key value unit; do if [ "$key" = "MemTotal:" ]; then printf "%s\n" "$value"; exit 0; fi; done < /proc/meminfo; exit 1'

# The emulated serial console writes CRLF line endings. Remove carriage returns
# before applying the numeric-only check, just as the version checks above do.
wasm_memory_kib="$(
  tr -d '\r' <"$OUT/wasm-memory-kib.txt" |
    awk '/^[0-9]+$/ { value = $0 } END { if (value != "") print value }'
)"
if [[ ! "$wasm_memory_kib" =~ ^[0-9]+$ ]]; then
  printf 'Could not parse guest MemTotal from %s:\n' "$OUT/wasm-memory-kib.txt" >&2
  cat "$OUT/wasm-memory-kib.txt" >&2
  exit 1
fi

minimum_memory_kib=$((EXPECTED_VM_MEMORY_MB * 1024 * 9 / 10))
if (( wasm_memory_kib < minimum_memory_kib )); then
  printf 'WASM guest memory is too small: %s KiB; expected approximately %s MiB.\n' \
    "$wasm_memory_kib" "$EXPECTED_VM_MEMORY_MB" >&2
  exit 1
fi
printf 'WASM guest memory: %s KiB (configured: %s MiB)\n' \
  "$wasm_memory_kib" "$EXPECTED_VM_MEMORY_MB"
