# Compile G10/G11/G13/G14/G15/G16part dprs
$ErrorActionPreference = 'Continue'
$DCC = 'D:\Program Files (x86)\Embarcadero\Studio\23.0\bin\dcc64.exe'
$Base = 'D:\_Progs\02Business'
$DB = "$Base\DeepBase"
$LogDir = "$Base\.kiro\specs\aierrorhandler-rollout\exec-log\_remaining_compile"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$DBCore = "$DB\Core;$DB\VCL;$DB\Persistence;$DB\Features;$DB\Governance;$DB\ThirdParty\UI;$DB\ThirdParty\Payment;$DB\ThirdParty\Social;$DB\Tools\WebService"
$Tests  = "$DB\Tests;$DB\Tests\AutoFix;$DB\Tests\Architecture;$DB\Tests\Governance;$DB\Tests\Acceptance;$DB\Tests\Integration;$DB\Tests\GUI;$DB\Tests\Speech;$DB\Tests\Stress"
$NS = 'System;Vcl;Winapi;System.Win;Data;Xml;Soap;Web;FireDAC'

$jobs = @(
  # ------ G10 ------
  @{ Group='G10'; Name='DoQryDemo';            Dpr="$DB\doQry\examples\DoQryDemo\DoQryDemo.dpr";           UnitPath="$DBCore;$DB\doQry;$DB\doQry\src" },
  @{ Group='G10'; Name='DataBindingDemo';      Dpr="$DB\Examples\DataBindingDemo\DataBindingDemo.dpr";     UnitPath="$DBCore;$DB\Examples\DataBindingDemo" },
  @{ Group='G10'; Name='FullDemo';             Dpr="$DB\Examples\FullDemo\FullDemo.dpr";                   UnitPath="$DBCore;$DB\Examples\FullDemo" },
  @{ Group='G10'; Name='MicroserviceClientDemo'; Dpr="$DB\Examples\MicroserviceClientDemo\MicroserviceClientDemo.dpr"; UnitPath="$DBCore;$DB\Examples\MicroserviceClientDemo" },
  @{ Group='G10'; Name='MultiLanguageDemo';    Dpr="$DB\Examples\MultiLanguageDemo\MultiLanguageDemo.dpr"; UnitPath="$DBCore;$DB\Examples\MultiLanguageDemo" },
  @{ Group='G10'; Name='MVVMDemo';             Dpr="$DB\Examples\MVVMDemo\MVVMDemo.dpr";                   UnitPath="$DBCore;$DB\Examples\MVVMDemo" },
  @{ Group='G10'; Name='Phase0Demo';           Dpr="$DB\Examples\Phase0Demo\Phase0Demo.dpr";               UnitPath="$DBCore;$DB\Examples\Phase0Demo" },

  # ------ G11 ------
  @{ Group='G11'; Name='Phase1Demo';           Dpr="$DB\Examples\Phase1Demo\Phase1Demo.dpr";               UnitPath="$DBCore;$DB\Examples\Phase1Demo" },
  @{ Group='G11'; Name='CRUDApp';              Dpr="$DB\Examples\Templates\CRUDApp\CRUDApp.dpr";           UnitPath="$DBCore;$DB\Examples\Templates\CRUDApp" },
  @{ Group='G11'; Name='DataAnalyzer';         Dpr="$DB\Examples\Templates\DataAnalyzer\DataAnalyzer.dpr"; UnitPath="$DBCore;$DB\Examples\Templates\DataAnalyzer" },
  @{ Group='G11'; Name='DocManager';           Dpr="$DB\Examples\Templates\DocManager\DocManager.dpr";     UnitPath="$DBCore;$DB\Examples\Templates\DocManager" },
  @{ Group='G11'; Name='VCLDeepShellDemo';     Dpr="$DB\Examples\VCLDeepShellDemo\VCLDeepShellDemo.dpr";   UnitPath="$DBCore;$DB\Examples\VCLDeepShellDemo" },

  # ------ G13 ------
  @{ Group='G13'; Name='DeepBaseTests';        Dpr="$DB\Tests\DeepBaseTests.dpr";        UnitPath="$DBCore;$Tests" },
  @{ Group='G13'; Name='InferenceTests';       Dpr="$DB\Tests\InferenceTests.dpr";       UnitPath="$DBCore;$Tests" },
  @{ Group='G13'; Name='MinimalDUnitX';        Dpr="$DB\Tests\MinimalDUnitX.dpr";        UnitPath="$DBCore;$Tests" },
  @{ Group='G13'; Name='SimpleTest';           Dpr="$DB\Tests\SimpleTest.dpr";           UnitPath="$DBCore;$Tests" },
  @{ Group='G13'; Name='TestLLMClient';        Dpr="$DB\Tests\TestLLMClient.dpr";        UnitPath="$DBCore;$Tests" },
  @{ Group='G13'; Name='TestLLMProxyClient';   Dpr="$DB\Tests\TestLLMProxyClient.dpr";   UnitPath="$DBCore;$Tests" },
  @{ Group='G13'; Name='TestNewModules';       Dpr="$DB\Tests\TestNewModules.dpr";       UnitPath="$DBCore;$Tests;$DB\Tools\CLI" },

  # ------ G14 ------
  @{ Group='G14'; Name='DebugTest';   Dpr="$DB\Tests\DebugTest.dpr";   UnitPath="$DBCore;$Tests" },
  @{ Group='G14'; Name='DebugTest2';  Dpr="$DB\Tests\DebugTest2.dpr";  UnitPath="$DBCore;$Tests" },
  @{ Group='G14'; Name='DebugTest3';  Dpr="$DB\Tests\DebugTest3.dpr";  UnitPath="$DBCore;$Tests" },
  @{ Group='G14'; Name='DebugTest4';  Dpr="$DB\Tests\DebugTest4.dpr";  UnitPath="$DBCore;$Tests" },
  @{ Group='G14'; Name='DebugTest5';  Dpr="$DB\Tests\DebugTest5.dpr";  UnitPath="$DBCore;$Tests" },
  @{ Group='G14'; Name='DebugTest6';  Dpr="$DB\Tests\DebugTest6.dpr";  UnitPath="$DBCore;$Tests" },

  # ------ G15 ------
  @{ Group='G15'; Name='DeepBaseAcceptanceTest';     Dpr="$DB\Tests\Acceptance\DeepBaseAcceptanceTest.dpr";   UnitPath="$DBCore;$Tests" },
  @{ Group='G15'; Name='DeepBaseArchitectureTests';  Dpr="$DB\Tests\Architecture\DeepBaseArchitectureTests.dpr"; UnitPath="$DBCore;$Tests" },
  @{ Group='G15'; Name='ConfigRegistrarPBT';         Dpr="$DB\Tests\Governance\ConfigRegistrarPBT.dpr";       UnitPath="$DBCore;$Tests" },
  @{ Group='G15'; Name='DeepBaseGUITests';           Dpr="$DB\Tests\GUI\DeepBaseGUITests.dpr";                UnitPath="$DBCore;$Tests" },
  @{ Group='G15'; Name='PageDriverSmoke';            Dpr="$DB\Tests\GUI\PageDriverSmoke.dpr";                 UnitPath="$DBCore;$Tests;D:\ProgramData\delphi\WebView4Delphi\source" },
  @{ Group='G15'; Name='DeepBaseIntegrationTests';   Dpr="$DB\Tests\Integration\DeepBaseIntegrationTests.dpr"; UnitPath="$DBCore;$Tests" },

  # ------ G16part ------
  @{ Group='G16p'; Name='SpeechSpike';          Dpr="$DB\Tests\Speech\SpeechSpike.dpr";         UnitPath="$DBCore;$Tests" },
  @{ Group='G16p'; Name='TestSpeechHeadless';   Dpr="$DB\Tests\Speech\TestSpeechHeadless.dpr";  UnitPath="$DBCore;$Tests" },
  @{ Group='G16p'; Name='DeepBaseStressTests';  Dpr="$DB\Tests\Stress\DeepBaseStressTests.dpr"; UnitPath="$DBCore;$Tests" }
)

$summary = @()
foreach ($j in $jobs) {
  $binDir = Split-Path -Parent $j.Dpr
  $binDir = Join-Path $binDir 'bin'
  New-Item -ItemType Directory -Force -Path $binDir | Out-Null
  $logFile = Join-Path $LogDir ("{0}_{1}.log" -f $j.Group, $j.Name)
  Write-Output ("==> [{0}] {1}" -f $j.Group, $j.Name)
  $args = @('-Q', "-E$binDir", "-U$($j.UnitPath)", "-NS$NS", $j.Dpr)
  $proc = Start-Process -FilePath $DCC -ArgumentList $args -Wait -NoNewWindow -PassThru -RedirectStandardOutput $logFile -RedirectStandardError "$logFile.err"
  $exit = $proc.ExitCode
  $summary += [PSCustomObject]@{ Group=$j.Group; Name=$j.Name; ExitCode=$exit; Log=$logFile }
  Write-Output ("    ExitCode=$exit")
}

Write-Output ''
Write-Output 'SUMMARY:'
$summary | Group-Object Group | ForEach-Object {
  $g = $_.Name
  $total = $_.Count
  $ok = ($_.Group | Where-Object { $_.ExitCode -eq 0 }).Count
  Write-Output ("  {0}: {1}/{2} clean" -f $g, $ok, $total)
}
$summary | ConvertTo-Json | Set-Content (Join-Path $LogDir 'compile_summary.json') -Encoding UTF8
