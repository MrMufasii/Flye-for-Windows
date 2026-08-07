# Complete Flye 2.9.6 WebAssembly build

This target packages the unmodified Linux Flye 2.9.6 pipeline into a single WASI
WebAssembly module. The module contains Linux, Python, Flye's C++ assembler,
minimap2, samtools/htslib, zlib, configuration matrices, and test data. Commands,
subprocesses, pipes, threads, compressed input, temporary files, and every Flye CLI
mode execute inside the module.

The source is the repository's pinned upstream archive for Flye commit
`886b8c17412cdf3a2868a28237bca6c5ad1da156`. The conversion is pinned to
container2wasm `v0.8.4`.

## Build

Requirements: Docker with Buildx, `c2w` v0.8.4, GNU Make, and enough local disk for
the image and generated module.

```bash
make -C wasm image
make -C wasm wasm
make -C wasm verify
```

GitHub Actions performs the same build, runs CLI parity checks, runs Flye's bundled
500 kb end-to-end assembly both natively and inside WASM, compares all principal
assembly products, and publishes `flye-2.9.6-complete.wasm` as an artifact.

## Run

Install Wasmtime, then expose a host working directory as `/work` inside the module:

```bash
export FLYE_WASM_WORKDIR="$PWD/work"
mkdir -p "$FLYE_WASM_WORKDIR"
cp reads.fastq.gz "$FLYE_WASM_WORKDIR/"

./wasm/run-flye-wasi.sh \
  --nano-hq /work/reads.fastq.gz \
  --out-dir /work/out \
  --threads 8
```

All standard Flye options are passed through unchanged:

```bash
./wasm/run-flye-wasi.sh --help
./wasm/run-flye-wasi.sh --version
./wasm/run-flye-wasi.sh --nano-raw /work/reads.fastq.gz -g 5m -o /work/out -t 8 --meta
./wasm/run-flye-wasi.sh --pacbio-hifi /work/hifi.fastq.gz -o /work/out -t 8
```

Override the module or runtime location with `FLYE_WASM_MODULE` and `WASMTIME`.
