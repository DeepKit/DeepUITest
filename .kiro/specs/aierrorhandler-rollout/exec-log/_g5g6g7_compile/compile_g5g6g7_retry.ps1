# G5/G6/G7 retry: only the 5 failing files with extended -U paths

$ErrorActionPreference = 'Continue'
$DCC = 'D:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe'
$DB  = 'd:\_Progs\02Business\DeepBase'
$ROOT = 'd:\_Progs\02Business'
$OUT  = 'd:\_Progs\02Business\.kiro\specs\aierrorhandler-rollout\exec-log\_g5g6g7_compile'
$RESULT = Join-Path $OUT '_result'
New-Item -ItemType Directory -Path $RESULT -Force | Out-Null

$BDS_CAT = 'D:\Personal\Documents\Embarcadero\Studio\37.0\CatalogRepository'
$VTV13   = Join-Path $BDS_CAT 'VirtualTreeView-13\2025.03\Source'
$VTV_M   = 'D:\ProgramData\delphi\VirtualTreeView-master\Source'
$SKIA    = 'D:\ProgramData\delphi\Skia4Delphi'
$WV      = 'D:\ProgramData\delphi\WebView4Delphi\source'

$CommonNS = 'System;Vcl;Winapi;System.Win;Data;Xml;Soap;Web;FireDAC'
$CommonDB = "$DB\Core;$DB\VCL;$DB\Persistence;$DB\Features;$DB\Governance;$DB\ThirdParty\UI"

$ShineCommon = "$ROOT\DeepShine\Common\Core;$ROOT\DeepShine\Common\UI;$ROOT\DeepShine\Common\Data;$ROOT\DeepShine\Common\Domain;$ROOT\DeepShine\Common\Flow;$ROOT\DeepShine\Common\Legacy;$ROOT\DeepShine\Common\Browser;$ROOT\DeepShine\Common\Security;$ROOT\DeepShine\Common\Controller"

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
  $cargs = @("-E$RESULT", "-U$U", "-NS$NS")
  if ($I) { $cargs += "-I$I" }
  if ($D) { $cargs += "-D$D" }
  $cargs += $Dpr
  & $DCC @cargs 2>&1 | Tee-Object -FilePath $log
  $rc = $LASTEXITCODE
  Add-Content -Path $log -Value "EXIT_CODE=$rc"
  Write-Host "ExitCode=$rc"
  return $rc
}

$results = @{}

# G5-1 DeepShine.TestGUI: + VTV13
$results['G5-1_DeepShine.TestGUI'] = Run-Compile -Tag 'G5-1_DeepShine.TestGUI' `
  -Dpr "$ROOT\DeepShine\Apps\DeepShine.TestGUI\DeepShine.TestGUI.dpr" `
  -U   "$CommonDB;$ShineCommon;$ROOT\DeepShine\Apps\DeepShine.TestGUI;$VTV13"

# G5-2 DeepShineConfig: + VTV13
$results['G5-2_DeepShineConfig'] = Run-Compile -Tag 'G5-2_DeepShineConfig' `
  -Dpr "$ROOT\DeepShine\Apps\DeepShineConfig\DeepShineConfig.dpr" `
  -U   "$CommonDB;$ShineCommon;$ROOT\DeepShine\Apps\DeepShineConfig;$VTV13"

# G5-3 DeepShineFlow: + VTV13 + WV + SKIA
$results['G5-3_DeepShineFlow'] = Run-Compile -Tag 'G5-3_DeepShineFlow' `
  -Dpr "$ROOT\DeepShine\Apps\DeepShineFlow\DeepShineFlow.dpr" `
  -U   "$CommonDB;$ShineCommon;$ROOT\DeepShine\Apps\DeepShineFlow;$VTV13;$WV;$SKIA"

# G5-4 DeepShineStudio: + VTV13
$results['G5-4_DeepShineStudio'] = Run-Compile -Tag 'G5-4_DeepShineStudio' `
  -Dpr "$ROOT\DeepShine\Apps\DeepShineStudio\DeepShineStudio.dpr" `
  -U   "$CommonDB;$ShineCommon;$ROOT\DeepShine\Apps\DeepShineStudio;$VTV13"

# G7-1 DeepSync.Agent: + src\forms (uAgentSnapshotStore -> uNewLocalTaskForm)
$results['G7-1_DeepSync.Agent'] = Run-Compile -Tag 'G7-1_DeepSync.Agent' `
  -Dpr "$ROOT\DeepSync\DeepSync.Agent.dpr" `
  -U   "$CommonDB;$ROOT\DeepSync\src\core;$ROOT\DeepSync\src\agents;$ROOT\DeepSync\src\forms;$ROOT\DeepSync\src\frames"

Write-Host ""
Write-Host "===== RETRY SUMMARY ====="
$results.Keys | Sort-Object | ForEach-Object {
  $rc = $results[$_]
  $status = if ($rc -eq 0) { 'OK' } else { "FAIL($rc)" }
  Write-Host ("{0,-32} {1}" -f $_, $status)
}
