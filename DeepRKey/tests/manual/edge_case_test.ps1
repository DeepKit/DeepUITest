# DeepRKey Edge Case Test (T-011)
# Tests sleep recovery, session lock/unlock, DPI change, RDP scenarios
#
# Usage: .\edge_case_test.ps1
# Requires: DeepRKey running, human tester to trigger events

param(
    [string]$ReportPath = ".\tests\manual\edge_case_report_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
)

Write-Host "=== DeepRKey Edge Case Test (T-011) ===" -ForegroundColor Cyan
Write-Host "Start: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host

$testResults = @()

function Record-Result {
    param([string]$Category, [string]$Test, [string]$Result, [string]$Notes = "")
    $script:testResults += [PSCustomObject]@{
        Category = $Category
        Test     = $Test
        Result   = $Result
        Notes    = $Notes
    }
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

function Wait-Action {
    param([string]$Instruction)
    Write-Host
    Write-Host "  ACTION REQUIRED:" -ForegroundColor DarkCyan
    Write-Host "    $Instruction" -ForegroundColor White
    Write-Host "    Press any key when done..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# ---------------------------------------------------------------------------
# Pre-check: verify DeepRKey log is accessible
# ---------------------------------------------------------------------------
$logDir = "$env:LOCALAPPDATA\DeepRKey\logs"
if (Test-Path $logDir) {
    $latestLog = Get-ChildItem $logDir -Filter "*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latestLog) {
        Write-Host "  Log file: $($latestLog.FullName)" -ForegroundColor Gray
        Write-Host "  (Check this file after each test for expected log entries)" -ForegroundColor DarkGray
    }
}

# ============================================================================
# Section 1: Session Lock / Unlock
# ============================================================================
Write-Host "`n[1/5] Session Lock / Unlock" -ForegroundColor Yellow

$r = Ask-Test "Before lock: open Notepad, right-click title bar -> verify DeepRKey menu works"
Record-Result -Category "Lock/Unlock" -Test "Pre-lock baseline" -Result $r

Wait-Action "Press Win+L to lock the workstation, wait 5 seconds, then unlock (enter password)"

$r = Ask-Test "After unlock: right-click Notepad title bar -> does DeepRKey menu still appear?"
Record-Result -Category "Lock/Unlock" -Test "Post-unlock menu works" -Result $r

$r = Ask-Test "After unlock: is the tray icon still visible and responsive?"
Record-Result -Category "Lock/Unlock" -Test "Tray icon survives lock" -Result $r

# ============================================================================
# Section 2: Sleep / Wake
# ============================================================================
Write-Host "`n[2/5] Sleep / Wake" -ForegroundColor Yellow

Wait-Action "Put the computer to sleep (Start -> Power -> Sleep, or close laptop lid). Wait 10 seconds, then wake it up"

$r = Ask-Test "After wake: right-click Notepad title bar -> does DeepRKey menu appear?"
Record-Result -Category "Sleep/Wake" -Test "Post-sleep menu works" -Result $r

$r = Ask-Test "After wake: is the titlebar button still visible on active windows?"
Record-Result -Category "Sleep/Wake" -Test "Titlebar button survives sleep" -Result $r

$r = Ask-Test "After wake: open a NEW window (e.g., new Notepad) -> does DeepRKey menu work on it?"
Record-Result -Category "Sleep/Wake" -Test "New windows work after sleep" -Result $r

Wait-Action "Check the log file for 'Power: system resumed from sleep' and 'ReenumerateAllWindows' entries"

# ============================================================================
# Section 3: Mixed DPI (multi-monitor)
# ============================================================================
Write-Host "`n[3/5] Mixed DPI (Multi-Monitor)" -ForegroundColor Yellow
Write-Host "  (Skip if you only have one monitor)" -ForegroundColor DarkGray

$r = Ask-Test "Do you have multiple monitors with different DPI settings?"
Record-Result -Category "Mixed DPI" -Test "Multi-monitor setup exists" -Result $r

if ($r -eq "PASS") {
    Wait-Action "Drag Notepad from the primary monitor to the secondary monitor (different DPI)"

    $r = Ask-Test "After dragging: right-click Notepad title bar on the new monitor -> does menu appear?"
    Record-Result -Category "Mixed DPI" -Test "Menu works after cross-monitor move" -Result $r

    $r = Ask-Test "After dragging: is the menu positioned correctly (not offset or clipped)?"
    Record-Result -Category "Mixed DPI" -Test "Menu positioning correct at new DPI" -Result $r

    $r = Ask-Test "After dragging: is the titlebar button still visible and at the correct position?"
    Record-Result -Category "Mixed DPI" -Test "Titlebar button correct at new DPI" -Result $r
} else {
    Record-Result -Category "Mixed DPI" -Test "Menu after cross-monitor move" -Result "SKIP" -Notes "Single monitor"
    Record-Result -Category "Mixed DPI" -Test "Menu positioning at new DPI" -Result "SKIP" -Notes "Single monitor"
    Record-Result -Category "Mixed DPI" -Test "Titlebar button at new DPI" -Result "SKIP" -Notes "Single monitor"
}

# ============================================================================
# Section 4: Fast User Switch
# ============================================================================
Write-Host "`n[4/5] Fast User Switch" -ForegroundColor Yellow

$r = Ask-Test "Do you have a second Windows user account to test with?"
Record-Result -Category "User Switch" -Test "Second account available" -Result $r

if ($r -eq "PASS") {
    Wait-Action "Press Win+L, then sign in with a different user account. Use the system for 30 seconds, then switch back"

    $r = Ask-Test "After switching back: right-click Notepad title bar -> does DeepRKey menu work?"
    Record-Result -Category "User Switch" -Test "Post-switch menu works" -Result $r
} else {
    Record-Result -Category "User Switch" -Test "Post-switch menu works" -Result "SKIP" -Notes "No second account"
}

# ============================================================================
# Section 5: RDP / Remote Desktop (optional)
# ============================================================================
Write-Host "`n[5/5] RDP / Remote Desktop (optional)" -ForegroundColor Yellow

$r = Ask-Test "Do you have an RDP server available to test remote connect/disconnect?"
Record-Result -Category "RDP" -Test "RDP environment available" -Result $r

if ($r -eq "PASS") {
    Wait-Action "Connect to a remote desktop session, wait 10 seconds, then disconnect"

    $r = Ask-Test "After RDP disconnect: does DeepRKey menu still work on local windows?"
    Record-Result -Category "RDP" -Test "Post-RDP-disconnect menu works" -Result $r
} else {
    Record-Result -Category "RDP" -Test "Post-RDP-disconnect menu works" -Result "SKIP" -Notes "No RDP available"
}

# ============================================================================
# Summary & Report
# ============================================================================
$pass = ($testResults | Where-Object { $_.Result -eq "PASS" }).Count
$fail = ($testResults | Where-Object { $_.Result -eq "FAIL" }).Count
$skip = ($testResults | Where-Object { $_.Result -eq "SKIP" }).Count
$total = $testResults.Count

Write-Host "`n=== Edge Case Test Summary ===" -ForegroundColor Cyan
Write-Host "  PASS:  $pass" -ForegroundColor Green
Write-Host "  FAIL:  $fail" -ForegroundColor Red
Write-Host "  SKIP:  $skip" -ForegroundColor Yellow
Write-Host "  Total: $total" -ForegroundColor White

# Save report
$reportLines = @()
$reportLines += "DeepRKey Edge Case Test Report (T-011)"
$reportLines += "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$reportLines += ""
$reportLines += "Results: $pass PASS / $fail FAIL / $skip SKIP / $total Total"
$reportLines += ""
$reportLines += "{0,-18} {1,-50} {2,-8} {3}" -f "Category","Test","Result","Notes"
$reportLines += ("-" * 90)
foreach ($r in $testResults) {
    $reportLines += "{0,-18} {1,-50} {2,-8} {3}" -f $r.Category, $r.Test, $r.Result, $r.Notes
}

$reportText = $reportLines -join "`r`n"
$reportText | Out-File -FilePath $ReportPath -Encoding UTF8
Write-Host "`nReport saved: $ReportPath" -ForegroundColor Gray
