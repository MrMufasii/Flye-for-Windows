#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WASM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
IMAGE="${FLYE_NATIVE_IMAGE:-flye-wasm-native:2.9.6}"
MODULE="${FLYE_WASM_MODULE:-$WASM_DIR/dist/flye-2.9.6-complete.wasm}"
ROOT="${FLYE_PARITY_DIR:-$WASM_DIR/dist/parity}"
WASMTIME_BIN="${WASMTIME:-wasmtime}"
ROOT="$(mkdir -p "$ROOT" && cd "$ROOT" && pwd)"
rm -rf "$ROOT/native" "$ROOT/wasm"
mkdir -p "$ROOT/native" "$ROOT/wasm" "$ROOT/.tmp"

READS=/opt/flye/flye/tests/data/ecoli_500kb_reads_hifi.fastq.gz
COMMON=(--pacbio-corr "$READS" --genome-size 500k --threads 1 --min-overlap 1000 --deterministic)

echo "Running native baseline..."
docker run --rm \
  --volume "$ROOT:/work" \
  "$IMAGE" "${COMMON[@]}" --out-dir /work/native

echo "Running the same assembly inside WebAssembly..."
"$WASMTIME_BIN" \
  --mapdir "/work::$ROOT" \
  -- \
  "$MODULE" \
  -- \
  "${COMMON[@]}" \
  --out-dir /work/wasm

python3 "$SCRIPT_DIR/assembly_parity.py" "$ROOT/native" "$ROOT/wasm"
