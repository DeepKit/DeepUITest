# G9 Tool_Program 批次编译脚本
$ErrorActionPreference = 'Continue'
$DCC = 'D:\Program Files (x86)\Embarcadero\Studio\23.0\bin\dcc64.exe'
$Base = 'D:\_Progs\02Business'
$DB = "$Base\DeepBase"
$LogDir = "$Base\.kiro\specs\aierrorhandler-rollout\exec-log\_g9_compile"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$DBCorePaths = "$DB\Core;$DB\VCL;$DB\Persistence;$DB\Features"
$NS = 'System;Vcl;Winapi;System.Win;Data;Xml;Soap;Web;FireDAC'

$jobs = @(
  @{
    Name = 'LogAnalyzer'
    Dpr = "$DB\Tools\LogAnalyzer\LogAnalyzer.dpr"
    BinDir = "$DB\Tools\LogAnalyzer\bin"
    UnitPath = "$DBCorePaths;$DB\Tools\LogAnalyzer"
    NS = $NS
  },
  @{
    Name = 'SeedTool'
    Dpr = "$DB\Tools\SeedTool\SeedTool.dpr"
    BinDir = "$DB\Tools\SeedTool\bin"
    UnitPath = "$DBCorePaths;$DB\Tools\SeedTool"
    NS = $NS
  },
  @{
    Name = 'prjDoQry'
    Dpr = "$DB\doQry\prjDoQry.dpr"
    BinDir = "$DB\doQry\bin"
    UnitPath = "$DBCorePaths;$DB\doQry"
    NS = $NS
  },
  @{
    Name = 'DeepBasePathValidator'
    Dpr = "$Base\DeepInsight\tools\DeepBasePathValidator.dpr"
    BinDir = "$Base\DeepInsight\tools\bin"
    UnitPath = "$DBCorePaths;$Base\DeepInsight\tools"
    NS = $NS
  },
  @{
    Name = 'BuildRunner'
    Dpr = "$Base\DeepSync\tools\BuildRunner.dpr"
    BinDir = "$Base\DeepSync\tools\bin"
    UnitPath = "$DBCorePaths;$Base\DeepSync\tools"
    NS = $NS
  }
)

$summary = @()
foreach ($j in $jobs) {
  New-Item -ItemType Directory -Force -Path $j.BinDir | Out-Null
  $logFile = Join-Path $LogDir ("$($j.Name).log")
  Write-Output "==> Compiling $($j.Name)"
  $args = @('-Q', "-E$($j.BinDir)", "-U$($j.UnitPath)", "-NS$($j.NS)", $j.Dpr)
  $proc = Start-Process -FilePath $DCC -ArgumentList $args -Wait -NoNewWindow -PassThru -RedirectStandardOutput $logFile -RedirectStandardError "$logFile.err"
  $exit = $proc.ExitCode
  $summary += [PSCustomObject]@{ Name = $j.Name; ExitCode = $exit; Log = $logFile }
  Write-Output ("    ExitCode=$exit")
}

Write-Output ''
Write-Output 'SUMMARY:'
$summary | Format-Table -AutoSize
$summary | ConvertTo-Json | Set-Content -Path (Join-Path $LogDir 'summary.json') -Encoding UTF8
