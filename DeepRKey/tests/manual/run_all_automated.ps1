# DeepRKey Automated Test Runner (T-011/012/013)
# Runs all programmatic tests; flags what requires human interaction.
#
# Usage: .\run_all_automated.ps1

param(
    [string]$ExePath = (Resolve-Path ".\bin\DeepRKey.exe").Path,
    [string]$ReportPath = ".\tests\manual\automated_report_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
)

$ErrorActionPreference = "Continue"
$script:results = @()
$script:pass = 0
$script:fail = 0
$script:skip = 0

function Record {
    param([string]$Category, [string]$Test, [string]$Target, [string]$Actual, [bool]$Passed, [string]$Notes = "")
    $status = if ($Passed) { "PASS" } elseif ($Target -eq "SKIP") { "SKIP" } else { "FAIL" }
    if ($Passed) { $script:pass++ }
    elseif ($status -eq "SKIP") { $script:skip++ }
    else { $script:fail++ }

    $color = if ($Passed) { "Green" } elseif ($status -eq "SKIP") { "Yellow" } else { "Red" }
    $tag = "[$status]"
    Write-Host "  $tag $Test" -ForegroundColor $color
    if (-not $Passed -and $status -ne "SKIP" -and $Notes) {
        Write-Host "        -> $Notes" -ForegroundColor DarkRed
    }

    $script:results += [PSCustomObject]@{
        Category = $Category; Test = $Test; Target = $Target
        Actual = $Actual; Result = $status; Notes = $Notes
    }
}

Write-Host "=== DeepRKey Automated Test Runner ===" -ForegroundColor Cyan
Write-Host "Start: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host "Exe:   $ExePath" -ForegroundColor Gray

if (-not (Test-Path $ExePath)) {
    Write-Error "Executable not found: $ExePath"
    exit 1
}

# ---------------------------------------------------------------------------
# Pre-cleanup: kill any existing DeepRKey
# ---------------------------------------------------------------------------
Get-Process -Name DeepRKey -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# ============================================================================
# PHASE 1: Unit Tests
# ============================================================================
Write-Host "`n[Phase 1/8] Unit Tests" -ForegroundColor Yellow

$testExe = ".\bin\DeepRKey.Tests.exe"
if (Test-Path $testExe) {
    $testOutput = & $testExe 2>&1 | Out-String
    $match = [regex]::Match($testOutput, '(\d+) passed, (\d+) failed, (\d+) total')
    if ($match.Success) {
        $passed = [int]$match.Groups[1].Value
        $failed = [int]$match.Groups[2].Value
        $total  = [int]$match.Groups[3].Value
        Record "Unit" "All unit tests pass" "0 failed" "$failed failed / $total total" ($failed -eq 0)
        Record "Unit" "Test count >= 180" ">= 180" "$total" ($total -ge 180)
    } else {
        Record "Unit" "Test runner output parseable" "parsed" "parse failed" $false
    }
} else {
    Record "Unit" "Test executable exists" "exists" "missing" $false
}

# ============================================================================
# PHASE 2: Build Artifacts
# ============================================================================
Write-Host "`n[Phase 2/8] Build Artifacts" -ForegroundColor Yellow

$binDir = Split-Path $ExePath
$artifacts = @{
    "DeepRKey.exe"          = 5MB    # Main exe should be > 5MB
    "DeepRKeyHook64.dll"    = 10KB   # Hook DLL should exist
    "DeepRKeyHook32.dll"    = 10KB   # 32-bit hook DLL
    "DeepRKey.Tests.exe"    = 100KB  # Test exe
    "DeepRKey32.exe"        = 100KB  # 32-bit helper
}

foreach ($name in $artifacts.Keys) {
    $path = Join-Path $binDir $name
    if (Test-Path $path) {
        $size = (Get-Item $path).Length
        $sizeKB = [math]::Round($size / 1024, 1)
        $minSize = $artifacts[$name]
        Record "Build" "$name exists and >= $([math]::Round($minSize/1024,1))KB" ">= $([math]::Round($minSize/1024,1))KB" "${sizeKB}KB" ($size -ge $minSize)
    } else {
        Record "Build" "$name exists" "exists" "missing" $false
    }
}

# Hook DLL 64-bit should be < 100KB (T-010c)
$dll64 = Join-Path $binDir "DeepRKeyHook64.dll"
if (Test-Path $dll64) {
    $size64 = (Get-Item $dll64).Length
    $size64KB = [math]::Round($size64 / 1024, 1)
    Record "Build" "Hook DLL 64-bit < 100KB (T-010c)" "< 100KB" "${size64KB}KB" ($size64 -lt 100KB)
}

# ============================================================================
# PHASE 3: Start DeepRKey & IPC
# ============================================================================
Write-Host "`n[Phase 3/8] Startup & IPC" -ForegroundColor Yellow

$startTime = Get-Date
Start-Process -FilePath $ExePath
# Wait for IPC window to appear
$ipcReady = $false
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 200
    $proc = Get-Process -Name DeepRKey -ErrorAction SilentlyContinue
    if ($proc) {
        $hwnd = (Get-Process -Name DeepRKey).MainWindowHandle
        # Also check for the hidden IPC window
        $diagOut = & $ExePath --diagnostics 2>&1 | Out-String
        if ($diagOut -match "Running") {
            $ipcReady = $true
            break
        }
    }
}
$elapsed = (Get-Date) - $startTime

Record "Startup" "DeepRKey process starts" "running" $(if($ipcReady){"running"}else{"not found"}) $ipcReady
Record "Startup" "IPC window appears within 6s" "< 6s" "$([math]::Round($elapsed.TotalSeconds, 2))s" ($elapsed.TotalSeconds -lt 6)

# Wait for Coordinator to fully initialize (hooks, GUID, menu injection)
Start-Sleep -Seconds 3

# ============================================================================
# PHASE 4: CLI Diagnostics
# ============================================================================
Write-Host "`n[Phase 4/8] CLI Diagnostics" -ForegroundColor Yellow

# Note: DeepRKey uses AllocConsole() for CLI output in GUI subsystem.
# PowerShell Start-Process -RedirectStandardOutput cannot capture AllocConsole output.
# Instead, verify diagnostics via: (1) log file, (2) IPC pause/resume, (3) process health.

# Check log file for diagnostics evidence
$logPath = "$env:LOCALAPPDATA\DeepRKey\DeepRKey.log"
$logContent = if (Test-Path $logPath) { Get-Content $logPath -Raw } else { "" }

Record "CLI" "Bootstrap initialized (log)" "Bootstrap" $(if($logContent -match "DeepRKey starting"){"found"}else{"not in log"}) ($logContent -match "DeepRKey starting")
Record "CLI" "Coordinator started (log)" "started" $(if($logContent -match "Coordinator started"){"found"}else{"not in log"}) ($logContent -match "Coordinator started")
Record "CLI" "IPC window created (log)" "IPC" $(if($logContent -match "IPC hidden window created"){"found"}else{"not in log"}) ($logContent -match "IPC hidden window created")
Record "CLI" "GUID assigned (log)" "GUID" $(if($logContent -match "GUID=[0-9A-F-]+"){$logContent | Select-String "GUID=([0-9A-F-]+)" | ForEach-Object { $_.Matches[0].Groups[1].Value.Substring(0,8) }}else{"N/A"}) ($logContent -match "GUID=[0-9A-F-]+")

# health-check via Start-Process (just check exit code)
$healthProc = Start-Process -FilePath $ExePath -ArgumentList "--health-check" -NoNewWindow -PassThru -Wait
Record "CLI" "--health-check exits cleanly" "exit 0" $(if($healthProc.ExitCode -eq 0){"OK"}else{"exit $($healthProc.ExitCode)"}) ($healthProc.ExitCode -eq 0)

# help via Start-Process
$helpProc = Start-Process -FilePath $ExePath -ArgumentList "--help" -NoNewWindow -PassThru -Wait
Record "CLI" "--help exits cleanly" "exit 0" $(if($helpProc.ExitCode -eq 0){"OK"}else{"exit $($helpProc.ExitCode)"}) ($helpProc.ExitCode -eq 0)

# ============================================================================
# PHASE 5: Pause / Resume via CLI
# ============================================================================
Write-Host "`n[Phase 5/8] Pause / Resume" -ForegroundColor Yellow

# Pause
$p = Start-Process -FilePath $ExePath -ArgumentList "--pause" -NoNewWindow -PassThru -Wait
Start-Sleep -Milliseconds 500
# Verify pause via log
$logAfterPause = if (Test-Path $logPath) { Get-Content $logPath -Raw } else { "" }
# We verify pause worked via the IPC mechanism itself — pause command exits 0
Record "IPC" "--pause command exits cleanly" "exit 0" $(if($p.ExitCode -eq 0){"OK"}else{"exit $($p.ExitCode)"}) ($p.ExitCode -eq 0)

# Resume
$p = Start-Process -FilePath $ExePath -ArgumentList "--resume" -NoNewWindow -PassThru -Wait
Start-Sleep -Milliseconds 500
Record "IPC" "--resume command exits cleanly" "exit 0" $(if($p.ExitCode -eq 0){"OK"}else{"exit $($p.ExitCode)"}) ($p.ExitCode -eq 0)

# Toggle off then on
$p1 = Start-Process -FilePath $ExePath -ArgumentList "--toggle" -NoNewWindow -PassThru -Wait
Start-Sleep -Milliseconds 300
$p2 = Start-Process -FilePath $ExePath -ArgumentList "--toggle" -NoNewWindow -PassThru -Wait
Start-Sleep -Milliseconds 300
Record "IPC" "--toggle works (off+on)" "roundtrip" $(if($p1.ExitCode -eq 0 -and $p2.ExitCode -eq 0){"done"}else{"error"}) ($p1.ExitCode -eq 0 -and $p2.ExitCode -eq 0)

# ============================================================================
# PHASE 6: Window Detection — launch test apps, verify tracking
# ============================================================================
Write-Host "`n[Phase 6/8] Window Detection" -ForegroundColor Yellow

$launchedProcs = @()

function Launch-TestApp {
    param([string]$Name, [string]$Cmd)
    try {
        $p = Start-Process -FilePath $Cmd -PassThru -ErrorAction Stop
        Start-Sleep -Milliseconds 1500
        if (-not $p.HasExited) {
            $script:launchedProcs += $p
            return $p
        }
    } catch {
        return $null
    }
    return $null
}

# Launch Notepad (Win32)
$notepad = Launch-TestApp "Notepad" "notepad.exe"
if ($notepad) {
    Record "Compat" "Notepad (Win32) launches" "running" "PID $($notepad.Id)" $true
} else {
    Record "Compat" "Notepad (Win32) launches" "running" "not found" $false
}

# Launch Calculator (might be UWP on modern Windows)
$calc = Launch-TestApp "Calculator" "calc.exe"
if ($calc) {
    Start-Sleep -Milliseconds 1000
    if (-not $calc.HasExited) {
        Record "Compat" "Calculator launches" "running" "PID $($calc.Id)" $true
    } else {
        # calc.exe exits immediately on modern Windows (UWP redirector) — SKIP, not FAIL
        $script:skip++
        $script:results += [PSCustomObject]@{
            Category = "Compat"; Test = "Calculator launches"; Target = "running"
            Actual = "UWP redirect (exits immediately)"; Result = "SKIP"; Notes = "calc.exe is UWP on modern Windows"
        }
        Write-Host "  [SKIP] Calculator launches" -ForegroundColor Yellow
    }
} else {
    $script:skip++
    $script:results += [PSCustomObject]@{
        Category = "Compat"; Test = "Calculator launches"; Target = "running"
        Actual = "not found"; Result = "SKIP"; Notes = "calc.exe not available"
    }
    Write-Host "  [SKIP] Calculator launches" -ForegroundColor Yellow
}

# Check if DeepRKey sees windows (via log)
Start-Sleep -Seconds 1
$logAfterWindows = if (Test-Path $logPath) { Get-Content $logPath -Raw } else { "" }
if ($logAfterWindows -match "(\d+) windows tracked") {
    $windowCount = [int]$Matches[1]
    Record "Detect" "DeepRKey tracking windows (from log)" "> 0" "$windowCount windows" ($windowCount -gt 0)
} else {
    Record "Detect" "DeepRKey tracking windows (from log)" "> 0" "parse failed" $false
}

if ($logAfterWindows -match "(\d+) threads") {
    $threadCount = [int]$Matches[1]
    Record "Detect" "DeepRKey tracking threads (from log)" "> 0" "$threadCount threads" ($threadCount -gt 0)
} else {
    Record "Detect" "DeepRKey tracking threads (from log)" "> 0" "parse failed" $false
}

# Try launching VS Code (Electron)
$code = Launch-TestApp "VS Code" "code.exe"
if ($code) {
    Record "Compat" "VS Code (Electron) launches" "running" "PID $($code.Id)" $true
} else {
    $script:skip++
    $script:results += [PSCustomObject]@{
        Category = "Compat"; Test = "VS Code (Electron) launches"; Target = "running"
        Actual = "not installed"; Result = "SKIP"; Notes = "VS Code not found on this system"
    }
    Write-Host "  [SKIP] VS Code (Electron) launches" -ForegroundColor Yellow
}

# ============================================================================
# PHASE 7: Performance Snapshot
# ============================================================================
Write-Host "`n[Phase 7/8] Performance Snapshot" -ForegroundColor Yellow

$drkProc = Get-Process -Name DeepRKey -ErrorAction SilentlyContinue
if ($drkProc) {
    $memMB = [math]::Round($drkProc.WorkingSet64 / 1MB, 1)
    $cpuSec = $drkProc.CPU
    Record "Perf" "Memory usage < 100MB" "< 100MB" "${memMB}MB" ($memMB -lt 100)
    Record "Perf" "Process has CPU time" "> 0" "${cpuSec}s" ($cpuSec -gt 0)

    # Sample CPU over 3 seconds
    $cpuBefore = $drkProc.TotalProcessorTime.TotalMilliseconds
    Start-Sleep -Seconds 3
    $drkProc.Refresh()
    $cpuAfter = $drkProc.TotalProcessorTime.TotalMilliseconds
    $cpuPct = [math]::Round(($cpuAfter - $cpuBefore) / 3000 * 100 / [Environment]::ProcessorCount, 2)
    Record "Perf" "Idle CPU < 5% (3s sample)" "< 5%" "${cpuPct}%" ($cpuPct -lt 5)
} else {
    Record "Perf" "DeepRKey process exists" "running" "not found" $false
}

# ============================================================================
# PHASE 8: Dark Mode / Theme
# ============================================================================
Write-Host "`n[Phase 8/8] Dark Mode / Theme" -ForegroundColor Yellow

# Check registry
$regPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"
if (Test-Path $regPath) {
    $lightTheme = (Get-ItemProperty -Path $regPath -Name AppsUseLightTheme -ErrorAction SilentlyContinue).AppsUseLightTheme
    if ($null -ne $lightTheme) {
        $isDark = ($lightTheme -eq 0)
        Record "Theme" "Windows theme detectable" "0 or 1" "$lightTheme ($([string]$(if($isDark){'Dark'}else{'Light'})))" $true
    } else {
        Record "Theme" "Windows theme registry key exists" "AppsUseLightTheme" "missing" $false
    }
} else {
    Record "Theme" "Personalize registry path exists" "exists" "missing" $false
}

# Check VCL styles available
$styleCount = 0
$vsfDir = $null
# Try multiple possible paths
$candidatePaths = @(
    "C:\Program Files (x86)\Embarcadero\Studio\37.0\Redist\styles\vcl",
    "D:\Program Files (x86)\Embarcadero\Studio\37.0\Redist\styles\vcl",
    "C:\Program Files (x86)\Embarcadero\Studio\37.0\Redist\win64\styles\vcl"
)
foreach ($cp in $candidatePaths) {
    if (Test-Path $cp) { $vsfDir = $cp; break }
}

if ($vsfDir) {
    $styleCount = (Get-ChildItem $vsfDir -Filter "*.vsf" -ErrorAction SilentlyContinue).Count
}
Record "Theme" "VCL styles available (dark candidates)" "> 0" "$styleCount .vsf files" ($styleCount -gt 0)

# Check for dark style names specifically
$darkStyles = @("Carbon", "Obsidian", "CharcoalDarkSlate", "OnyxBlue")
$found = $false
if ($vsfDir) {
    foreach ($ds in $darkStyles) {
        if (Test-Path (Join-Path $vsfDir "$ds.vsf")) {
            $found = $true
            break
        }
    }
}
Record "Theme" "At least one dark VCL style available" "1+" $(if($found){"found"}else{"none"}) $found

# Check log file for theme entry
$logDir = "$env:LOCALAPPDATA\DeepRKey"
if (Test-Path $logDir) {
    $latestLog = Get-ChildItem $logDir -Filter "*.log" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latestLog) {
        $logContent = Get-Content $latestLog.FullName -Raw -ErrorAction SilentlyContinue
        $hasThemeEntry = $logContent -match "Theme"
        Record "Theme" "Log contains Theme entry" "Theme" $(if($hasThemeEntry){"found"}else{"not in log"}) $hasThemeEntry
        $hasBootstrap = $logContent -match "Bootstrap"
        Record "Theme" "Log contains Bootstrap entry" "Bootstrap" $(if($hasBootstrap){"found"}else{"not in log"}) $hasBootstrap
        # Check log freshness
        $logAge = (Get-Date) - $latestLog.LastWriteTime
        Record "Theme" "Log file written recently" "< 60s" "$([math]::Round($logAge.TotalSeconds,1))s ago" ($logAge.TotalSeconds -lt 60)
    } else {
        Record "Theme" "Log file exists" "exists" "no log files" $false
    }
} else {
    Record "Theme" "Log directory exists" "exists" "missing ($logDir)" $false
}

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
Write-Host "`nCleaning up..." -ForegroundColor Yellow
foreach ($p in $script:launchedProcs) {
    try {
        if ($p -and -not $p.HasExited) {
            $p.CloseMainWindow() | Out-Null
            Start-Sleep -Milliseconds 500
            if (-not $p.HasExited) { $p.Kill() }
        }
    } catch {}
}
Get-Process -Name DeepRKey -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# ============================================================================
# Summary
# ============================================================================
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host " AUTOMATED TEST RESULTS" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  PASS:  $($script:pass)" -ForegroundColor Green
Write-Host "  FAIL:  $($script:fail)" -ForegroundColor Red
Write-Host "  SKIP:  $($script:skip)" -ForegroundColor Yellow
$total = $script:pass + $script:fail + $script:skip
$passRate = if ($total -gt 0) { [math]::Round($script:pass / ($total - $script:skip) * 100, 1) } else { 0 }
Write-Host "  Total: $total  (pass rate: ${passRate}% excl. skips)" -ForegroundColor White

# Save report
$reportLines = @()
$reportLines += "DeepRKey Automated Test Report"
$reportLines += "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$reportLines += "Executable: $ExePath"
$reportLines += ""
$reportLines += "Results: $($script:pass) PASS / $($script:fail) FAIL / $($script:skip) SKIP / $total Total (${passRate}% pass rate excl. skips)"
$reportLines += ""
$reportLines += "{0,-12} {1,-45} {2,-20} {3,-20} {4}" -f "Category","Test","Target","Actual","Result"
$reportLines += ("-" * 110)
foreach ($r in $script:results) {
    $reportLines += "{0,-12} {1,-45} {2,-20} {3,-20} {4}" -f $r.Category, $r.Test, $r.Target, $r.Actual, $r.Result
}

# Note about manual tests
$reportLines += ""
$reportLines += "--- Manual Tests Remaining ---"
$reportLines += "The following require human interaction and are covered by:"
$reportLines += "  tests/manual/edge_case_test.ps1         — sleep/lock/DPI/RDP"
$reportLines += "  tests/manual/compatibility_matrix_test.ps1 — right-click titlebar verification"
$reportLines += "  tests/manual/accessibility_test.ps1     — keyboard/high contrast"

$reportText = $reportLines -join "`r`n"
$reportText | Out-File -FilePath $ReportPath -Encoding UTF8
Write-Host "`nReport saved: $ReportPath" -ForegroundColor Gray
