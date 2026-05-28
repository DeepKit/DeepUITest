# G4 retry: DeepMoveC via ASCII alias + capture clean per-file logs.
$ErrorActionPreference = 'Continue'
$DCC = 'D:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe'
$DB  = 'd:\_Progs\02Business\DeepBase'
$ROOT = 'd:\_Progs\02Business'
$RESULT = 'd:\_Progs\02Business\.kiro\specs\aierrorhandler-rollout\exec-log\_g4_compile\_result'

$CommonNS = 'System;Vcl;Winapi;System.Win;Data;Xml;Soap;Web;FireDAC'
$CommonDB = "$DB\Core;$DB\VCL;$DB\Persistence;$DB\Features;$DB\Governance"

function Run-Compile {
  param([string]$Tag, [string]$Dpr, [string]$U, [string]$D = '')
  Write-Host ""
  Write-Host "=== $Tag ==="
  $log = Join-Path $RESULT "$Tag.log"
  $args = @("-E$RESULT", "-U$U", "-NS$CommonNS")
  if ($D) { $args += "-D$D" }
  $args += $Dpr
  & $DCC @args 2>&1 | Tee-Object -FilePath $log
  Add-Content -Path $log -Value "EXIT_CODE=$LASTEXITCODE"
  return $LASTEXITCODE
}

# DeepMoveC: copy to ASCII name, compile, delete copy
$origDpr  = "$ROOT\DeepMoveC\C盘超级瘦身.dpr"
$aliasDpr = "$ROOT\DeepMoveC\_DeepMoveC_g4.dpr"
Copy-Item -LiteralPath $origDpr -Destination $aliasDpr -Force
try {
  $rc = Run-Compile -Tag 'DeepMoveC' `
    -Dpr $aliasDpr `
    -U   "$CommonDB;$ROOT\DeepMoveC;$ROOT\DeepMoveC\AntiTamperPackage"
  Write-Host "DeepMoveC ExitCode = $rc"
} finally {
  if (Test-Path -LiteralPath $aliasDpr) { Remove-Item -LiteralPath $aliasDpr -Force }
  # Also clean the .dcu that was generated under the alias name
  $aliasDcu = Join-Path $RESULT '_DeepMoveC_g4.dcu'
  if (Test-Path -LiteralPath $aliasDcu) { Remove-Item -LiteralPath $aliasDcu -Force }
  $aliasIdent = Join-Path $RESULT '_DeepMoveC_g4.identcache'
  if (Test-Path -LiteralPath $aliasIdent) { Remove-Item -LiteralPath $aliasIdent -Force }
}
