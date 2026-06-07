# Flye -> native Windows: what the port actually changes

Flye is a Unix long-read assembler: a Python driver (`flye/`) orchestrating a C++
core (`flye-modules`) plus bundled `minimap2` and `samtools`/`htslib`. Getting it
to run **natively on Windows** (no WSL, no Cygwin runtime, no Docker) and **fully
statically linked** (no `libwinpthread-1.dll`, `libstdc++-6.dll`, ... only Windows
system DLLs) took a surprisingly small patch plus two header shims and a precise
build recipe. This is the whole surface.

The source patch is [`flye-mingw.patch`](flye-mingw.patch) (8 files). The shims are
in [`shim/`](shim). The build that wires it together is
[`../build_flye.sh`](../build_flye.sh).

---

## 1. C++ core (`flye-modules`)

### LLP64: `std::max(size_t, 1UL)` won't compile  — `src/repeat_graph/repeat_resolver.cpp`
On Windows (LLP64) `unsigned long` is **32-bit** while `size_t` is **64-bit**, so
`std::max(some.size(), 1UL)` has two different types and template argument
deduction fails. (On Linux/LP64 both are 64-bit, so it compiles there.) Fixed by
making the literal a `size_t`: `std::max(..., (size_t)1)`. Two call sites.

The core already guards its Unix-isms (`sysconf`/`getrusage`/`sysctl`) behind
`#ifdef __unix__`, and `common/memory_info.h` already has a `_WIN32` branch, so no
`fork()`, `mmap`, or `std::filesystem` problems to chase.

### The hardest bug: heap corruption from `thread_local` at thread exit — `src/common/parallel.h`
This one is a **MinGW-w64 toolchain defect**, not a Flye bug, and it took the longest to
corner. Symptom: assembly runs fine at `-t 1` but dies with `STATUS_HEAP_CORRUPTION`
(`0xC0000374`) at `-t 4`+, with the crash location *wandering* between runs (overlap
estimation, disjointig extension, consensus, …). That wandering is the giveaway of a
single wild write, not many bugs.

A three-line repro nails it: 16 `std::thread`s, each touching one
`thread_local std::vector`, even for a single round, heap-corrupts on this compiler —
**static or dynamic**. Trivial `thread_local`s and ones whose destructor does *not* free
heap are fine; the trigger is a `thread_local` whose destructor **frees memory** when a
`std::thread` exits (the `__cxa_thread_atexit` path). Flye leans on `thread_local`
scratch buffers (k-mer match lists, DP tables, kalloc pools) inside every parallel loop,
and upstream `processInParallel` spawns and **joins a fresh batch of threads on every
call** — so those destructors ran constantly and smashed the heap under load.

Fix: `processInParallel` now runs on a **persistent pool of detached worker threads**,
created once and never joined (the OS reclaims them at process exit). The workers' thread
locals are therefore constructed once and **never destroyed**, so the buggy teardown path
never runs. It's also faster than respawning threads for every parallel region.

### Thread-safe logging — `src/common/logger.h`
`Logger`'s `StreamWriter` wrote straight to a shared `std::ofstream` (and `std::cerr`)
with no lock. With debug logging on, the parallel loops log concurrently, racing the
`ofstream`'s `filebuf` and corrupting the heap on Windows. Each log message now holds a
mutex for the `StreamWriter`'s whole lifetime (one statement = one atomic line). A manual
move constructor was added because the `unique_lock` member makes `StreamWriter`
non-copyable and the user destructor suppresses the implicit move.

### Correct `BFContainer` random-access iterator — `src/common/bfcontainer.h`
`BFContainer` (the chunked vector for billion-element arrays) had an iterator that
violated the `RandomAccessIterator` contract: `operator[]` **mutated `*this`**, and
post-`++`/`--` returned **dangling references** to locals. `std::sort` falls back to
heapsort for large inputs and leans on `it[n]`; at high coverage a single read's k-mer
matches span multiple chunks, so this could corrupt. Fixed to a correct iterator.

### `execinfo.h` shim  — `shim/execinfo.h`
The crash handler (`common/utils.h`, `assemble/main_assemble.cpp`) uses glibc's
`backtrace()`/`backtrace_symbols()` from `<execinfo.h>`, which MinGW does not ship.
The shim provides no-op stubs so the handler compiles; on a crash you simply get
no symbolic stack trace (the process still exits cleanly).

---

## 2. `flye-minimap2` (vendored minimap2 2.24)

### Binary stdout  — `lib/minimap2/main.c`
minimap2 streams SAM text to stdout, which Flye pipes into samtools. On Windows the
C runtime opens stdout in **text mode**, rewriting every `\n` to `\r\n`. That
corrupts the downstream uncompressed-BAM stream (`Invalid BAM binary header`). Fix:
`_setmode(_fileno(stdout), _O_BINARY)` (and stdin) at the top of `main()`, under
`#ifdef _WIN32`.

Everything else is build flags (see below): static link + the vendored static zlib.

---

## 3. `flye-samtools` (vendored samtools + htslib 1.9)

No samtools/htslib **source** changes are needed — two things already exist
upstream and just had to be switched on or worked around:

* **`samtools` already sets binary mode** for stdin/stdout in `bamtk.c`
  (`setmode(fileno(stdout), O_BINARY)` under `#ifdef _WIN32`), so its own SAM/BAM
  stream handling is correct on Windows.
* **htslib already has** `setmode(fd, O_BINARY)` for the `-` (stdin/stdout) case
  and `O_BINARY` for file opens.

### `regex.h` shim  — `shim/regex.h`
MinGW ships no POSIX C `<regex.h>`. The only consumers in samtools 1.9 are
`bam_split.c` (`samtools split`) and `bam_tview.c` (curses, already excluded by
`--without-curses`). Flye invokes neither, so the shim provides stub
`regcomp`/`regexec`/... that let the objects compile and link; they report "no
match" if ever called.

### The one behavioural workaround lives in Python, not C: piping into `samtools sort`
On native Windows, htslib's bgzf reader **cannot read a binary BAM stream from an
anonymous pipe** — the first read of a piped stdin returns EOF immediately
(`Read block operation failed ... after 0 of 4 bytes`), even though `samtools view`
reading *text* SAM from a pipe works fine and `samtools sort` reading the same BAM
from a *file* works fine. So instead of
`minimap2 | samtools view | samtools sort`, the port does
`minimap2 | samtools view -o tmp.bam` (view reads the pipe, writes a temp BAM) then
`samtools sort tmp.bam` (sort reads the file). See item 4.

---

## 4. Python driver (`flye/`)

### Find `.exe` helpers  — `flye/utils/utils.py`
Flye's `which()` looks up its helpers by bare name (`flye-modules`), which never
matches `flye-modules.exe`. Patched to also try the `PATHEXT` suffixes on Windows.

### No `/bin/bash`, no pipe-into-sort  — `flye/polishing/alignment.py`
Upstream builds the alignment as a shell string run through
`/bin/bash -c "minimap2 ... | samtools view ... | samtools sort ..."` with
`pipefail`. `/bin/bash` doesn't exist on a stock Windows box. Rewritten to drive
the pipeline with `subprocess` (no shell, so paths with spaces need no quoting),
and — per item 3 — to route `samtools view` output through a temp BAM file that
`samtools sort` reads, instead of a second pipe. Portable back to Linux.

### `shell=True` region queries  — `flye/utils/sam_parser.py`
Three calls ran `samtools depth/view ... '<ctg>:<start>-<end>'` with `shell=True`.
On Windows `cmd.exe` does not strip the single quotes, so samtools saw a literal
`'ctg:..'` region and failed. Rewritten as list-form `subprocess.Popen([...])`
(no shell, no quotes).

---

## 5. Build recipe (no source change, but essential)

All in [`../build_flye.sh`](../build_flye.sh):

| Concern | What the build does |
|---|---|
| **Large files >2 GB** | `-D_FILE_OFFSET_BITS=64` for htslib/samtools (32-bit `off_t` otherwise) |
| **Fully static** | `-static` on every final link -> no `libwinpthread-1.dll`/`libstdc++`/`libgcc` |
| **Windows memory API** | link `flye-modules` with `-lpsapi` (used by `common/memory_info.h`) |
| **GCC strictness** | `-fcommon` for the 2018-era htslib/samtools C |
| **zlib** | build a static `libz.a` once; link it into minimap2, htslib, flye-modules |
| **MinGW path quirk** | pass include/lib dirs as native `G:/...` paths (`cygpath -m`); the winlibs gcc does **not** understand git-bash `/g/...` paths |
| **curses/bz2/lzma/curl** | `./configure --without-curses --disable-bz2 --disable-lzma --disable-libcurl` (none needed by Flye) |

The result: `flye-modules.exe`, `flye-minimap2.exe`, `flye-samtools.exe` each
depend only on `KERNEL32.dll`, the `api-ms-win-crt-*` Universal CRT, and (samtools
only) `WS2_32.dll` — all shipped with Windows.

---

## Pinned source

`flye-src-886b8c1.tar.gz` is a `git archive` of Flye **2.9.6** (commit `886b8c1`),
including its vendored minimap2 2.24 and samtools/htslib 1.9. It is bundled so a
build never depends on upstream staying reachable or unchanged — the patch is
guaranteed to apply.
