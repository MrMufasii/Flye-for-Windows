#!/usr/bin/env python3
"""Patch container2wasm v0.8.4 for split guest/host RAM.

The upstream amd64 WASI target asks Bochs to allocate all guest RAM as one
contiguous wasm32 heap object. A 2048 MiB guest therefore crosses wasm32's
2-GiB signed-address boundary before Linux starts. This patch enables Bochs'
large-RAM-file backend and gives it a smaller in-memory working set while the
guest still sees the full configured RAM.
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
RUN sed -i 's|^megs: ${MEMORY_SIZE}$|memory: guest=${MEMORY_SIZE}, host=${HOST_MEMORY_SIZE}, block_size=1024|' /bochsrc.template && \
    cat /bochsrc.template | MEMORY_SIZE=$VM_MEMORY_SIZE_MB HOST_MEMORY_SIZE=$VM_HOST_MEMORY_SIZE_MB envsubst > /out/bochsrc
""",
        "Bochs guest/host memory configuration",
    )

    text = replace_once(
        text,
        "--disable-large-ramfile",
        "--enable-large-ramfile",
        "Bochs large-RAM-file configure flag",
    )

    required = (
        "ARG VM_HOST_MEMORY_SIZE_MB=1024",
        "ARG VM_HOST_MEMORY_SIZE_MB",
        "--enable-large-ramfile",
        "memory: guest=${MEMORY_SIZE}, host=${HOST_MEMORY_SIZE}, block_size=1024",
        "HOST_MEMORY_SIZE=$VM_HOST_MEMORY_SIZE_MB",
    )
    missing = [marker for marker in required if marker not in text]
    if missing:
        raise SystemExit(
            "patched Dockerfile is missing required markers: " + ", ".join(missing)
        )
    if "--disable-large-ramfile" in text:
        raise SystemExit("patched Dockerfile still disables large-RAM-file support")
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
        "Patched container2wasm Dockerfile: enabled Bochs large-RAM-file "
        "support and split guest RAM from the wasm32 host working set."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
