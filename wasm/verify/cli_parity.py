#!/usr/bin/env python3
"""Compare native-container and WebAssembly Flye CLI surfaces."""
from __future__ import annotations

import argparse
import difflib
import re
from pathlib import Path


def normalize(text: str) -> list[str]:
    text = text.replace("\r\n", "\n")
    text = re.sub(r"/opt/flye(?:/[^\s'\"]*)?", "<FLYE_PATH>", text)
    text = re.sub(r"/work(?:/[^\s'\"]*)?", "<WORK_PATH>", text)
    return [line.rstrip() for line in text.splitlines() if line.rstrip()]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("native", type=Path)
    parser.add_argument("wasm", type=Path)
    args = parser.parse_args()

    native = normalize(args.native.read_text(encoding="utf-8", errors="replace"))
    wasm = normalize(args.wasm.read_text(encoding="utf-8", errors="replace"))
    if native == wasm:
        print(f"CLI parity: {len(native)} normalized lines are identical")
        return 0

    diff = "\n".join(
        difflib.unified_diff(native, wasm, fromfile="native", tofile="wasm", lineterm="")
    )
    print(diff)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
