<#
.SYNOPSIS
    Build a single one-click Windows installer for the native Flye port.

.DESCRIPTION
    Stages a self-contained payload and compiles it into Flye-Windows-<ver>-Setup.exe
    with Inno Setup. The payload bundles everything needed to run Flye on a stock
    Windows machine with NO prerequisites (no WSL/Docker, no system Python, no MinGW):

        bin\      static flye-modules / flye-minimap2 / flye-samtools .exe + `flye` + flye.bat
        flye\     the Flye Python package (+ bundled toy test data)
        python\   embedded Python 3.11 (downloaded if not cached)
        gui\      the WinForms front-end + console-less VBS launcher
        flye-shell.bat, README-WINDOWS.txt, LICENSE

    Run AFTER building the binaries (scripts\setup_flye.ps1), or just from the repo,
    which already ships prebuilt bin\ and flye\.

.PARAMETER SrcRoot
    The repo root containing bin\, flye\, gui\, LICENSE. Default: two levels up.

.PARAMETER OutDir
    Where to write the Setup .exe. Default <repo>\dist.

.PARAMETER PythonVersion
    Embeddable Python version to bundle. Default 3.11.9.
#>
[CmdletBinding()]
param(
    [string]$SrcRoot       = '',
    [string]$OutDir        = '',
    [string]$PythonVersion = '3.11.9',
    [string]$Iscc          = ''
)

$ErrorActionPreference = 'Stop'
function Info($m) { Write-Host "[installer] $m" -ForegroundColor Cyan }
function Die($m)  { Write-Host "[installer] ERROR: $m" -ForegroundColor Red; exit 1 }

# $PSScriptRoot is empty inside param() defaults when launched via -File, so resolve here.
$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path $MyInvocation.MyCommand.Path -Parent }
if (-not $SrcRoot) { $SrcRoot = Split-Path (Split-Path $here -Parent) -Parent }
if (-not $OutDir)  { $OutDir  = Join-Path $SrcRoot 'dist' }
$iss  = Join-Path $here 'flye_windows.iss'
$work    = Join-Path $env:LOCALAPPDATA 'flye-dist'
$payload = Join-Path $work 'payload'
$dl      = Join-Path $work 'dl'

# --- sanity: the binaries + package must be present ---
foreach ($need in @('bin\flye-modules.exe','bin\flye-minimap2.exe','bin\flye-samtools.exe','bin\flye','flye\main.py','gui\flye-gui.ps1','LICENSE')) {
    if (-not (Test-Path (Join-Path $SrcRoot $need))) { Die "missing '$need' under '$SrcRoot'. Build binaries (setup_flye.ps1) first." }
}

# --- version (from flye/__version__.py) ---
$version = '2.9.6'
$verPy = Join-Path $SrcRoot 'flye\__version__.py'
if (Test-Path $verPy) {
    $m = Select-String -Path $verPy -Pattern "__version__\s*=\s*['""]([^'""]+)['""]" | Select-Object -First 1
    if ($m) { $version = $m.Matches[0].Groups[1].Value }
}
Info "Flye version: $version"

# --- locate ISCC ---
if (-not $Iscc) {
    $cands = @(
        (Join-Path $env:LOCALAPPDATA 'InnoSetup6\ISCC.exe'),
        'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
        'C:\Program Files\Inno Setup 6\ISCC.exe'
    )
    $Iscc = $cands | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $Iscc -or -not (Test-Path $Iscc)) {
    Die "ISCC.exe (Inno Setup 6) not found. Install from https://jrsoftware.org/isdl.php or pass -Iscc."
}

# --- embedded Python (download if needed) ---
New-Item -ItemType Directory -Force -Path $dl | Out-Null
$pyZip = Join-Path $dl "python-$PythonVersion-embed-amd64.zip"
if (-not (Test-Path $pyZip)) {
    $url = "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-embed-amd64.zip"
    Info "Downloading embeddable Python $PythonVersion ..."
    Invoke-WebRequest -Uri $url -OutFile $pyZip -UseBasicParsing
}

# --- stage payload from scratch ---
if (Test-Path $payload) { Remove-Item $payload -Recurse -Force }
New-Item -ItemType Directory -Force -Path $payload | Out-Null

Info "Staging bin\, flye\, gui\ ..."
Copy-Item (Join-Path $SrcRoot 'bin')  (Join-Path $payload 'bin')  -Recurse -Force
Copy-Item (Join-Path $SrcRoot 'flye') (Join-Path $payload 'flye') -Recurse -Force
Copy-Item (Join-Path $SrcRoot 'gui')  (Join-Path $payload 'gui')  -Recurse -Force
Copy-Item (Join-Path $SrcRoot 'LICENSE') (Join-Path $payload 'LICENSE') -Force
Get-ChildItem $payload -Recurse -Directory -Filter '__pycache__' | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

Info "Staging embedded Python ..."
$pyDir = Join-Path $payload 'python'
New-Item -ItemType Directory -Force -Path $pyDir | Out-Null
Expand-Archive -Path $pyZip -DestinationPath $pyDir -Force
# Point the embedded interpreter at the app root so the `flye` package imports.
$pthName = (Get-ChildItem $pyDir -Filter 'python*._pth' | Select-Object -First 1).Name
$pyMajorMinor = ($PythonVersion -split '\.')[0..1] -join ''
@(
    "python$pyMajorMinor.zip"
    '.'
    '..'
    'import site'
) | Set-Content -Path (Join-Path $pyDir $pthName) -Encoding ascii

# --- launchers ---
Info "Generating launchers ..."
# `flye` command (bin\flye.bat -> on PATH via the installer's addtopath task)
$flyeBat = @"
@echo off
rem Flye launcher - runs the bundled Flye with the bundled Python.
"%~dp0..\python\python.exe" "%~dp0flye" %*
"@
Set-Content -Path (Join-Path $payload 'bin\flye.bat') -Value $flyeBat -Encoding ascii

# "Flye Command Prompt"
$shell = @"
@echo off
set "PATH=%~dp0bin;%~dp0python;%PATH%"
title Flye for Windows
echo ============================================================
echo   Flye for Windows ($version) is ready.
echo.
echo   Try:   flye --version
echo          flye --help
echo          flye --nano-hq reads.fastq.gz -o out_dir -t 8
echo          flye --pacbio-hifi reads.fastq.gz -o out_dir -t 8
echo.
echo   Read types: --nano-raw --nano-hq --nano-corr
echo               --pacbio-raw --pacbio-hifi --pacbio-corr
echo ============================================================
echo.
cd /d "%USERPROFILE%"
cmd /k
"@
Set-Content -Path (Join-Path $payload 'flye-shell.bat') -Value $shell -Encoding ascii

# --- README ---
$readme = @"
Flye for Windows (native port) $version
=======================================

This is a fully self-contained, native-Windows build of the Flye long-read
genome assembler. No WSL, Docker, Linux VM, system Python, or compiler is
required - everything (the assembler binaries and a private Python 3.11) is
bundled here.

Quick start
-----------
  * Double-click "Flye for Windows (app)" in the Start Menu for the graphical
    interface: pick your reads, the read type, an output folder, and Run.

  * Or use the "Flye Command Prompt" shortcut and type:
        flye --version
        flye --nano-hq  reads.fastq.gz -o out_dir -t 8
        flye --pacbio-hifi reads.fastq.gz -o out_dir -t 8

  * If you ticked "Add Flye to my PATH" during install, the 'flye' command works
    in any terminal.

Read types:  --nano-raw  --nano-hq  --nano-corr
             --pacbio-raw  --pacbio-hifi  --pacbio-corr
Options:     -g <size> (e.g. 5m), --meta, --keep-haplotypes, -t <threads>

Output (in the -o directory): assembly.fasta, assembly_graph.gfa,
assembly_graph.gv, assembly_info.txt, flye.log.

Project: https://github.com/MrMufasii/Flye-for-Windows
"@
Set-Content -Path (Join-Path $payload 'README-WINDOWS.txt') -Value $readme -Encoding ascii

# --- compile the installer ---
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Info "Compiling installer with Inno Setup ..."
& $Iscc "/DPayloadDir=$payload" "/DOutputDir=$OutDir" "/DAppVersion=$version" $iss | Out-Host
if ($LASTEXITCODE -ne 0) { Die "ISCC failed with exit code $LASTEXITCODE" }

$setup = Join-Path $OutDir "Flye-Windows-$version-Setup.exe"
if (Test-Path $setup) {
    $mb = [math]::Round((Get-Item $setup).Length / 1MB, 1)
    Info "DONE -> $setup  ($mb MB)"
} else {
    Die "Installer was not produced."
}
