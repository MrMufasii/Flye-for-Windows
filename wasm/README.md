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

Requirements: Docker with Buildx, `c2w` v0.8.4, Python 3, GNU Make, and enough
local disk for the image and generated module.

```bash
make -C wasm image
make -C wasm wasm
make -C wasm verify
```

The generated Linux guest exposes 2048 MiB of RAM. To keep the Bochs emulator
inside wasm32's addressable range, the build enables Bochs large-RAM-file support
and uses a 1024 MiB in-memory working set; guest pages beyond that working set are
paged through Bochs' temporary RAM backing file. This preserves the full 2048 MiB
guest-visible memory without requiring one contiguous 2 GiB WebAssembly allocation.

The values are reproducible and configurable at conversion time:

```bash
make -C wasm wasm \
  VM_MEMORY_SIZE_MB=2048 \
  VM_HOST_MEMORY_SIZE_MB=1024
```

`VM_HOST_MEMORY_SIZE_MB` must be positive and lower than
`VM_MEMORY_SIZE_MB`. The build uses container2wasm's `native` initialization
mode, avoiding a multi-gigabyte Wizer snapshot while retaining the complete
container filesystem and command environment.

GitHub Actions performs the same build, verifies the configured guest memory, runs
CLI parity checks, runs Flye's bundled 500 kb end-to-end assembly both natively and
inside WASM, compares all principal assembly products, and publishes
`flye-2.9.6-complete.wasm` as an artifact. The exact patched container2wasm
Dockerfile and its checksum are included with the artifact.

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
