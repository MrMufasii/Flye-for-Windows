#!/usr/bin/env bash
#
# Build native-Windows Flye, fully static (no MinGW runtime DLLs), with MinGW-w64.
#
# This is the single source of truth for the port's build. It:
#   1. extracts the pinned, vendored Flye source (scripts/flye-patch/flye-src-*.tar.gz)
#   2. applies the Windows port patch + drops in the POSIX-header shims
#   3. builds, all statically linked:
#        - zlib            (static libz.a, fetched once)
#        - flye-minimap2   (vendored minimap2 2.24)
#        - flye-samtools   (vendored samtools/htslib 1.9)
#        - flye-modules    (the C++ assembler core)
#   4. stages a ready-to-run install tree:  <out>/bin + <out>/flye
#
# Run from a git-bash shell (the autoconf/htslib build needs a POSIX shell), or
# let setup_flye.ps1 drive it. Requires the winlibs MinGW-w64 toolchain
# (scripts/setup_toolchain.ps1 installs it to %LOCALAPPDATA%\winlibs).
#
# Usage:  build_flye.sh [OUT_DIR]
#   OUT_DIR  where to stage bin/ + flye/   (default: %LOCALAPPDATA%/flye-install)
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"     # scripts/
PATCHDIR="$HERE/flye-patch"
ZLIBVER="1.3.1"
JOBS="${JOBS:-4}"

say() { printf '\033[36m[build]\033[0m %s\n' "$*"; }
die() { printf '\033[31m[build] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# --- locate the winlibs MinGW-w64 toolchain ------------------------------------
MINGW="${MINGW:-$(cygpath "$LOCALAPPDATA")/winlibs/mingw64}"
[ -x "$MINGW/bin/gcc.exe" ] || die "MinGW-w64 not found at '$MINGW'. Run scripts\\setup_toolchain.ps1 first (or set MINGW)."
# Keep PATH minimal + native: winlibs first, then System32 (for cygpath we rely on git-bash).
export PATH="$MINGW/bin:$PATH"
say "toolchain: $(gcc -dumpmachine), gcc $(gcc -dumpversion)"
[ "$(gcc -dumpmachine)" = "x86_64-w64-mingw32" ] || die "expected an x86_64-w64-mingw32 gcc"

# --- workspace -----------------------------------------------------------------
OUT="${1:-$(cygpath "$LOCALAPPDATA")/flye-install}"
BUILD="$(cygpath "$LOCALAPPDATA")/flye-build"
SRC="$BUILD/flye-src"
mkdir -p "$BUILD"

# --- 1. unpack vendored source + apply the port --------------------------------
TARBALL="$(ls "$PATCHDIR"/flye-src-*.tar.gz 2>/dev/null | head -1 || true)"
if [ ! -e "$SRC/.ported" ]; then
    [ -n "$TARBALL" ] || die "no vendored source tarball in $PATCHDIR"
    say "extracting $(basename "$TARBALL")"
    rm -rf "$SRC"; mkdir -p "$SRC"
    tar xzf "$TARBALL" -C "$SRC"
    say "applying flye-mingw.patch"
    patch -p1 -d "$SRC" < "$PATCHDIR/flye-mingw.patch"
    say "installing POSIX-header shims (execinfo.h, regex.h)"
    mkdir -p "$SRC/_shim"; cp "$PATCHDIR/shim/"*.h "$SRC/_shim/"
    touch "$SRC/.ported"
fi
cd "$SRC"
mkdir -p bin

# --- 2. zlib (static libz.a) ---------------------------------------------------
if [ ! -f "lib/zlib-$ZLIBVER/libz.a" ]; then
    say "building static zlib $ZLIBVER"
    ( cd lib
      [ -f zlib.tar.gz ] || curl -fL -o zlib.tar.gz \
          "https://github.com/madler/zlib/releases/download/v$ZLIBVER/zlib-$ZLIBVER.tar.gz"
      tar xzf zlib.tar.gz
      cd "zlib-$ZLIBVER"
      mingw32-make -f win32/Makefile.gcc libz.a )
fi
ZLIB="$(cygpath -m "$SRC/lib/zlib-$ZLIBVER")"   # native G:/... path for MinGW gcc
SHIM="$(cygpath -m "$SRC/_shim")"
say "zlib: $ZLIB"

# --- 3. flye-minimap2 (static) -------------------------------------------------
say "building flye-minimap2 (static)"
( cd lib/minimap2
  mingw32-make clean >/dev/null 2>&1 || true
  mingw32-make -j "$JOBS" CC=gcc INCLUDES="-I../zlib-$ZLIBVER" \
       LIBS="-static -lm ../zlib-$ZLIBVER/libz.a -lpthread" )
cp lib/minimap2/minimap2.exe bin/flye-minimap2.exe

# --- 4. htslib (static libhts.a) -----------------------------------------------
say "configuring + building htslib 1.9 (static)"
( cd lib/samtools-1.9/htslib-1.9
  mingw32-make distclean >/dev/null 2>&1 || true
  ./configure --disable-bz2 --disable-lzma --disable-libcurl CC=gcc \
      CFLAGS="-O2 -fcommon -I$ZLIB -D_FILE_OFFSET_BITS=64" LDFLAGS="-L$ZLIB"
  mingw32-make -j "$JOBS" libhts.a )

# --- 5. flye-samtools (static) -------------------------------------------------
say "configuring + building flye-samtools 1.9 (static)"
( cd lib/samtools-1.9
  mingw32-make distclean >/dev/null 2>&1 || true
  ./configure --without-curses --disable-bz2 --disable-lzma --with-htslib=htslib-1.9 CC=gcc \
      CFLAGS="-O2 -fcommon -I$ZLIB -I$SHIM -D_FILE_OFFSET_BITS=64" LDFLAGS="-L$ZLIB"
  # -static on the final link drops libwinpthread-1.dll (WS2_32 is a Windows system DLL).
  mingw32-make samtools ALL_LDFLAGS="-L$ZLIB -static" )
cp lib/samtools-1.9/samtools.exe bin/flye-samtools.exe

# --- 6. flye-modules (the C++ core, static) ------------------------------------
say "building flye-modules (static)"
mingw32-make -C src release -j "$JOBS" CXX=g++ BIN_DIR=../bin \
    CXXFLAGS="-O3 -DNDEBUG -std=c++11 -pthread -Wall -Wextra -Wno-missing-field-initializers \
              -I../lib/libcuckoo -I../lib/interval_tree -I../lib/lemon -I../lib/minimap2 \
              -I../lib/zlib-$ZLIBVER -I../_shim" \
    LDFLAGS="-pthread -std=c++11 -static ../lib/minimap2/libminimap2.a \
             ../lib/zlib-$ZLIBVER/libz.a -lpsapi"

# --- 7. verify fully static ----------------------------------------------------
say "verifying static linkage (only KERNEL32 / UCRT / WS2_32 are allowed)"
bad=0
for exe in bin/flye-modules.exe bin/flye-minimap2.exe bin/flye-samtools.exe; do
    dlls="$(objdump -p "$exe" | awk '/DLL Name/{print $3}' \
            | grep -ivE 'KERNEL32|api-ms-win-crt|WS2_32' || true)"
    if [ -n "$dlls" ]; then echo "  !! $exe depends on: $dlls"; bad=1
    else echo "  ok $exe"; fi
done
[ "$bad" = 0 ] || die "a binary is not fully static (see above)"

# --- 8. stage the install tree -------------------------------------------------
say "staging install tree -> $OUT"
rm -rf "$OUT"; mkdir -p "$OUT/bin"
cp bin/flye-modules.exe bin/flye-minimap2.exe bin/flye-samtools.exe bin/flye "$OUT/bin/"
cp -r flye "$OUT/flye"
find "$OUT/flye" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true

say "DONE."
say "Run it with:   python \"$OUT/bin/flye\" --help"
