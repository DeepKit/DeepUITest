# G5/G6/G7 compile script
# Compiles each modified .dpr; logs ExitCode + last 80 lines of output to _result/<n>.log

$ErrorActionPreference = 'Continue'
$DCC = 'D:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe'
$DB  = 'd:\_Progs\02Business\DeepBase'
$ROOT = 'd:\_Progs\02Business'
$OUT  = 'd:\_Progs\02Business\.kiro\specs\aierrorhandler-rollout\exec-log\_g5g6g7_compile'
$RESULT = Join-Path $OUT '_result'
New-Item -ItemType Directory -Path $RESULT -Force | Out-Null

# Third-party libs (matching G2/G3/G4 conventions)
$BDS_CAT = 'D:\Personal\Documents\Embarcadero\Studio\37.0\CatalogRepository'
$VTV13   = Join-Path $BDS_CAT 'VirtualTreeView-13\2025.03\Source'
$SKIA    = 'D:\ProgramData\delphi\Skia4Delphi'
$SYNEDIT = 'D:\ProgramData\delphi\SynEdit-master\Source'
$SYNHL   = 'D:\ProgramData\delphi\SynEdit-master\Source\Highlighters'
$VTV_M   = 'D:\ProgramData\delphi\VirtualTreeView-master\Source'
$CEF     = 'D:\ProgramData\delphi\CEF4Delphi-131\source'
$WV      = 'D:\ProgramData\delphi\WebView4Delphi\source'

$CommonNS = 'System;Vcl;Winapi;System.Win;Data;Xml;Soap;Web;FireDAC'
$CommonDB = "$DB\Core;$DB\VCL;$DB\Persistence;$DB\Features;$DB\Governance;$DB\ThirdParty\UI"

# DeepShine common search paths (apps share these)
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
  $cargs = @(
    "-E$RESULT",
    "-U$U",
    "-NS$NS"
  )
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

# ===== G5 — DeepShine =====

# G5-1 DeepShine.TestGUI
$results['G5-1_DeepShine.TestGUI'] = Run-Compile -Tag 'G5-1_DeepShine.TestGUI' `
  -Dpr "$ROOT\DeepShine\Apps\DeepShine.TestGUI\DeepShine.TestGUI.dpr" `
  -U   "$CommonDB;$ShineCommon;$ROOT\DeepShine\Apps\DeepShine.TestGUI"

# G5-2 DeepShineConfig
$results['G5-2_DeepShineConfig'] = Run-Compile -Tag 'G5-2_DeepShineConfig' `
  -Dpr "$ROOT\DeepShine\Apps\DeepShineConfig\DeepShineConfig.dpr" `
  -U   "$CommonDB;$ShineCommon;$ROOT\DeepShine\Apps\DeepShineConfig"

# G5-3 DeepShineFlow
$results['G5-3_DeepShineFlow'] = Run-Compile -Tag 'G5-3_DeepShineFlow' `
  -Dpr "$ROOT\DeepShine\Apps\DeepShineFlow\DeepShineFlow.dpr" `
  -U   "$CommonDB;$ShineCommon;$ROOT\DeepShine\Apps\DeepShineFlow;$WV;$SKIA"

# G5-4 DeepShineStudio
$results['G5-4_DeepShineStudio'] = Run-Compile -Tag 'G5-4_DeepShineStudio' `
  -Dpr "$ROOT\DeepShine\Apps\DeepShineStudio\DeepShineStudio.dpr" `
  -U   "$CommonDB;$ShineCommon;$ROOT\DeepShine\Apps\DeepShineStudio"

# G5-5 DeepShine.Legacy.FakeCLI
$results['G5-5_FakeCLI'] = Run-Compile -Tag 'G5-5_FakeCLI' `
  -Dpr "$ROOT\DeepShine\Common\Legacy\DeepShine.Legacy.FakeCLI.dpr" `
  -U   "$CommonDB;$ROOT\DeepShine\Common\Legacy"

# ===== G6 — DeepStory + DeepSVG =====

# G6-1 DeepStory
$results['G6-1_DeepStory'] = Run-Compile -Tag 'G6-1_DeepStory' `
  -Dpr "$ROOT\DeepStory\DeepStory.dpr" `
  -U   "$CommonDB;$ROOT\DeepStory;$SYNEDIT;$SYNHL" `
  -I   "$SYNEDIT"

# G6-2 DeepStoryRef
$results['G6-2_DeepStoryRef'] = Run-Compile -Tag 'G6-2_DeepStoryRef' `
  -Dpr "$ROOT\DeepStory\DeepStoryRef.dpr" `
  -U   "$CommonDB;$ROOT\DeepStory"

# G6-3 CEFCopier
$results['G6-3_CEFCopier'] = Run-Compile -Tag 'G6-3_CEFCopier' `
  -Dpr "$ROOT\DeepSVG\CEFCopier.dpr" `
  -U   "$CommonDB;$ROOT\DeepSVG"

# G6-4 DeepSVG (heavy CEF)
$results['G6-4_DeepSVG'] = Run-Compile -Tag 'G6-4_DeepSVG' `
  -Dpr "$ROOT\DeepSVG\DeepSVG.dpr" `
  -U   "$CommonDB;$ROOT\DeepSVG;$ROOT\DeepSVG\tests;$CEF" `
  -I   "$CEF"

# G6-5 DeepSVG_TestRunner
$results['G6-5_DeepSVG_TestRunner'] = Run-Compile -Tag 'G6-5_DeepSVG_TestRunner' `
  -Dpr "$ROOT\DeepSVG\DeepSVG_TestRunner.dpr" `
  -U   "$CommonDB;$ROOT\DeepSVG;$ROOT\DeepSVG\tests;$CEF" `
  -I   "$CEF"

# ===== G7 — DeepSync =====

# G7-1 DeepSync.Agent
$results['G7-1_DeepSync.Agent'] = Run-Compile -Tag 'G7-1_DeepSync.Agent' `
  -Dpr "$ROOT\DeepSync\DeepSync.Agent.dpr" `
  -U   "$CommonDB;$ROOT\DeepSync\src\core;$ROOT\DeepSync\src\agents"

# G7-3 DeepSync.ScreenAgent
$results['G7-3_DeepSync.ScreenAgent'] = Run-Compile -Tag 'G7-3_DeepSync.ScreenAgent' `
  -Dpr "$ROOT\DeepSync\DeepSync.ScreenAgent.dpr" `
  -U   "$CommonDB;$ROOT\DeepSync\src\core;$ROOT\DeepSync\src\agents"

Write-Host ""
Write-Host "===== SUMMARY ====="
$results.Keys | Sort-Object | ForEach-Object {
  $rc = $results[$_]
  $status = if ($rc -eq 0) { 'OK' } else { "FAIL($rc)" }
  Write-Host ("{0,-32} {1}" -f $_, $status)
}
