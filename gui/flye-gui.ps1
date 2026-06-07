# Flye for Windows - minimal graphical front-end for non-technical users.
# Pure PowerShell + WinForms (.NET Framework, present on every Windows 10/11) - no
# extra runtime. It just drives the bundled Flye (embedded Python + bin\flye).
# Launched console-less via Flye-GUI.vbs. Run with -SelfTest to build the UI and
# exit (used by CI to verify the form constructs).
param([switch]$SelfTest)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# --- locate the bundled Flye (installed layout: <app>\gui, <app>\python, <app>\bin, <app>\flye) ---
$app    = Split-Path $PSScriptRoot -Parent
$python = Join-Path $app 'python\python.exe'
$flye   = Join-Path $app 'bin\flye'
if (-not (Test-Path $python)) { $python = 'python' }            # dev fallback: system Python

# --- palette ---
$NAVY  = [System.Drawing.Color]::FromArgb(27,42,74)
$BLUE  = [System.Drawing.Color]::FromArgb(47,109,181)
$BG    = [System.Drawing.Color]::FromArgb(245,246,248)
$INK   = [System.Drawing.Color]::FromArgb(33,37,41)
$UIFONT = New-Object System.Drawing.Font('Segoe UI', 9.75)

# --- sensible default thread count ---
$cpu = [Environment]::ProcessorCount
$defThreads = [math]::Min([math]::Max($cpu,1), 32)

# read-type presets: display label -> flye flag
$readtypes = [ordered]@{
    'Nanopore - high quality (R10 / R9.4.1, Guppy5+)   [--nano-hq]'  = '--nano-hq'
    'Nanopore - raw / older basecalling                [--nano-raw]' = '--nano-raw'
    'Nanopore - corrected                              [--nano-corr]'= '--nano-corr'
    'PacBio - HiFi (CCS)                              [--pacbio-hifi]'= '--pacbio-hifi'
    'PacBio - raw (CLR)                                [--pacbio-raw]'= '--pacbio-raw'
    'PacBio - corrected                               [--pacbio-corr]'= '--pacbio-corr'
}

# ---------------------------------------------------------------- form
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Flye for Windows'
$form.Size = New-Object System.Drawing.Size(680, 600)
$form.MinimumSize = New-Object System.Drawing.Size(560, 520)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $BG
$form.Font = $UIFONT
try { $form.Icon = [System.Drawing.SystemIcons]::Application } catch {}

# header strip
$header = New-Object System.Windows.Forms.Panel
$header.Size = New-Object System.Drawing.Size(680, 58)
$header.Location = New-Object System.Drawing.Point(0, 0)
$header.BackColor = $NAVY
$header.Anchor = 'Top,Left,Right'
$title = New-Object System.Windows.Forms.Label
$title.Text = 'Flye for Windows'
$title.ForeColor = [System.Drawing.Color]::White
$title.Font = New-Object System.Drawing.Font('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)
$title.Location = New-Object System.Drawing.Point(16, 8); $title.AutoSize = $true
$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = 'native long-read genome assembly (Nanopore / PacBio) - no setup required'
$subtitle.ForeColor = [System.Drawing.Color]::FromArgb(190,205,225)
$subtitle.Location = New-Object System.Drawing.Point(18, 36); $subtitle.AutoSize = $true
$header.Controls.AddRange(@($title, $subtitle))
$form.Controls.Add($header)

# helpers
function New-Label($text, $x, $y) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.Location = New-Object System.Drawing.Point($x, $y); $l.AutoSize = $true; $l.ForeColor = $INK
    return $l
}
function New-TextBox($x, $y, $w) {
    $t = New-Object System.Windows.Forms.TextBox
    $t.Location = New-Object System.Drawing.Point($x, $y); $t.Size = New-Object System.Drawing.Size($w, 24)
    $t.Anchor = 'Top,Left,Right'
    return $t
}
function New-Button($text, $x, $y, $w) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.Location = New-Object System.Drawing.Point($x, $y); $b.Size = New-Object System.Drawing.Size($w, 25)
    $b.FlatStyle = 'Flat'; $b.BackColor = [System.Drawing.Color]::White
    return $b
}

$lblReads = New-Label 'Long-read file (FASTQ / FASTA, optionally .gz)' 16 76; $form.Controls.Add($lblReads)
$txtReads = New-TextBox 16 98 530; $form.Controls.Add($txtReads)
$btnReads = New-Button 'Browse...' 552 97 96; $btnReads.Anchor='Top,Right'; $form.Controls.Add($btnReads)

$lblOut = New-Label 'Output folder' 16 130; $form.Controls.Add($lblOut)
$txtOut = New-TextBox 16 152 530; $form.Controls.Add($txtOut)
$btnOut = New-Button 'Browse...' 552 151 96; $btnOut.Anchor='Top,Right'; $form.Controls.Add($btnOut)

$lblType = New-Label 'Read type' 16 184; $form.Controls.Add($lblType)
$cmbType = New-Object System.Windows.Forms.ComboBox
$cmbType.Location = New-Object System.Drawing.Point(16, 206); $cmbType.Size = New-Object System.Drawing.Size(632, 24)
$cmbType.DropDownStyle = 'DropDownList'; $cmbType.Anchor = 'Top,Left,Right'
foreach ($k in $readtypes.Keys) { [void]$cmbType.Items.Add($k) }
$cmbType.SelectedIndex = 0
$form.Controls.Add($cmbType)

$lblG = New-Label 'Genome size (optional, e.g. 5m, 4.6m, 120k)' 16 238; $form.Controls.Add($lblG)
$txtG = New-Object System.Windows.Forms.TextBox
$txtG.Location = New-Object System.Drawing.Point(16, 260); $txtG.Size = New-Object System.Drawing.Size(170, 24); $form.Controls.Add($txtG)

$lblT = New-Label 'Threads' 210 238; $form.Controls.Add($lblT)
$numT = New-Object System.Windows.Forms.NumericUpDown
$numT.Location = New-Object System.Drawing.Point(210, 260); $numT.Size = New-Object System.Drawing.Size(70, 24)
$numT.Minimum = 1; $numT.Maximum = 256; $numT.Value = $defThreads; $form.Controls.Add($numT)

$chkMeta = New-Object System.Windows.Forms.CheckBox
$chkMeta.Text = 'Metagenome (--meta)'; $chkMeta.Location = New-Object System.Drawing.Point(300, 261)
$chkMeta.AutoSize = $true; $form.Controls.Add($chkMeta)

$chkKeepHap = New-Object System.Windows.Forms.CheckBox
$chkKeepHap.Text = 'Keep haplotypes'; $chkKeepHap.Location = New-Object System.Drawing.Point(470, 261)
$chkKeepHap.AutoSize = $true; $form.Controls.Add($chkKeepHap)

# run / open buttons
$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = 'Run assembly'; $btnRun.Location = New-Object System.Drawing.Point(16, 296)
$btnRun.Size = New-Object System.Drawing.Size(150, 34); $btnRun.FlatStyle = 'Flat'
$btnRun.BackColor = $BLUE; $btnRun.ForeColor = [System.Drawing.Color]::White
$btnRun.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnRun)

$btnOpen = New-Button 'Open output folder' 176 300 150; $btnOpen.Enabled = $false; $form.Controls.Add($btnOpen)

# progress + status
$prog = New-Object System.Windows.Forms.ProgressBar
$prog.Location = New-Object System.Drawing.Point(16, 340); $prog.Size = New-Object System.Drawing.Size(632, 8)
$prog.Style = 'Marquee'; $prog.MarqueeAnimationSpeed = 0; $prog.Anchor='Top,Left,Right'; $form.Controls.Add($prog)

$status = New-Label 'Ready.' 16 352; $status.Anchor='Top,Left'; $status.ForeColor = $NAVY; $form.Controls.Add($status)

# log
$log = New-Object System.Windows.Forms.TextBox
$log.Location = New-Object System.Drawing.Point(16, 376); $log.Size = New-Object System.Drawing.Size(632, 168)
$log.Multiline = $true; $log.ReadOnly = $true; $log.ScrollBars = 'Vertical'; $log.WordWrap = $false
$log.BackColor = [System.Drawing.Color]::FromArgb(30,30,30); $log.ForeColor = [System.Drawing.Color]::FromArgb(212,212,212)
$log.Font = New-Object System.Drawing.Font('Consolas', 9)
$log.Anchor = 'Top,Bottom,Left,Right'
$form.Controls.Add($log)

# ---------------------------------------------------------------- behaviour
$script:proc = $null
$script:logPath = $null
$script:logPos = 0
$script:outDir = $null

$btnReads.Add_Click({
    $d = New-Object System.Windows.Forms.OpenFileDialog
    $d.Filter = 'Long reads (*.fastq;*.fq;*.fasta;*.fa;*.gz)|*.fastq;*.fq;*.fasta;*.fa;*.fastq.gz;*.fq.gz;*.fasta.gz;*.fa.gz|All files (*.*)|*.*'
    if ($d.ShowDialog() -eq 'OK') { $txtReads.Text = $d.FileName }
})
$btnOut.Add_Click({
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($d.ShowDialog() -eq 'OK') { $txtOut.Text = $d.SelectedPath }
})
$btnOpen.Add_Click({ if ($script:outDir -and (Test-Path $script:outDir)) { Start-Process explorer.exe $script:outDir } })

function Read-NewLog {
    if (-not $script:logPath -or -not (Test-Path $script:logPath)) { return '' }
    try {
        $fs = [System.IO.File]::Open($script:logPath, 'Open', 'Read', 'ReadWrite')
        [void]$fs.Seek($script:logPos, 'Begin')
        $sr = New-Object System.IO.StreamReader($fs)
        $new = $sr.ReadToEnd(); $script:logPos = $fs.Position
        $sr.Close(); $fs.Close(); return $new
    } catch { return '' }
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 800
$timer.Add_Tick({
    $new = Read-NewLog
    if ($new.Length) { $log.AppendText($new) }
    if ($script:proc -and $script:proc.HasExited) {
        $timer.Stop()
        $log.AppendText((Read-NewLog))
        $prog.MarqueeAnimationSpeed = 0
        $btnRun.Enabled = $true
        if ($script:proc.ExitCode -eq 0) {
            $status.Text = "Done. Assembly: $(Join-Path $script:outDir 'assembly.fasta')"
            $status.ForeColor = [System.Drawing.Color]::FromArgb(20,120,60)
            $btnOpen.Enabled = $true
        } else {
            $status.Text = "Flye failed (exit $($script:proc.ExitCode)). See the log / flye.log."
            $status.ForeColor = [System.Drawing.Color]::FromArgb(170,30,30)
            $btnOpen.Enabled = (Test-Path $script:outDir)
        }
    }
})

$btnRun.Add_Click({
    $reads = $txtReads.Text.Trim(); $out = $txtOut.Text.Trim()
    if (-not $reads -or -not (Test-Path $reads)) { [System.Windows.Forms.MessageBox]::Show('Please choose a valid long-read file.','Flye'); return }
    if (-not $out) { [System.Windows.Forms.MessageBox]::Show('Please choose an output folder.','Flye'); return }
    if (-not (Test-Path $flye)) { [System.Windows.Forms.MessageBox]::Show("Bundled Flye not found at:`n$flye",'Flye'); return }
    New-Item -ItemType Directory -Force -Path $out | Out-Null

    # Build a single, properly-quoted argument string. Start-Process -ArgumentList with an
    # ARRAY does not reliably quote elements containing spaces on Windows PowerShell 5.1, so a
    # spaced path would split. Quoting each path fixes it.
    $q = { param($s) '"' + $s + '"' }
    $parts = New-Object System.Collections.ArrayList
    [void]$parts.Add((& $q $flye))
    [void]$parts.Add($readtypes[$cmbType.SelectedItem])      # --nano-hq / --pacbio-raw / ...
    [void]$parts.Add((& $q $reads))
    $g = $txtG.Text.Trim()
    if ($g) { [void]$parts.Add('-g'); [void]$parts.Add($g) }
    if ($chkMeta.Checked)    { [void]$parts.Add('--meta') }
    if ($chkKeepHap.Checked) { [void]$parts.Add('--keep-haplotypes') }
    [void]$parts.Add('-o'); [void]$parts.Add((& $q $out))
    [void]$parts.Add('-t'); [void]$parts.Add([string]$numT.Value)
    $argline = ($parts -join ' ')

    $script:outDir = $out
    # Flye writes its full progress log to <out>\flye.log; tail that. Also capture the
    # console (stderr/stdout) for diagnosing failures that happen before flye.log exists.
    $script:logPath = Join-Path $out 'flye.log'
    $conOut = Join-Path $out 'gui_console.out.log'
    $conErr = Join-Path $out 'gui_console.err.log'
    if (Test-Path $script:logPath) { Remove-Item $script:logPath -Force -ErrorAction SilentlyContinue }
    $script:logPos = 0
    $log.Clear()
    $log.AppendText("> " + (& $q $python) + " " + $argline + "`r`n`r`n")
    $btnRun.Enabled = $false; $btnOpen.Enabled = $false
    $prog.MarqueeAnimationSpeed = 30
    $status.Text = 'Running... (long-read assembly can take several minutes)'
    $status.ForeColor = $NAVY
    try {
        $script:proc = Start-Process -FilePath $python -ArgumentList $argline `
            -NoNewWindow -PassThru -RedirectStandardOutput $conOut -RedirectStandardError $conErr
        $timer.Start()
    } catch {
        $prog.MarqueeAnimationSpeed = 0; $btnRun.Enabled = $true
        $status.Text = "Could not start Flye: $($_.Exception.Message)"
        $status.ForeColor = [System.Drawing.Color]::FromArgb(170,30,30)
    }
})

if ($SelfTest) { Write-Output 'SELFTEST OK'; return }
[void]$form.ShowDialog()
