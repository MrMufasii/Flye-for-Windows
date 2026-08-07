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
  "$IMAGE" \
  /opt/flye/bin/flye \
  "${COMMON[@]}" \
  --out-dir /work/native

echo "Running the same assembly inside WebAssembly..."
"$WASMTIME_BIN" run \
  --dir "$ROOT::/work" \
  -- \
  "$MODULE" \
  -no-stdin \
  /opt/flye/bin/flye \
  "${COMMON[@]}" \
  --out-dir /work/wasm

# container2wasm currently returns success after the emulated VM shuts down even
# when a process inside the guest failed. Validate Flye's products explicitly so
# the original Flye log, rather than a secondary Python FileNotFoundError, is
# reported by CI.
missing=0
for output in assembly.fasta assembly_graph.gfa assembly_info.txt; do
  if [[ ! -s "$ROOT/wasm/$output" ]]; then
    printf 'missing or empty WASM assembly product: %s\n' "$ROOT/wasm/$output" >&2
    missing=1
  fi
done
if (( missing != 0 )); then
  if [[ -f "$ROOT/wasm/flye.log" ]]; then
    printf '\n===== WASM Flye log (last 200 lines) =====\n' >&2
    tail -n 200 "$ROOT/wasm/flye.log" >&2
  fi
  exit 1
fi

python3 "$SCRIPT_DIR/assembly_parity.py" "$ROOT/native" "$ROOT/wasm"
