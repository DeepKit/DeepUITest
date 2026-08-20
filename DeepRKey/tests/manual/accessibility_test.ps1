# DeepRKey Accessibility Test (T-013)
# Tests keyboard navigation, high contrast mode, touch targets
#
# Usage: .\accessibility_test.ps1

param(
    [string]$ReportPath = ".\tests\manual\accessibility_report_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
)

Write-Host "=== DeepRKey Accessibility Test (T-013) ===" -ForegroundColor Cyan
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

# ============================================================================
# Section 1: Keyboard Navigation
# ============================================================================
Write-Host "[1/4] Keyboard Navigation" -ForegroundColor Yellow

Write-Host
Write-Host "  Please open DeepRKey Settings (double-click tray icon)" -ForegroundColor DarkCyan

$r = Ask-Test "Can you open Settings by double-clicking the tray icon?"
Record-Result -Category "Keyboard" -Test "Open Settings" -Result $r

$r = Ask-Test "Press Tab -> does focus cycle through all controls on Status tab?"
Record-Result -Category "Keyboard" -Test "Tab navigation (Status)" -Result $r

$r = Ask-Test "Press Ctrl+Tab -> does it switch between tabs (Status/General/Menu/Advanced)?"
Record-Result -Category "Keyboard" -Test "Tab switching (Ctrl+Tab)" -Result $r

$r = Ask-Test "On General tab: Tab through all checkboxes + theme combo -> all reachable?"
Record-Result -Category "Keyboard" -Test "Tab navigation (General)" -Result $r

$r = Ask-Test "On Menu Items tab: Tab through all checkboxes -> all reachable?"
Record-Result -Category "Keyboard" -Test "Tab navigation (Menu Items)" -Result $r

$r = Ask-Test "On Advanced tab: Tab through snap strategy + resize presets edit -> all reachable?"
Record-Result -Category "Keyboard" -Test "Tab navigation (Advanced)" -Result $r

$r = Ask-Test "Press Enter on OK button -> does Settings close and save?"
Record-Result -Category "Keyboard" -Test "Enter activates OK" -Result $r

$r = Ask-Test "Reopen Settings, change a value, press Escape -> does Settings close without saving?"
Record-Result -Category "Keyboard" -Test "Escape cancels" -Result $r

# ============================================================================
# Section 2: Tray Icon Keyboard Access
# ============================================================================
Write-Host "`n[2/4] Tray Icon Keyboard Access" -ForegroundColor Yellow

$r = Ask-Test "Press Win+B to focus system tray -> arrow to DeepRKey icon -> press Enter -> does tray menu open?"
Record-Result -Category "Keyboard" -Test "Win+B -> tray -> Enter" -Result $r

$r = Ask-Test "With tray menu open: arrow down to each item -> does each get highlighted?"
Record-Result -Category "Keyboard" -Test "Arrow navigation in tray menu" -Result $r

$r = Ask-Test "Press Escape -> does tray menu close?"
Record-Result -Category "Keyboard" -Test "Escape closes tray menu" -Result $r

# ============================================================================
# Section 3: High Contrast Mode
# ============================================================================
Write-Host "`n[3/4] High Contrast Mode" -ForegroundColor Yellow
Write-Host "  NOTE: Please enable Windows High Contrast mode now:" -ForegroundColor DarkCyan
Write-Host "    Settings -> Accessibility -> Contrast themes -> Select a theme" -ForegroundColor DarkCyan
Write-Host "    (Or press Left Alt + Left Shift + Print Screen)" -ForegroundColor DarkCyan
Write-Host

$r = Ask-Test "Enable High Contrast -> open DeepRKey Settings -> is all text readable?"
Record-Result -Category "High Contrast" -Test "Settings text readable" -Result $r

$r = Ask-Test "High Contrast -> right-click a window title bar -> is DeepRKey menu readable?"
Record-Result -Category "High Contrast" -Test "Menu text readable" -Result $r

$r = Ask-Test "High Contrast -> are checkboxes/radio buttons visually distinct?"
Record-Result -Category "High Contrast" -Test "Controls visually distinct" -Result $r

$r = Ask-Test "High Contrast -> is the titlebar button visible against both light and dark title bars?"
Record-Result -Category "High Contrast" -Test "Titlebar button visible" -Result $r

Write-Host
Write-Host "  You can disable High Contrast now (Left Alt + Left Shift + Print Screen)" -ForegroundColor DarkCyan

# ============================================================================
# Section 4: Touch Targets & Visual Size
# ============================================================================
Write-Host "`n[4/4] Touch Targets & Visual Size" -ForegroundColor Yellow

$r = Ask-Test "Titlebar button: is it at least 18x18 pixels (visible on screen)?"
Record-Result -Category "Touch Target" -Test "Titlebar button size >= 18x18" -Result $r -Notes "BTN_SIZE = 18 in code"

$r = Ask-Test "Settings OK/Cancel/Apply buttons: are they at least 75x25 pixels?"
Record-Result -Category "Touch Target" -Test "Settings buttons >= 75x25" -Result $r -Notes "Buttons are 75x25 in DFM"

$r = Ask-Test "Checkboxes in Settings: are they spaced at least 24px apart vertically?"
Record-Result -Category "Touch Target" -Test "Checkbox spacing >= 24px" -Result $r -Notes "Checkboxes are at 24px intervals in DFM"

$r = Ask-Test "Transparency dialog: is the trackbar thumb easy to grab (>= 20px)?"
Record-Result -Category "Touch Target" -Test "Trackbar thumb size" -Result $r

# ============================================================================
# Summary & Report
# ============================================================================
$pass = ($testResults | Where-Object { $_.Result -eq "PASS" }).Count
$fail = ($testResults | Where-Object { $_.Result -eq "FAIL" }).Count
$skip = ($testResults | Where-Object { $_.Result -eq "SKIP" }).Count
$total = $testResults.Count

Write-Host "`n=== Accessibility Test Summary ===" -ForegroundColor Cyan
Write-Host "  PASS:  $pass" -ForegroundColor Green
Write-Host "  FAIL:  $fail" -ForegroundColor Red
Write-Host "  SKIP:  $skip" -ForegroundColor Yellow
Write-Host "  Total: $total" -ForegroundColor White

# Save report
$reportLines = @()
$reportLines += "DeepRKey Accessibility Test Report (T-013)"
$reportLines += "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$reportLines += ""
$reportLines += "Results: $pass PASS / $fail FAIL / $skip SKIP / $total Total"
$reportLines += ""
$reportLines += "{0,-20} {1,-45} {2,-8} {3}" -f "Category","Test","Result","Notes"
$reportLines += ("-" * 90)
foreach ($r in $testResults) {
    $reportLines += "{0,-20} {1,-45} {2,-8} {3}" -f $r.Category, $r.Test, $r.Result, $r.Notes
}

$reportText = $reportLines -join "`r`n"
$reportText | Out-File -FilePath $ReportPath -Encoding UTF8
Write-Host "`nReport saved: $ReportPath" -ForegroundColor Gray
