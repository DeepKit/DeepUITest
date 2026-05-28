# Compile script for Test Batch 1 (17 .dpr files) — group-test-batch1
# Time: 2026-05-17
# Compiler: Delphi 13.1 (BDS 37.0)
# Outputs to:  _test_batch1_compile/_result/
# Per-file logs to: _test_batch1_compile/<dpr-stem>.log

$ErrorActionPreference = 'Stop'

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
$WV      = 'D:\ProgramData\delphi\WebView4Delphi\source'

$CommonNS = 'System;Vcl;Winapi;System.Win;Data;Xml;Soap;Web;FireDAC'
$CommonDB = "$DB\Core;$DB\VCL;$DB\Persistence;$DB\Features;$DB\Governance"

# DeepClip src tree (per compile-tests.bat)
$ClipSearch = "$ROOT\DeepClip\src;$ROOT\DeepClip\src\UI;$ROOT\DeepClip\src\App;$ROOT\DeepClip\src\Core;$ROOT\DeepClip\src\Storage;$ROOT\DeepClip\src\Capture;$ROOT\DeepClip\src\Privacy;$ROOT\DeepClip\src\AI;$ROOT\DeepClip\src\Voice;$ROOT\DeepClip\src\Commerce;$ROOT\DeepClip\tests;$ROOT\DeepClip\tests\Mock"

# DeepCompare delphi tree (per build.bat / compile_all.bat)
$CompareSearch = "$ROOT\DeepCompare\delphi\Core;$ROOT\DeepCompare\delphi\DeepCompare;$ROOT\DeepCompare\delphi\DeepCompareU;$SKIA;$SYNEDIT;$SYNHL;$VTV13;$WV;$DUNITX"

$Cases = @(
  # G16 part — DeepCharset/Tests/*  (single file console)
  @{ Name='QuickTest';                 Dpr="$ROOT\DeepCharset\Tests\QuickTest.dpr";                                   U="$CommonDB;$ROOT\DeepCharset"; I=$null; D=$null },
  @{ Name='SelfTest_Encoding';         Dpr="$ROOT\DeepCharset\Tests\SelfTest_Encoding.dpr";                           U="$CommonDB;$ROOT\DeepCharset;$ROOT\DeepCharset\Tests"; I=$null; D=$null },
  @{ Name='TestBOM';                   Dpr="$ROOT\DeepCharset\Tests\TestBOM.dpr";                                     U="$CommonDB;$ROOT\DeepCharset"; I=$null; D=$null },

  # G17 — DeepClip + DeepCompare tests
  @{ Name='DeepClipBehavior';          Dpr="$ROOT\DeepClip\tests\BehaviorMock\DeepClipBehavior.dpr";                  U="$CommonDB;$ClipSearch;$ROOT\DeepClip\tests\BehaviorMock;$ROOT\DeepBase\Tests\Governance"; I=$null; D=$null },
  @{ Name='DeepClip.Tests';            Dpr="$ROOT\DeepClip\tests\DeepClip.Tests.dpr";                                 U="$CommonDB;$ClipSearch"; I=$null; D=$null },
  @{ Name='DeepClipGovernanceSmoke';   Dpr="$ROOT\DeepClip\tests\GovernanceSmoke\DeepClipGovernanceSmoke.dpr";        U="$CommonDB;$ClipSearch;$ROOT\DeepClip\tests\GovernanceSmoke"; I=$null; D=$null },
  @{ Name='DeepClipGovernanceSmokeCfg';Dpr="$ROOT\DeepClip\tests\GovernanceSmoke\DeepClipGovernanceSmokeCfg.dpr";     U="$CommonDB;$ClipSearch;$ROOT\DeepClip\tests\GovernanceSmoke"; I=$null; D=$null },
  @{ Name='DeepCompareTests';          Dpr="$ROOT\DeepCompare\delphi\Tests\DeepCompareTests.dpr";                     U="$CommonDB;$CompareSearch;$ROOT\DeepCompare\delphi\Tests"; I="$SYNEDIT"; D='SKIA' },
  @{ Name='WebView2Test';              Dpr="$ROOT\DeepCompare\delphi\WebView2Test.dpr";                               U="$CommonDB;$CompareSearch"; I=$null; D=$null },

  # G18 — DeepConfig tests (single directory + DeepBase common)
  @{ Name='TestAddPairProgram';        Dpr="$ROOT\DeepConfig\TestAddPairProgram.dpr";                                 U="$CommonDB;$ROOT\DeepConfig"; I=$null; D=$null },
  @{ Name='TestConfigs';               Dpr="$ROOT\DeepConfig\TestConfigs.dpr";                                        U="$CommonDB;$ROOT\DeepConfig"; I=$null; D=$null },
  @{ Name='EasyConfigTests';           Dpr="$ROOT\DeepConfig\tests\EasyConfigTests.dpr";                              U="$CommonDB;$ROOT\DeepConfig;$ROOT\DeepConfig\tests;$DUNITX"; I=$null; D=$null },
  @{ Name='FinalConfigEditor';         Dpr="$ROOT\DeepConfig\tests\FinalConfigEditor.dpr";                            U="$CommonDB;$ROOT\DeepConfig;$ROOT\DeepConfig\tests"; I=$null; D=$null },
  @{ Name='Minimal';                   Dpr="$ROOT\DeepConfig\tests\Minimal.dpr";                                      U="$CommonDB;$ROOT\DeepConfig\tests"; I=$null; D=$null },
  @{ Name='MyConfig';                  Dpr="$ROOT\DeepConfig\tests\MyConfig.dpr";                                     U="$CommonDB;$ROOT\DeepConfig;$ROOT\DeepConfig\tests"; I=$null; D=$null },
  @{ Name='NewConfigEditor';           Dpr="$ROOT\DeepConfig\tests\NewConfigEditor.dpr";                              U="$CommonDB;$ROOT\DeepConfig;$ROOT\DeepConfig\tests"; I=$null; D=$null },
  @{ Name='SimpleConfigEditor';        Dpr="$ROOT\DeepConfig\tests\SimpleConfigEditor.dpr";                           U="$CommonDB;$ROOT\DeepConfig;$ROOT\DeepConfig\tests"; I=$null; D=$null }
)

$results = @()
foreach ($c in $Cases) {
  $log = Join-Path $LOGDIR ("{0}.log" -f $c.Name)
  $args = @("-E$OUT", "-U$($c.U)", "-NS$CommonNS")
  if ($c.I) { $args += "-I$($c.I)" }
  if ($c.D) { $args += "-D$($c.D)" }
  $args += $c.Dpr

  Write-Host "==> Compiling $($c.Name)" -ForegroundColor Cyan
  & $DCC @args *> $log
  $code = $LASTEXITCODE
  Write-Host ("    ExitCode={0}  log={1}" -f $code, $log)
  $results += [PSCustomObject]@{ Name=$c.Name; ExitCode=$code; Log=$log }
}

Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Yellow
$results | ForEach-Object { Write-Host ("{0,-32} {1}" -f $_.Name, $_.ExitCode) }
$results | Export-Csv -NoTypeInformation -Path (Join-Path $LOGDIR 'summary.csv')
