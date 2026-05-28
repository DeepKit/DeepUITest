# G4 compile script
# Compiles each modified .dpr; logs ExitCode + last 80 lines of output to _result/<n>.log
# Output is captured to .\_result\

$ErrorActionPreference = 'Continue'
$DCC = 'D:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe'
$DB  = 'd:\_Progs\02Business\DeepBase'
$ROOT = 'd:\_Progs\02Business'
$OUT  = 'd:\_Progs\02Business\.kiro\specs\aierrorhandler-rollout\exec-log\_g4_compile'
$RESULT = Join-Path $OUT '_result'
New-Item -ItemType Directory -Path $RESULT -Force | Out-Null

# Third-party libs
$BDS_CAT = 'D:\Personal\Documents\Embarcadero\Studio\37.0\CatalogRepository'
$VTV13   = Join-Path $BDS_CAT 'VirtualTreeView-13\2025.03\Source'
$MSHELL  = Join-Path $BDS_CAT 'MustangpeakVirtualShell-13\2025.03\Source'
$MCOMMON = Join-Path $BDS_CAT 'MustangpeakCommonLibrary-13\2025.03\Source'
$SKIA    = 'D:\ProgramData\delphi\Skia4Delphi'
$SYNEDIT = 'D:\ProgramData\delphi\SynEdit-master\Source'
$SYNHL   = 'D:\ProgramData\delphi\SynEdit-master\Source\Highlighters'
$VTV_M   = 'D:\ProgramData\delphi\VirtualTreeView-master\Source'

$CommonNS = 'System;Vcl;Winapi;System.Win;Data;Xml;Soap;Web;FireDAC'
$CommonDB = "$DB\Core;$DB\VCL;$DB\Persistence;$DB\Features;$DB\Governance"

function Run-Compile {
  param(
    [string]$Tag,
    [string]$Dpr,
    [string]$U,
    [string]$NS = $CommonNS,
    [string]$I = '',
    [string]$D = ''
  )
  Write-Host ""
  Write-Host "=== $Tag ==="
  $log = Join-Path $RESULT "$Tag.log"
  $args = @(
    "-E$RESULT",
    "-U$U",
    "-NS$NS"
  )
  if ($I) { $args += "-I$I" }
  if ($D) { $args += "-D$D" }
  $args += $Dpr
  Write-Host "DCC64 args:"
  $args | ForEach-Object { Write-Host "  $_" }
  & $DCC @args 2>&1 | Tee-Object -FilePath $log
  $rc = $LASTEXITCODE
  Add-Content -Path $log -Value "EXIT_CODE=$rc"
  Write-Host "ExitCode=$rc"
  return $rc
}

$results = @{}

# 1. ClipVault.dpr (DeepLaunch/ClipDemo)
$results['ClipVault'] = Run-Compile -Tag 'ClipVault' `
  -Dpr "$ROOT\DeepLaunch\ClipDemo\ClipVault.dpr" `
  -U   "$CommonDB;$ROOT\DeepLaunch\ClipDemo\src\Core;$ROOT\DeepLaunch\ClipDemo\src\UI;$SKIA;$SYNEDIT;$SYNHL;$VTV_M" `
  -D   'SKIA'

# 2. DeepLaunch.dpr
$results['DeepLaunch'] = Run-Compile -Tag 'DeepLaunch' `
  -Dpr "$ROOT\DeepLaunch\DeepLaunch.dpr" `
  -U   "$CommonDB;$ROOT\DeepLaunch\src\Core;$ROOT\DeepLaunch\src\UI;$VTV13;$MSHELL;$MCOMMON;$SKIA"

# 3. DeepMoveC (Chinese filename)
$results['DeepMoveC'] = Run-Compile -Tag 'DeepMoveC' `
  -Dpr "$ROOT\DeepMoveC\C盘超级瘦身.dpr" `
  -U   "$CommonDB;$ROOT\DeepMoveC;$ROOT\DeepMoveC\AntiTamperPackage"

# 4. DeepRenew.dpr
$results['DeepRenew'] = Run-Compile -Tag 'DeepRenew' `
  -Dpr "$ROOT\DeepRenew\DeepRenew.dpr" `
  -U   "$CommonDB;$ROOT\DeepRenew"

# 5. DeepRenewAdmin.dpr
$results['DeepRenewAdmin'] = Run-Compile -Tag 'DeepRenewAdmin' `
  -Dpr "$ROOT\DeepRenew\DeepRenewAdmin.dpr" `
  -U   "$CommonDB;$ROOT\DeepRenew"

Write-Host ""
Write-Host "===== SUMMARY ====="
$results.Keys | Sort-Object | ForEach-Object {
  $rc = $results[$_]
  $status = if ($rc -eq 0) { 'OK' } else { "FAIL($rc)" }
  Write-Host ("{0,-20} {1}" -f $_, $status)
}
