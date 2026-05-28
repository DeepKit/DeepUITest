<#
.SYNOPSIS
  Static gate check: ensure .dpr files that call DeepBase Initialize also link the FireDAC adapter.

.DESCRIPTION
  Rules:
  1. If a .dpr calls Initialize/InitializeEx/InitializeOrRaise/InitializeWithDB,
     it must also include DeepBase.Persistence.Manager.FireDAC.
  2. If a .dpr explicitly references DeepBase.DB.DoQry in '..\DeepBase\Core\',
     flag it (should be Persistence).
  3. If a .dproj has DCC_UnitSearchPath with DeepBase\Core but not DeepBase\Persistence
     while the corresponding .dpr calls Initialize, flag it.
  4. If a .dpr has both source-mode DeepBase.Manager 'in ...' and package dependency
     DeepBasePersistence, flag for manual review.

  Returns exit code 0 on pass, 1 on failure.
#>

param(
    [string]$Root = 'D:\_Progs\02Business',
    [switch]$CI
)

$ErrorActionPreference = 'Stop'
$exitCode = 0
$violations = [System.Collections.Generic.List[string]]::new()

# --- Rule 1: Initialize without adapter ---
Write-Host '=== Rule 1: Initialize calls without FireDAC adapter ==='

$dprFiles = Get-ChildItem -Path $Root -Filter '*.dpr' -Recurse -File |
    Where-Object { $_.FullName -notmatch '\\DeepBase\\' }

foreach ($dpr in $dprFiles) {
    $content = Get-Content $dpr.FullName -Raw -Encoding UTF8
    if ($content -match '\.\bInitialize\b' -and
        $content -notmatch 'Application\.Initialize' -replace '(?m)^.*Application\.Initialize.*$', '' -match '\.\bInitialize\b' -or
        $content -match 'InitializeEx\b' -or
        $content -match 'InitializeOrRaise\b' -or
        $content -match 'InitializeWithDB\b') {

        $hasInit = $false
        if ($content -match '(?<!Application\.)\.\bInitialize\b') { $hasInit = $true }
        if ($content -match '\bInitializeEx\b') { $hasInit = $true }
        if ($content -match '\bInitializeOrRaise\b') { $hasInit = $true }
        if ($content -match '\bInitializeWithDB\b') { $hasInit = $true }

        if ($hasInit) {
            $hasAdapter = $content -match 'DeepBase\.Persistence\.Manager\.FireDAC'
            if (-not $hasAdapter) {
                $msg = "MISSING ADAPTER: $($dpr.FullName) calls Initialize but has no DeepBase.Persistence.Manager.FireDAC"
                $violations.Add($msg)
                Write-Host "  FAIL: $msg" -ForegroundColor Red
            }
        }
    }
}

# --- Rule 2: Old Core path for DoQry ---
Write-Host ''
Write-Host '=== Rule 2: DeepBase.DB.DoQry referenced from old Core path ==='

foreach ($dpr in $dprFiles) {
    $content = Get-Content $dpr.FullName -Raw -Encoding UTF8
    if ($content -match "DeepBase\.DB\.DoQry\s+in\s+'[^']*\\DeepBase\\Core\\") {
        $msg = "OLD PATH: $($dpr.FullName) references DeepBase.DB.DoQry from Core (should be Persistence)"
        $violations.Add($msg)
        Write-Host "  FAIL: $msg" -ForegroundColor Red
    }
}

# --- Rule 3: dproj missing Persistence search path ---
Write-Host ''
Write-Host '=== Rule 3: .dproj missing Persistence search path ==='

$dprojFiles = Get-ChildItem -Path $Root -Filter '*.dproj' -Recurse -File |
    Where-Object { $_.FullName -notmatch '\\DeepBase\\' }

foreach ($dproj in $dprojFiles) {
    $dprojContent = Get-Content $dproj.FullName -Raw -Encoding UTF8

    # Find corresponding .dpr
    $dprName = $null
    if ($dprojContent -match '<MainSource>([^<]+)</MainSource>') {
        $dprName = $Matches[1]
    }
    if (-not $dprName) { continue }

    $dprPath = Join-Path $dproj.DirectoryName $dprName
    if (-not (Test-Path $dprPath)) { continue }

    $dprContent = Get-Content $dprPath -Raw -Encoding UTF8

    # Only check if .dpr calls Initialize
    $hasInit = $false
    if ($dprContent -match '(?<!Application\.)\.\bInitialize\b') { $hasInit = $true }
    if ($dprContent -match '\bInitializeEx\b') { $hasInit = $true }
    if ($dprContent -match '\bInitializeOrRaise\b') { $hasInit = $true }
    if ($dprContent -match '\bInitializeWithDB\b') { $hasInit = $true }

    if (-not $hasInit) { continue }

    $hasCorePath = $dprojContent -match 'DeepBase\\Core' -or $dprojContent -match 'DeepBase/Core'
    $hasPersistencePath = $dprojContent -match 'DeepBase\\Persistence' -or $dprojContent -match 'DeepBase/Persistence'

    if ($hasCorePath -and -not $hasPersistencePath) {
        $msg = "MISSING PATH: $($dproj.FullName) has DeepBase\Core search path but not DeepBase\Persistence"
        $violations.Add($msg)
        Write-Host "  FAIL: $msg" -ForegroundColor Red
    }
}

# --- Rule 4: Source-mode + package mix ---
Write-Host ''
Write-Host '=== Rule 4: Source-mode Manager + package dependency mix ==='

foreach ($dpr in $dprFiles) {
    $dprContent = Get-Content $dpr.FullName -Raw -Encoding UTF8

    $hasSourceManager = $dprContent -match "DeepBase\.Manager\s+in\s+'"
    if (-not $hasSourceManager) { continue }

    # Check corresponding .dproj for package dependency
    $dprojPath = $dpr.FullName -replace '\.dpr$', '.dproj'
    if (-not (Test-Path $dprojPath)) { continue }

    $dprojContent = Get-Content $dprojPath -Raw -Encoding UTF8
    if ($dprojContent -match 'DeepBasePersistence' -or $dprojContent -match 'DeepBaseCore') {
        $msg = "MIX WARNING: $($dpr.FullName) uses source-mode DeepBase.Manager but .dproj has package dependency - manual review needed"
        $violations.Add($msg)
        Write-Host "  WARN: $msg" -ForegroundColor Yellow
    }
}

# --- Summary ---
Write-Host ''
Write-Host '===' -NoNewline
if ($violations.Count -eq 0) {
    Write-Host ' ALL CHECKS PASSED ' -ForegroundColor Green -NoNewLine
} else {
    Write-Host " $($violations.Count) VIOLATION(S) FOUND " -ForegroundColor Red -NoNewLine
    $exitCode = 1
}
Write-Host '==='

exit $exitCode
