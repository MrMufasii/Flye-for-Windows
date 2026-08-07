#!/usr/bin/env python3
"""Assert that native and WASM Flye produced the same assembly products."""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


def fasta_records(path: Path) -> list[tuple[str, str]]:
    records: list[tuple[str, str]] = []
    name: str | None = None
    parts: list[str] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith(">"):
            if name is not None:
                records.append((name, "".join(parts).upper()))
            name = line[1:].split()[0]
            parts = []
        else:
            if name is None:
                raise ValueError(f"sequence before header in {path}")
            parts.append(line)
    if name is not None:
        records.append((name, "".join(parts).upper()))
    if not records:
        raise ValueError(f"no FASTA records in {path}")
    return records


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("native_dir", type=Path)
    parser.add_argument("wasm_dir", type=Path)
    args = parser.parse_args()

    native_fasta = args.native_dir / "assembly.fasta"
    wasm_fasta = args.wasm_dir / "assembly.fasta"
    native = fasta_records(native_fasta)
    wasm = fasta_records(wasm_fasta)

    if native != wasm:
        raise SystemExit("assembly parity failed: FASTA records or sequences differ")

    required = ("assembly_graph.gfa", "assembly_info.txt")
    for filename in required:
        n = (args.native_dir / filename).read_bytes()
        w = (args.wasm_dir / filename).read_bytes()
        if n != w:
            raise SystemExit(f"assembly parity failed: {filename} differs")

    total_bp = sum(len(sequence) for _, sequence in native)
    print(
        "assembly parity: "
        f"{len(native)} contigs, {total_bp} bp, "
        f"FASTA sha256={digest(native_fasta.read_bytes())}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
