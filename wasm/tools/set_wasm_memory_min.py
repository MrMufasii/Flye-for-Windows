#!/usr/bin/env python3
"""Raise a wasm32 module's defined linear-memory minimum.

container2wasm's native (non-Wizer) output relies on runtime memory.grow for
Bochs' guest-RAM allocation. Large allocations can cross wasm32's signed
2-GiB boundary before the allocator grows memory, so Flye's high-memory module
is pre-grown at link-artifact level instead.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import tempfile

WASM_HEADER = b"\x00asm\x01\x00\x00\x00"
WASM_PAGE_SIZE = 65536
MAX_WASM32_PAGES = 65536


def decode_u32(data: bytes, offset: int) -> tuple[int, int]:
    value = 0
    shift = 0
    start = offset
    while True:
        if offset >= len(data):
            raise ValueError(f"truncated unsigned LEB128 at offset {start}")
        byte = data[offset]
        offset += 1
        value |= (byte & 0x7F) << shift
        if (byte & 0x80) == 0:
            if value > 0xFFFFFFFF:
                raise ValueError(f"u32 LEB128 overflow at offset {start}")
            return value, offset
        shift += 7
        if shift >= 35:
            raise ValueError(f"invalid u32 LEB128 at offset {start}")


def encode_u32(value: int) -> bytes:
    if not 0 <= value <= 0xFFFFFFFF:
        raise ValueError(f"value is not a u32: {value}")
    encoded = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            encoded.append(byte | 0x80)
        else:
            encoded.append(byte)
            return bytes(encoded)


def mib_to_pages(mib: int) -> int:
    if mib <= 0:
        raise ValueError("minimum memory must be greater than zero")
    return (mib * 1024 * 1024 + WASM_PAGE_SIZE - 1) // WASM_PAGE_SIZE


def patch_memory_minimum(module: bytes, requested_pages: int) -> tuple[bytes, int, int]:
    if module[:8] != WASM_HEADER:
        raise ValueError("input is not a WebAssembly 1.0 binary module")
    if not 1 <= requested_pages <= MAX_WASM32_PAGES:
        raise ValueError(
            f"requested minimum must be 1..{MAX_WASM32_PAGES} wasm32 pages; "
            f"got {requested_pages}"
        )

    cursor = 8
    output = bytearray(module[:8])
    memory_sections = 0
    old_minimum: int | None = None
    new_minimum: int | None = None

    while cursor < len(module):
        section_id = module[cursor]
        cursor += 1
        payload_size, payload_start = decode_u32(module, cursor)
        payload_end = payload_start + payload_size
        if payload_end > len(module):
            raise ValueError(f"section {section_id} extends beyond end of file")
        payload = module[payload_start:payload_end]
        cursor = payload_end

        if section_id != 5:
            output.append(section_id)
            output.extend(encode_u32(len(payload)))
            output.extend(payload)
            continue

        memory_sections += 1
        if memory_sections > 1:
            raise ValueError("module contains more than one memory section")

        offset = 0
        count, offset = decode_u32(payload, offset)
        if count != 1:
            raise ValueError(f"expected exactly one defined memory; found {count}")

        flags, offset = decode_u32(payload, offset)
        if flags & ~0x07:
            raise ValueError(f"unsupported memory limits flags: 0x{flags:x}")
        if flags & 0x02:
            raise ValueError("shared memories are not supported")
        if flags & 0x04:
            raise ValueError("memory64 modules are not supported")

        minimum, offset = decode_u32(payload, offset)
        maximum: int | None = None
        if flags & 0x01:
            maximum, offset = decode_u32(payload, offset)
        if offset != len(payload):
            raise ValueError("unexpected bytes after the memory definition")
        if maximum is not None and requested_pages > maximum:
            raise ValueError(
                f"requested minimum {requested_pages} exceeds declared maximum {maximum}"
            )

        old_minimum = minimum
        new_minimum = max(minimum, requested_pages)
        new_payload = bytearray()
        new_payload.extend(encode_u32(1))
        new_payload.extend(encode_u32(flags))
        new_payload.extend(encode_u32(new_minimum))
        if maximum is not None:
            new_payload.extend(encode_u32(maximum))

        output.append(section_id)
        output.extend(encode_u32(len(new_payload)))
        output.extend(new_payload)

    if memory_sections != 1 or old_minimum is None or new_minimum is None:
        raise ValueError("module does not contain exactly one defined memory")
    return bytes(output), old_minimum, new_minimum


def atomic_write(path: Path, contents: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(contents)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary_name, path)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Raise a wasm32 module's single defined memory minimum."
    )
    parser.add_argument("module", type=Path, help="input WebAssembly module")
    parser.add_argument(
        "--minimum-mib",
        type=int,
        required=True,
        help="minimum linear-memory size in MiB (maximum 4096 for wasm32)",
    )
    parser.add_argument("--output", type=Path, help="output path; default replaces input")
    args = parser.parse_args()

    source = args.module.resolve()
    target = (args.output or args.module).resolve()
    requested_pages = mib_to_pages(args.minimum_mib)
    original = source.read_bytes()
    patched, old_pages, new_pages = patch_memory_minimum(original, requested_pages)
    atomic_write(target, patched)

    print(
        "WebAssembly memory minimum: "
        f"{old_pages} -> {new_pages} pages "
        f"({old_pages * WASM_PAGE_SIZE / 1024**2:.1f} -> "
        f"{new_pages * WASM_PAGE_SIZE / 1024**2:.1f} MiB)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
