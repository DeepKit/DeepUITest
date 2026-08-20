# DeepRKey Manual Test Launcher
# Runs all 3 interactive test scripts in sequence.
#
# Prerequisites:
#   - DeepRKey.exe must be running (start it manually before running this script)
#   - Each test requires human interaction (keyboard input for PASS/FAIL/SKIP)
#
# Usage: .\run_manual_tests.ps1

param(
    [switch]$SkipPrereq
)

$ErrorActionPreference = "Continue"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host " DeepRKey Manual Test Suite" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host

# ---------------------------------------------------------------------------
# Prerequisites check
# ---------------------------------------------------------------------------
if (-not $SkipPrereq) {
    Write-Host "[Prerequisites]" -ForegroundColor Yellow

    # Check DeepRKey is running
    $drkProc = Get-Process -Name DeepRKey -ErrorAction SilentlyContinue
    if ($drkProc) {
        Write-Host "  [OK] DeepRKey is running (PID $($drkProc.Id))" -ForegroundColor Green
    } else {
        Write-Host "  [!!] DeepRKey is NOT running!" -ForegroundColor Red
        Write-Host "       Start DeepRKey.exe first, then re-run this script." -ForegroundColor DarkGray
        Write-Host "       Or use -SkipPrereq to bypass this check." -ForegroundColor DarkGray
        return
    }

    # Check Notepad is available (needed for most tests)
    $notepadPath = Join-Path $env:SystemRoot "notepad.exe"
    if (Test-Path $notepadPath) {
        Write-Host "  [OK] Notepad available" -ForegroundColor Green
    } else {
        Write-Host "  [!!] Notepad not found at $notepadPath" -ForegroundColor Yellow
    }

    # Check log directory
    $logPath = "$env:LOCALAPPDATA\DeepRKey\DeepRKey.log"
    if (Test-Path $logPath) {
        Write-Host "  [OK] Log file accessible: $logPath" -ForegroundColor Green
    } else {
        Write-Host "  [!!] Log file not found (will be created on next DeepRKey start)" -ForegroundColor Yellow
    }

    Write-Host
}

# ---------------------------------------------------------------------------
# Test scripts
# ---------------------------------------------------------------------------
$scripts = @(
    @{ Name = "Edge Cases (T-011)";       File = "edge_case_test.ps1";              Desc = "Sleep/lock/DPI/RDP scenarios" },
    @{ Name = "Compatibility (T-012)";    File = "compatibility_matrix_test.ps1";   Desc = "Win32/VCL/WPF/Electron/UWP apps" },
    @{ Name = "Accessibility (T-013)";    File = "accessibility_test.ps1";          Desc = "Keyboard/high contrast/touch" }
)

$testDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$totalPass = 0
$totalFail = 0
$totalSkip = 0

for ($i = 0; $i -lt $scripts.Count; $i++) {
    $s = $scripts[$i]
    $scriptPath = Join-Path $testDir $s.File

    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host " [$($i+1)/$($scripts.Count)] $($s.Name)" -ForegroundColor Cyan
    Write-Host " $($s.Desc)" -ForegroundColor DarkGray
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host

    if (-not (Test-Path $scriptPath)) {
        Write-Host "  [SKIP] Script not found: $scriptPath" -ForegroundColor Yellow
        continue
    }

    & $scriptPath

    Write-Host
    if ($i -lt $scripts.Count - 1) {
        Write-Host "Press any key to continue to next test..." -ForegroundColor DarkGray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        Write-Host
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " All Manual Tests Complete" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host
Write-Host "Check the generated report files in this directory:" -ForegroundColor DarkGray
Get-ChildItem $testDir -Filter "*_report_*.txt" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 6 |
    ForEach-Object {
        Write-Host "  $($_.Name)  ($([math]::Round((Get-Date).Subtract($_.LastWriteTime).TotalMinutes))min ago)" -ForegroundColor Gray
    }
