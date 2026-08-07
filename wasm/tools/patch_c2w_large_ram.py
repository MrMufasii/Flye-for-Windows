#!/usr/bin/env python3
"""Patch container2wasm v0.8.4 for split guest/host RAM.

The upstream amd64 WASI target asks Bochs to allocate all guest RAM as one
contiguous wasm32 heap object. A 2048 MiB guest therefore crosses wasm32's
2-GiB signed-address boundary before Linux starts. This patch enables Bochs'
large-RAM-file backend and gives it a smaller in-memory working set while the
guest still sees the full configured RAM.

WASI SDK 19 does not link a ``tmpfile`` implementation, although Bochs' large
RAM backend calls ``tmpfile64`` (mapped to ``tmpfile`` on this target). The
patched Dockerfile therefore replaces that single call in the WASI Bochs copy
with an explicit writable file under /tmp. Runtime launchers preopen a private
host directory there.
"""

from __future__ import annotations

import argparse
from pathlib import Path


def replace_once(text: str, old: str, new: str, description: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f"cannot patch {description}: expected exactly one match, found {count}"
        )
    return text.replace(old, new, 1)


def replace_once_in_region(
    text: str,
    *,
    start_marker: str,
    end_marker: str,
    old: str,
    new: str,
    description: str,
) -> str:
    """Replace one token only inside a uniquely delimited Dockerfile stage."""
    start_count = text.count(start_marker)
    end_count = text.count(end_marker)
    if start_count != 1 or end_count != 1:
        raise SystemExit(
            f"cannot locate {description}: start matches={start_count}, "
            f"end matches={end_count}"
        )

    start = text.index(start_marker)
    end = text.index(end_marker, start + len(start_marker))
    region = text[start:end]
    count = region.count(old)
    if count != 1:
        raise SystemExit(
            f"cannot patch {description}: expected exactly one match in the "
            f"WASI Bochs stage, found {count}"
        )

    patched_region = region.replace(old, new, 1)
    return text[:start] + patched_region + text[end:]


def get_region(text: str, start_marker: str, end_marker: str) -> str:
    start = text.index(start_marker)
    end = text.index(end_marker, start + len(start_marker))
    return text[start:end]


def patch_dockerfile(text: str) -> str:
    text = replace_once(
        text,
        "ARG VM_MEMORY_SIZE_MB=128\n",
        "ARG VM_MEMORY_SIZE_MB=128\nARG VM_HOST_MEMORY_SIZE_MB=1024\n",
        "global VM host-memory argument",
    )

    text = replace_once(
        text,
        """FROM ubuntu:22.04 AS bochs-config-dev
ARG VM_MEMORY_SIZE_MB
RUN apt-get update && apt-get install -y gettext-base && mkdir /out
COPY --link --from=assets ./config/bochs/bochsrc.template /
RUN cat /bochsrc.template | MEMORY_SIZE=$VM_MEMORY_SIZE_MB envsubst > /out/bochsrc
""",
        """FROM ubuntu:22.04 AS bochs-config-dev
ARG VM_MEMORY_SIZE_MB
ARG VM_HOST_MEMORY_SIZE_MB
RUN apt-get update && apt-get install -y gettext-base && mkdir /out
COPY --link --from=assets ./config/bochs/bochsrc.template /
RUN sed -i 's|^megs: ${MEMORY_SIZE}$|memory: guest=${MEMORY_SIZE}, host=${HOST_MEMORY_SIZE}, block_size=1024|' /bochsrc.template && \\
    cat /bochsrc.template | MEMORY_SIZE=$VM_MEMORY_SIZE_MB HOST_MEMORY_SIZE=$VM_HOST_MEMORY_SIZE_MB envsubst > /out/bochsrc
""",
        "Bochs guest/host memory configuration",
    )

    # The upstream Dockerfile contains two Bochs builds: the WASI module used
    # by this target and an unrelated Emscripten browser build. Patch only the
    # WASI stage; retaining the Emscripten flag is intentional.
    wasi_start = "FROM rust:1.74.1-bullseye AS bochs-dev-common\n"
    wasi_end = "FROM bochs-dev-common AS bochs-dev-native\n"
    text = replace_once_in_region(
        text,
        start_marker=wasi_start,
        end_marker=wasi_end,
        old="--disable-large-ramfile",
        new="--enable-large-ramfile",
        description="WASI Bochs large-RAM-file configure flag",
    )

    # wasi-sdk 19's libc leaves tmpfile unresolved. Keep the compatibility
    # change scoped to the copied WASI Bochs source so the native BIOS and
    # Emscripten builds remain byte-for-byte upstream.
    bochs_copy = "COPY --link --from=bochs-repo / /Bochs\n\n"
    bochs_copy_with_tmpfile_patch = """COPY --link --from=bochs-repo / /Bochs
RUN sed -i \\
    's|BX_MEM_THIS overflow_file = tmpfile64();|BX_MEM_THIS overflow_file = fopen("/tmp/bochs-memory.ram", "w+b");|' \\
    /Bochs/bochs/memory/misc_mem.cc && \\
    grep -F 'BX_MEM_THIS overflow_file = fopen("/tmp/bochs-memory.ram", "w+b");' \\
    /Bochs/bochs/memory/misc_mem.cc

"""
    text = replace_once_in_region(
        text,
        start_marker=wasi_start,
        end_marker=wasi_end,
        old=bochs_copy,
        new=bochs_copy_with_tmpfile_patch,
        description="WASI Bochs tmpfile compatibility patch",
    )

    required = (
        "ARG VM_HOST_MEMORY_SIZE_MB=1024",
        "ARG VM_HOST_MEMORY_SIZE_MB",
        "memory: guest=${MEMORY_SIZE}, host=${HOST_MEMORY_SIZE}, block_size=1024",
        "HOST_MEMORY_SIZE=$VM_HOST_MEMORY_SIZE_MB",
    )
    missing = [marker for marker in required if marker not in text]
    if missing:
        raise SystemExit(
            "patched Dockerfile is missing required markers: " + ", ".join(missing)
        )

    wasi_region = get_region(text, wasi_start, wasi_end)
    if wasi_region.count("--enable-large-ramfile") != 1:
        raise SystemExit(
            "patched WASI Bochs stage does not enable large-RAM-file exactly once"
        )
    if "--disable-large-ramfile" in wasi_region:
        raise SystemExit(
            "patched WASI Bochs stage still disables large-RAM-file support"
        )
    tmpfile_replacement = (
        'BX_MEM_THIS overflow_file = fopen("/tmp/bochs-memory.ram", "w+b");'
    )
    if wasi_region.count(tmpfile_replacement) != 2:
        raise SystemExit(
            "patched WASI Bochs stage does not contain the expected tmpfile "
            "replacement command and verification"
        )
    if wasi_region.count("tmpfile64();") != 1:
        raise SystemExit(
            "patched WASI Bochs stage should contain tmpfile64 only in the "
            "source-rewrite search expression"
        )
    return text


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Patch the container2wasm v0.8.4 Dockerfile so an amd64 guest can "
            "expose more RAM than Bochs allocates contiguously in wasm32."
        )
    )
    parser.add_argument("source", type=Path, help="Dockerfile from c2w --show-dockerfile")
    parser.add_argument("output", type=Path, help="patched Dockerfile")
    args = parser.parse_args()

    source = args.source.read_text(encoding="utf-8")
    patched = patch_dockerfile(source)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(patched, encoding="utf-8")
    print(
        "Patched container2wasm Dockerfile: enabled WASI Bochs large-RAM-file "
        "support, split guest RAM from the wasm32 host working set, and "
        "replaced the unavailable WASI tmpfile call."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
