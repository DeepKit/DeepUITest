# Compile script for Test Batch 3 (12 .dpr files) — group-test-batch3
# Time: 2026-05-17
# Compiler: Delphi 13.1 (BDS 37.0)
# Outputs to:  _test_batch3_compile/_result/
# Per-file logs to: _test_batch3_compile/<dpr-stem>.log

$ErrorActionPreference = 'Continue'

$DCC = 'D:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe'
$DB = 'd:\_Progs\02Business\DeepBase'
$ROOT = 'd:\_Progs\02Business'
$OUT = Join-Path $PSScriptRoot '_result'
$LOGDIR = $PSScriptRoot

New-Item -ItemType Directory -Force -Path $OUT | Out-Null

$BDS_CAT = 'D:\Personal\Documents\Embarcadero\Studio\37.0\CatalogRepository'
$DUNITX  = 'D:\ProgramData\delphi\DUnitX\Source'
$VTV13   = "$BDS_CAT\VirtualTreeView-13\2025.03\Source"
$SKIA    = 'D:\ProgramData\delphi\Skia4Delphi'
$SYNEDIT = 'D:\ProgramData\delphi\SynEdit-master\Source'
$SYNHL   = 'D:\ProgramData\delphi\SynEdit-master\Source\Highlighters'
$VTV_M   = 'D:\ProgramData\delphi\VirtualTreeView-master\Source'
$CEF     = 'D:\ProgramData\delphi\CEF4Delphi-131\source'
$WV      = 'D:\ProgramData\delphi\WebView4Delphi\source'

$CommonNS    = 'System;Vcl;Winapi;System.Win;Data;Xml;Soap;Web;FireDAC'
$CommonNSFmx = 'System;Vcl;Fmx;Winapi;System.Win;Data;Xml;Soap;Web;FireDAC'
$CommonDB    = "$DB\Core;$DB\VCL;$DB\Persistence;$DB\Features;$DB\Governance"

# DeepSync src tree (per G7 — needs core+agents+forms+frames because of pre-existing core->forms reverse coupling)
$DeepSyncSearch = "$ROOT\DeepSync\src\core;$ROOT\DeepSync\src\agents;$ROOT\DeepSync\src\forms;$ROOT\DeepSync\src\frames"

$Cases = @(
  # G21 — DeepStory Tests + DeepSVG + DeepSync first test (8)
  @{ Name='DeepStoryBehavior';      Dpr="$ROOT\DeepStory\Tests\BehaviorMock\DeepStoryBehavior.dpr"; U="$CommonDB;$ROOT\DeepStory;$SYNEDIT;$SYNHL;$ROOT\DeepStory\Tests\BehaviorMock;$ROOT\DeepBase\Tests\Governance"; NS=$CommonNS; I=$SYNEDIT; D=$null },
  @{ Name='TestCoreFeaturesRunner'; Dpr="$ROOT\DeepSVG\TestCoreFeaturesRunner.dpr";                 U="$CommonDB;$ROOT\DeepSVG;$ROOT\DeepSVG\tests;$CEF;$DUNITX";                                                       NS=$CommonNS; I=$CEF;     D=$null },
  @{ Name='TestRunner';             Dpr="$ROOT\DeepSVG\TestRunner.dpr";                             U="$CommonDB;$ROOT\DeepSVG;$ROOT\DeepSVG\tests;$CEF";                                                                NS=$CommonNS; I=$CEF;     D=$null },
  @{ Name='TestRunner_Simple';      Dpr="$ROOT\DeepSVG\TestRunner_Simple.dpr";                      U="$CommonDB;$ROOT\DeepSVG;$ROOT\DeepSVG\tests;$CEF";                                                                NS=$CommonNS; I=$CEF;     D=$null },
  @{ Name='Smoke_Anim';             Dpr="$ROOT\DeepSVG\tests\smoke\Smoke_Anim.dpr";                 U="$CommonDB;$ROOT\DeepSVG;$ROOT\DeepSVG\tests;$ROOT\DeepSVG\tests\smoke;$CEF";                                       NS=$CommonNS; I=$CEF;     D=$null },
  @{ Name='Smoke_Static';           Dpr="$ROOT\DeepSVG\tests\smoke\Smoke_Static.dpr";               U="$CommonDB;$ROOT\DeepSVG;$ROOT\DeepSVG\tests;$ROOT\DeepSVG\tests\smoke;$SKIA";                                      NS=$CommonNS; I=$null;    D='SKIA' },
  @{ Name='Smoke_UIExport';         Dpr="$ROOT\DeepSVG\tests\smoke\Smoke_UIExport.dpr";             U="$CommonDB";                                                                                                       NS=$CommonNS; I=$null;    D=$null },
  @{ Name='DeepSyncTests';          Dpr="$ROOT\DeepSync\tests\DeepSyncTests.dpr";                   U="$CommonDB;$DeepSyncSearch;$ROOT\DeepSync\tests;$DUNITX";                                                          NS=$CommonNSFmx; I=$null; D=$null },

  # G22 — DeepSync remaining tests (4)
  @{ Name='MockBehaviorRunner';        Dpr="$ROOT\DeepSync\tests\MockBehaviorRunner.dpr";           U="$CommonDB;$DeepSyncSearch;$ROOT\DeepSync\tests";                                                                  NS=$CommonNSFmx; I=$null; D=$null },
  @{ Name='TestAgentIPC_Smoke';        Dpr="$ROOT\DeepSync\tests\TestAgentIPC_Smoke.dpr";           U="$CommonDB;$DeepSyncSearch";                                                                                       NS=$CommonNS;    I=$null; D=$null },
  @{ Name='TestScreenShare_Full';      Dpr="$ROOT\DeepSync\tests\TestScreenShare_Full.dpr";         U="$CommonDB;$DeepSyncSearch";                                                                                       NS=$CommonNSFmx; I=$null; D=$null },
  @{ Name='TestScreenShare_Standalone';Dpr="$ROOT\DeepSync\tests\TestScreenShare_Standalone.dpr";   U="$CommonDB;$DeepSyncSearch";                                                                                       NS=$CommonNSFmx; I=$null; D=$null }
)

$results = @()
foreach ($c in $Cases) {
  $log = Join-Path $LOGDIR ("{0}.log" -f $c.Name)
  $cargs = @("-E$OUT", "-U$($c.U)", "-NS$($c.NS)")
  if ($c.I) { $cargs += "-I$($c.I)" }
  if ($c.D) { $cargs += "-D$($c.D)" }
  $cargs += $c.Dpr

  Write-Host "==> Compiling $($c.Name)" -ForegroundColor Cyan
  & $DCC @cargs *> $log
  $code = $LASTEXITCODE
  Write-Host ("    ExitCode={0}  log={1}" -f $code, $log)
  $results += [PSCustomObject]@{ Name=$c.Name; ExitCode=$code; Log=$log }
}

Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Yellow
$results | ForEach-Object { Write-Host ("{0,-32} {1}" -f $_.Name, $_.ExitCode) }
$results | Export-Csv -NoTypeInformation -Path (Join-Path $LOGDIR 'summary.csv')
