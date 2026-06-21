# DeepRKey Compatibility Matrix Test (T-012)
# Tests menu injection across Win32/VCL/WPF/Electron/UWP app types
#
# Usage: .\compatibility_matrix_test.ps1 [-ExePath .\bin\DeepRKey.exe]
# Requires: DeepRKey running, human tester to verify menus

param(
    [string]$ExePath = ".\bin\DeepRKey.exe",
    [string]$ReportPath = ".\tests\manual\compatibility_report_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
)

$ErrorActionPreference = "Continue"

Write-Host "=== DeepRKey Compatibility Matrix Test (T-012) ===" -ForegroundColor Cyan
Write-Host "Start: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
$launched = @()

function Start-TestApp {
    param([string]$Name, [string]$Command)
    Write-Host "  Starting $Name ..." -NoNewline
    try {
        $proc = Start-Process -FilePath $Command -PassThru -ErrorAction Stop
        Start-Sleep -Milliseconds 1500
        if (-not $proc.HasExited) {
            $script:launched += [PSCustomObject]@{ Name = $Name; Proc = $proc }
            Write-Host " OK (PID $($proc.Id))" -ForegroundColor Green
            return $proc
        } else {
            Write-Host " exited immediately" -ForegroundColor Yellow
            return $null
        }
    } catch {
        Write-Host " not found ($($_.Exception.Message))" -ForegroundColor Yellow
        return $null
    }
}

function Stop-AllTestApps {
    foreach ($entry in $script:launched) {
        try {
            if ($entry.Proc -and -not $entry.Proc.HasExited) {
                $entry.Proc.CloseMainWindow() | Out-Null
                Start-Sleep -Milliseconds 500
                if (-not $entry.Proc.HasExited) { $entry.Proc.Kill() }
            }
        } catch {}
    }
    $script:launched = @()
}

function Ask-Test {
    param([string]$Prompt)
    Write-Host
    Write-Host "  $Prompt" -ForegroundColor White
    Write-Host "  [1] PASS   [2] FAIL   [3] SKIP" -ForegroundColor DarkGray
    do {
        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        switch ($key.Character) {
            '1' { Write-Host "  -> PASS" -ForegroundColor Green; return "PASS" }
            '2' { Write-Host "  -> FAIL" -ForegroundColor Red; return "FAIL" }
            '3' { Write-Host "  -> SKIP" -ForegroundColor Yellow; return "SKIP" }
        }
    } while ($true)
}

# ---------------------------------------------------------------------------
# Check DeepRKey is running
# ---------------------------------------------------------------------------
$drk = Get-Process -Name "DeepRKey" -ErrorAction SilentlyContinue
if (-not $drk) {
    Write-Host "Starting DeepRKey..." -ForegroundColor Yellow
    Start-Process -FilePath $ExePath
    Start-Sleep -Seconds 3
}

# ---------------------------------------------------------------------------
# Results collection
# ---------------------------------------------------------------------------
$testResults = @()

function Record-Result {
    param([string]$AppType, [string]$AppName, [string]$Test, [string]$Result, [string]$Notes = "")
    $script:testResults += [PSCustomObject]@{
        AppType = $AppType
        AppName = $AppName
        Test    = $Test
        Result  = $Result
        Notes   = $Notes
    }
}

# ============================================================================
# Section 1: Win32 Native Apps
# ============================================================================
Write-Host "`n[1/5] Win32 Native Apps" -ForegroundColor Yellow

$notepad = Start-TestApp -Name "Notepad (Win32)" -Command "notepad.exe"
if ($notepad) {
    $r = Ask-Test "Right-click Notepad title bar -> does DeepRKey menu appear?"
    Record-Result -AppType "Win32" -AppName "Notepad" -Test "Menu injection" -Result $r

    if ($r -eq "PASS") {
        $r2 = Ask-Test "Click 'Always On Top' -> does window stay on top?"
        Record-Result -AppType "Win32" -AppName "Notepad" -Test "Always On Top" -Result $r2

        $r3 = Ask-Test "Click 'Transparency' -> does slider appear and work?"
        Record-Result -AppType "Win32" -AppName "Notepad" -Test "Transparency" -Result $r3
    }
}

$calc = Start-TestApp -Name "Calculator" -Command "calc.exe"
if ($calc) {
    $r = Ask-Test "Right-click Calculator title bar -> does DeepRKey menu appear?"
    Record-Result -AppType "Win32/UWP" -AppName "Calculator" -Test "Menu injection" -Result $r
}

# ============================================================================
# Section 2: VCL Apps
# ============================================================================
Write-Host "`n[2/5] VCL Apps" -ForegroundColor Yellow

$r = Ask-Test "Open DeepRKey Settings (double-click tray icon) -> right-click Settings title bar -> does DeepRKey menu appear? (Self-hook test)"
Record-Result -AppType "VCL" -AppName "DeepRKey Settings" -Test "Menu injection (self)" -Result $r

# ============================================================================
# Section 3: WPF Apps
# ============================================================================
Write-Host "`n[3/5] WPF Apps" -ForegroundColor Yellow

# Try common WPF apps
$wpfApps = @(
    @{ Name = "Visual Studio"; Cmd = "devenv.exe" },
    @{ Name = "PowerShell ISE"; Cmd = "powershell_ise.exe" },
    @{ Name = "WPF Test (msedge)"; Cmd = "msedge.exe" }
)

$wpfFound = $false
foreach ($app in $wpfApps) {
    $proc = Start-TestApp -Name $app.Name -Command $app.Cmd
    if ($proc) {
        $r = Ask-Test "Right-click $($app.Name) title bar -> does DeepRKey menu appear?"
        Record-Result -AppType "WPF" -AppName $app.Name -Test "Menu injection" -Result $r
        $wpfFound = $true
        break  # one WPF app is enough
    }
}
if (-not $wpfFound) {
    Write-Host "  No WPF apps found to test (skipped)" -ForegroundColor Yellow
    Record-Result -AppType "WPF" -AppName "(none)" -Test "Menu injection" -Result "SKIP" -Notes "No WPF app available"
}

# ============================================================================
# Section 4: Electron / Chromium Apps
# ============================================================================
Write-Host "`n[4/5] Electron / Chromium Apps" -ForegroundColor Yellow

$electronApps = @(
    @{ Name = "VS Code"; Cmd = "code.exe" },
    @{ Name = "Slack"; Cmd = "slack.exe" },
    @{ Name = "Microsoft Teams"; Cmd = "ms-teams.exe" }
)

$electronFound = $false
foreach ($app in $electronApps) {
    $proc = Start-TestApp -Name $app.Name -Command $app.Cmd
    if ($proc) {
        $r = Ask-Test "Right-click $($app.Name) title bar -> does DeepRKey menu appear?"
        Record-Result -AppType "Electron" -AppName $app.Name -Test "Menu injection" -Result $r
        $electronFound = $true
        break  # one Electron app is enough
    }
}
if (-not $electronFound) {
    Write-Host "  No Electron apps found to test (skipped)" -ForegroundColor Yellow
    Record-Result -AppType "Electron" -AppName "(none)" -Test "Menu injection" -Result "SKIP" -Notes "No Electron app available"
}

# ============================================================================
# Section 5: UWP / Modern Apps
# ============================================================================
Write-Host "`n[5/5] UWP / Modern Apps" -ForegroundColor Yellow

$uwpApps = @(
    @{ Name = "Windows Settings"; Cmd = "ms-settings:" },
    @{ Name = "File Explorer"; Cmd = "explorer.exe" }
)

foreach ($app in $uwpApps) {
    if ($app.Cmd -eq "ms-settings:") {
        Write-Host "  Starting $($app.Name) ..." -NoNewline
        try {
            Start-Process "ms-settings:"
            Start-Sleep -Seconds 2
            Write-Host " OK" -ForegroundColor Green
            $r = Ask-Test "Right-click Windows Settings title bar -> does DeepRKey menu appear?"
            Record-Result -AppType "UWP" -AppName $app.Name -Test "Menu injection" -Result $r
        } catch {
            Write-Host " failed" -ForegroundColor Yellow
            Record-Result -AppType "UWP" -AppName $app.Name -Test "Menu injection" -Result "SKIP"
        }
    } else {
        $proc = Start-TestApp -Name $app.Name -Command $app.Cmd
        if ($proc) {
            $r = Ask-Test "Right-click $($app.Name) title bar -> does DeepRKey menu appear?"
            Record-Result -AppType "UWP/Shell" -AppName $app.Name -Test "Menu injection" -Result $r
        }
    }
}

# ============================================================================
# Cleanup & Report
# ============================================================================
Write-Host "`nCleaning up test apps..." -ForegroundColor Yellow
Stop-AllTestApps

# Summary
$pass = ($testResults | Where-Object { $_.Result -eq "PASS" }).Count
$fail = ($testResults | Where-Object { $_.Result -eq "FAIL" }).Count
$skip = ($testResults | Where-Object { $_.Result -eq "SKIP" }).Count
$total = $testResults.Count

Write-Host "`n=== Compatibility Matrix Summary ===" -ForegroundColor Cyan
Write-Host "  PASS:  $pass" -ForegroundColor Green
Write-Host "  FAIL:  $fail" -ForegroundColor Red
Write-Host "  SKIP:  $skip" -ForegroundColor Yellow
Write-Host "  Total: $total" -ForegroundColor White

# Save report
$reportLines = @()
$reportLines += "DeepRKey Compatibility Matrix Test Report"
$reportLines += "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$reportLines += ""
$reportLines += "Results: $pass PASS / $fail FAIL / $skip SKIP / $total Total"
$reportLines += ""
$reportLines += "{0,-15} {1,-20} {2,-25} {3,-8} {4}" -f "AppType","AppName","Test","Result","Notes"
$reportLines += ("-" * 90)
foreach ($r in $testResults) {
    $reportLines += "{0,-15} {1,-20} {2,-25} {3,-8} {4}" -f $r.AppType, $r.AppName, $r.Test, $r.Result, $r.Notes
}

$reportText = $reportLines -join "`r`n"
$reportText | Out-File -FilePath $ReportPath -Encoding UTF8
Write-Host "`nReport saved: $ReportPath" -ForegroundColor Gray
