# G8 Tool_Program 批次编译脚本
$ErrorActionPreference = 'Continue'
$DCC = 'D:\Program Files (x86)\Embarcadero\Studio\23.0\bin\dcc64.exe'
$Base = 'D:\_Progs\02Business'
$DB = "$Base\DeepBase"
$LogDir = "$Base\.kiro\specs\aierrorhandler-rollout\exec-log\_g8_compile"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$DBCorePaths = "$DB\Core;$DB\VCL;$DB\Persistence;$DB\Features"

$jobs = @(
  @{
    Name = 'DeepBase-CLI'
    Dpr = "$DB\Tools\CLI\DeepBase.dpr"
    BinDir = "$DB\Tools\CLI\bin"
    UnitPath = "$DBCorePaths"
  },
  @{
    Name = 'DeepBaseTray'
    Dpr = "$DB\Tools\Tray\DeepBaseTray.dpr"
    BinDir = "$DB\Tools\Tray\bin"
    UnitPath = "$DBCorePaths;$DB\Tools\Tray;$DB\Tools\Tray\Frames;$DB\Tools\Tray\Forms;$DB\Tools\Tray\Automation"
  },
  @{
    Name = 'DeepBaseStudio'
    Dpr = "$DB\Tools\Studio\DeepBaseStudio.dpr"
    BinDir = "$DB\Tools\Studio\bin\DeepBaseStudio"
    UnitPath = "$DBCorePaths;$DB\Tools\Studio;$DB\Tools\Studio\Forms;$DB\Tools\Studio\Frames"
  },
  @{
    Name = 'Studio'
    Dpr = "$DB\Tools\Studio\Studio.dpr"
    BinDir = "$DB\Tools\Studio\bin\Studio"
    UnitPath = "$DBCorePaths;$DB\Tools\Studio;$DB\Tools\Studio\Forms;$DB\Tools\Studio\Frames"
  },
  @{
    Name = 'UniPublisher'
    Dpr = "$DB\Tools\UniPublisher\DeepPublisher.dpr"
    BinDir = "$DB\Tools\UniPublisher\bin"
    UnitPath = "$DBCorePaths;$DB\Tools\UniPublisher;$DB\Tools\UniPublisher\Forms;$DB\Tools\UniPublisher\Core"
  },
  @{
    Name = 'UpdaterHelper'
    Dpr = "$DB\Tools\UpdaterHelper\UpdaterHelper.dpr"
    BinDir = "$DB\Tools\UpdaterHelper\bin"
    UnitPath = "$DBCorePaths;$DB\Tools\UpdaterHelper"
  }
)

$summary = @()
foreach ($j in $jobs) {
  New-Item -ItemType Directory -Force -Path $j.BinDir | Out-Null
  $logFile = Join-Path $LogDir ("$($j.Name).log")
  Write-Output "==> Compiling $($j.Name)"
  $args = @('-Q', "-E$($j.BinDir)", "-U$($j.UnitPath)", $j.Dpr)
  $proc = Start-Process -FilePath $DCC -ArgumentList $args -Wait -NoNewWindow -PassThru -RedirectStandardOutput $logFile -RedirectStandardError "$logFile.err"
  $exit = $proc.ExitCode
  $summary += [PSCustomObject]@{ Name = $j.Name; ExitCode = $exit; Log = $logFile }
  Write-Output ("    ExitCode=$exit")
}

Write-Output ''
Write-Output 'SUMMARY:'
$summary | Format-Table -AutoSize
$summary | ConvertTo-Json | Set-Content -Path (Join-Path $LogDir 'summary.json') -Encoding UTF8
