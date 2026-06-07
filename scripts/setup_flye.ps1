<#
.SYNOPSIS
    Build native-Windows Flye (fully static) from the vendored, pinned source.

.DESCRIPTION
    One command to go from a clean Windows box to a working Flye:

      1. Installs the winlibs MinGW-w64 toolchain (via setup_toolchain.ps1) if it
         is not already present. This is a BUILD-time dependency only.
      2. Runs build_flye.sh, which extracts the pinned Flye source, applies the
         Windows port patch + POSIX shims, and builds zlib, flye-minimap2,
         flye-samtools and flye-modules - all statically linked.

    The autoconf/htslib build needs a POSIX shell, so the heavy lifting lives in
    build_flye.sh (bash); this wrapper just locates git-bash and wires it up.

    Result: a ready-to-run tree (bin\ + flye\) with NO MinGW runtime DLLs - only
    the Windows system DLLs (KERNEL32, the UCRT, WS2_32) are referenced. Nothing
    needs to be pre-installed to RUN it except a Python 3 interpreter.

.PARAMETER OutDir
    Where to stage the install tree. Default: %LOCALAPPDATA%\flye-install
#>
[CmdletBinding()]
param(
    [string]$OutDir = (Join-Path $env:LOCALAPPDATA 'flye-install')
)

$ErrorActionPreference = 'Stop'
function Info($m) { Write-Host "[setup] $m" -ForegroundColor Cyan }
function Die($m)  { Write-Host "[setup] ERROR: $m" -ForegroundColor Red; exit 1 }

$here = $PSScriptRoot

# --- 1. MinGW-w64 toolchain (winlibs) ----------------------------------------
$gcc = Join-Path $env:LOCALAPPDATA 'winlibs\mingw64\bin\gcc.exe'
if (-not (Test-Path $gcc)) {
    Info "Installing MinGW-w64 toolchain (winlibs)..."
    & (Join-Path $here 'setup_toolchain.ps1')
}
if (-not (Test-Path $gcc)) { Die "MinGW-w64 toolchain not found after setup_toolchain.ps1." }
Info "Toolchain: $gcc"

# --- 2. locate git-bash (needed for autoconf/htslib) -------------------------
$bash = $null
$cands = @(
    "$env:ProgramFiles\Git\bin\bash.exe",
    "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
    "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
)
foreach ($c in $cands) { if (Test-Path $c) { $bash = $c; break } }
if (-not $bash) {
    $g = Get-Command git -ErrorAction SilentlyContinue
    if ($g) {
        $cand = Join-Path (Split-Path (Split-Path $g.Source -Parent) -Parent) 'bin\bash.exe'
        if (Test-Path $cand) { $bash = $cand }
    }
}
if (-not $bash) { Die "git-bash (bash.exe) not found. Install Git for Windows: https://git-scm.com/download/win" }
Info "Using bash: $bash"

# --- 3. run the build --------------------------------------------------------
$buildSh = Join-Path $here 'build_flye.sh'
if (-not (Test-Path $buildSh)) { Die "build_flye.sh not found next to this script." }

# Convert Windows paths to the /c/... form bash/cygpath expect.
$buildUnix = (& $bash -c "cygpath -u '$buildSh'").Trim()
$outUnix   = (& $bash -c "cygpath -u '$OutDir'").Trim()

Info "Building (this compiles minimap2, htslib, samtools and the C++ core)..."
& $bash -lc "'$buildUnix' '$outUnix'"
if ($LASTEXITCODE -ne 0) { Die "build_flye.sh failed with exit code $LASTEXITCODE" }

Write-Host ""
Info "DONE -> $OutDir"
Info "Try it:   python `"$OutDir\bin\flye`" --version"
Info "          python `"$OutDir\bin\flye`" --nano-raw reads.fastq.gz -g 5m -o out_dir -t 8"
