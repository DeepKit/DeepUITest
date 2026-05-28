# Compile script for Test Batch 2 (16 .dpr files) — group-test-batch2
# Time: 2026-05-17
# Compiler: Delphi 13.1 (BDS 37.0)
# Outputs to:  _test_batch2_compile/_result/
# Per-file logs to: _test_batch2_compile/<dpr-stem>.log

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
$MSHELL  = "$BDS_CAT\MustangpeakVirtualShell-13\2025.03\Source"
$MCOMMON = "$BDS_CAT\MustangpeakCommonLibrary-13\2025.03\Source"
$MLIST   = "$BDS_CAT\MustangpeakListView-13\2025.03\Source"
$SKIA    = 'D:\ProgramData\delphi\Skia4Delphi'
$SYNEDIT = 'D:\ProgramData\delphi\SynEdit-master\Source'
$SYNHL   = 'D:\ProgramData\delphi\SynEdit-master\Source\Highlighters'
$VTV_M   = 'D:\ProgramData\delphi\VirtualTreeView-master\Source'

$CommonNS    = 'System;Vcl;Winapi;System.Win;Data;Xml;Soap;Web;FireDAC'
$CommonNSFmx = 'System;Vcl;Fmx;Winapi;System.Win;Data;Xml;Soap;Web;FireDAC'
$LaunchNS    = 'System;Vcl;Vcl.Imaging;Vcl.Touch;Vcl.Samples;Vcl.Shell;Winapi;System.Win;Data;Xml;Soap;Web;FireDAC'
$CommonDB    = "$DB\Core;$DB\VCL;$DB\Persistence;$DB\Features;$DB\Governance"
$CommonDBFmx = "$DB\Core;$DB\VCL;$DB\FMX;$DB\Persistence;$DB\Features;$DB\Governance"

# DeepShine Common (per G5)
$ShineCommon = "$ROOT\DeepShine\Common\Core;$ROOT\DeepShine\Common\UI;$ROOT\DeepShine\Common\Data;$ROOT\DeepShine\Common\Domain;$ROOT\DeepShine\Common\Flow;$ROOT\DeepShine\Common\Legacy;$ROOT\DeepShine\Common\Browser;$ROOT\DeepShine\Common\Security;$ROOT\DeepShine\Common\Controller"

# DeepInput tree (per compile_all.bat)
$DeepInput = "$ROOT\DeepInput\src;$SKIA;$SYNEDIT;$SYNHL;$VTV_M"

# DeepInsight tree (test runner needs FMX side; tests + parent + backend)
$DeepInsightCommon = "$ROOT\DeepInsight;$ROOT\DeepInsight\backend;$ROOT\DeepInsight\tests;$DUNITX;$SKIA"

# DeepLaunch tree (mirrors G4 + Tests subdir + MustangpeakListView for FrameFileExplorer)
$DeepLaunchCommon = "$ROOT\DeepLaunch\src\Core;$ROOT\DeepLaunch\src\UI;$ROOT\DeepLaunch\Tests;$VTV13;$MSHELL;$MCOMMON;$MLIST;$SKIA"

$Cases = @(
  # G19 — DeepConfig 余 + DeepInput + DeepInsight + DeepLaunch + DeepMoveC tests (8)
  @{ Name='SimpleTest';            Dpr="$ROOT\DeepConfig\tests\SimpleTest.dpr";                                  U="$CommonDB;$ROOT\DeepConfig\tests";              NS=$CommonNS;    I=$null;    D=$null },
  @{ Name='Test';                  Dpr="$ROOT\DeepConfig\tests\Test.dpr";                                        U="$CommonDB;$ROOT\DeepConfig\tests";              NS=$CommonNS;    I=$null;    D=$null },
  @{ Name='behavior_mock';         Dpr="$ROOT\DeepInput\src\behavior_mock.dpr";                                  U="$CommonDB;$DeepInput";                          NS=$CommonNS;    I=$SYNEDIT; D='SKIA' },
  @{ Name='struct_test';           Dpr="$ROOT\DeepInput\src\struct_test.dpr";                                    U="$CommonDB;$DeepInput";                          NS=$CommonNS;    I=$null;    D=$null },
  @{ Name='DeepInsightBehavior';   Dpr="$ROOT\DeepInsight\tests\BehaviorMock\DeepInsightBehavior.dpr";           U="$CommonDBFmx;$DeepInsightCommon;$ROOT\DeepInsight\tests\BehaviorMock;$ROOT\DeepBase\Tests\Governance"; NS=$CommonNSFmx; I=$null; D='SKIA' },
  @{ Name='DeepInsightTests';      Dpr="$ROOT\DeepInsight\tests\DeepInsightTests.dpr";                           U="$CommonDBFmx;$DeepInsightCommon";               NS=$CommonNSFmx; I=$null;    D='SKIA' },
  @{ Name='RunTests';              Dpr="$ROOT\DeepLaunch\Tests\RunTests.dpr";                                    U="$CommonDB;$DeepLaunchCommon";                   NS=$LaunchNS;    I=$null;    D=$null },
  @{ Name='DeepMoveCCoreTests';    Dpr="$ROOT\DeepMoveC\Tests\DeepMoveCCoreTests.dpr";                           U="$CommonDB;$ROOT\DeepMoveC;$ROOT\DeepMoveC\AntiTamperPackage;$ROOT\DeepMoveC\Tests;$ROOT\DeepMoveC\Tests\Mock;$DUNITX"; NS=$CommonNS; I=$null; D=$null },

  # G20 — DeepShine + DeepStory tests (8)
  @{ Name='DeepShineBehavior';     Dpr="$ROOT\DeepShine\Tests\BehaviorMock\DeepShineBehavior.dpr";               U="$CommonDB;$ShineCommon;$ROOT\DeepShine\Tests\BehaviorMock;$ROOT\DeepBase\Tests\Governance"; NS=$CommonNS; I=$null; D=$null },
  @{ Name='GovernanceSmoke';       Dpr="$ROOT\DeepShine\Tests\GovernanceSmoke\GovernanceSmoke.dpr";              U="$CommonDB;$ShineCommon;$ROOT\DeepShine\Tests\GovernanceSmoke";                              NS=$CommonNS; I=$null; D=$null },
  @{ Name='DeepStorySchemeBench'; Dpr="$ROOT\DeepStory\DeepStorySchemeBench.dpr";                                U="$CommonDB;$ROOT\DeepStory;$SYNEDIT;$SYNHL";     NS=$CommonNS;    I=$SYNEDIT; D=$null },
  @{ Name='TestApi';               Dpr="$ROOT\DeepStory\TestApi.dpr";                                            U="$CommonDB;$ROOT\DeepStory;$SYNEDIT;$SYNHL";     NS=$CommonNS;    I=$SYNEDIT; D=$null },
  @{ Name='TestDB';                Dpr="$ROOT\DeepStory\TestDB.dpr";                                             U="$CommonDB;$ROOT\DeepStory;$SYNEDIT;$SYNHL";     NS=$CommonNS;    I=$SYNEDIT; D=$null },
  @{ Name='TestDeepStoryRef';      Dpr="$ROOT\DeepStory\TestDeepStoryRef.dpr";                                   U="$CommonDB;$ROOT\DeepStory;$SYNEDIT;$SYNHL";     NS=$CommonNS;    I=$SYNEDIT; D=$null },
  @{ Name='TestImport';            Dpr="$ROOT\DeepStory\TestImport.dpr";                                         U="$CommonDB;$ROOT\DeepStory;$SYNEDIT;$SYNHL";     NS=$CommonNS;    I=$SYNEDIT; D=$null },
  @{ Name='TestWriting';           Dpr="$ROOT\DeepStory\TestWriting.dpr";                                        U="$CommonDB;$ROOT\DeepStory;$SYNEDIT;$SYNHL";     NS=$CommonNS;    I=$SYNEDIT; D=$null }
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
