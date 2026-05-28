# G3 batch compile script for AIErrorHandler rollout
# Generated 2026-05-17

$ErrorActionPreference = 'Continue'
$DCC = 'D:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe'
$DB  = 'd:\_Progs\02Business\DeepBase'
$OUT = 'd:\_Progs\02Business\.kiro\specs\aierrorhandler-rollout\exec-log\_g3_compile'
$SYNEDIT = 'd:\Personal\Documents\Embarcadero\Studio\23.0\CatalogRepository\SynEdit-12\Source'
$SYNEDIT_HL = "$SYNEDIT\Highlighters"
$SYNEDIT_M  = 'd:\ProgramData\delphi\SynEdit-master\Source'
$SKIA = 'd:\ProgramData\delphi\Skia4Delphi'
$VTV = 'd:\ProgramData\delphi\VirtualTreeView-master'
$WV = 'd:\ProgramData\delphi\WebView4Delphi\source'

New-Item -ItemType Directory -Force -Path $OUT | Out-Null

$results = @()

function Compile-Dpr($name, $dpr, $unitPath, $incPath = '') {
  $log = Join-Path $OUT "$name.log"
  $ns = "System;Vcl;Winapi;System.Win;Data;Xml;Soap;Web"
  Write-Host "=== Compiling $name ==="
  if ($incPath) {
    & $DCC "-E$OUT" "-U$unitPath" "-I$incPath" "-NS$ns" $dpr *> $log
  } else {
    & $DCC "-E$OUT" "-U$unitPath" "-NS$ns" $dpr *> $log
  }
  $code = $LASTEXITCODE
  Write-Host "ExitCode: $code"
  return @{ Name = $name; Dpr = $dpr; ExitCode = $code; Log = $log }
}

# 1, 2. ZhihuPoster / ZhihuPosterPro (DeepCompare\delphi)
$DC = 'd:\_Progs\02Business\DeepCompare\delphi'
$dcUnits = "$DC\Core;$DC\DeepCompare;$DC\DeepCompareU;" +
           "$DB\Core;$DB\VCL;$DB\Persistence;$DB\Features;$DB\Governance;" +
           "$SKIA;$SYNEDIT;$SYNEDIT_HL;$VTV;$WV"
$results += Compile-Dpr 'ZhihuPoster'    "$DC\ZhihuPoster.dpr"    $dcUnits $SYNEDIT_M
$results += Compile-Dpr 'ZhihuPosterPro' "$DC\ZhihuPosterPro.dpr" $dcUnits $SYNEDIT_M

# 3..7. DeepConfig family (single-dir VCL programs / console tools)
$DCFG = 'd:\_Progs\02Business\DeepConfig'
$dcfgUnits = "$DCFG;$DB\Core;$DB\VCL;$DB\Persistence;$DB\Features;$DB\Governance"
$results += Compile-Dpr 'ConfigEditor'        "$DCFG\ConfigEditor.dpr"        $dcfgUnits
$results += Compile-Dpr 'ConvertFilesToUTF8'  "$DCFG\ConvertFilesToUTF8.dpr"  $dcfgUnits
$results += Compile-Dpr 'DeepConfig'          "$DCFG\DeepConfig.dpr"          $dcfgUnits
$results += Compile-Dpr 'FixAccess'           "$DCFG\FixAccess.dpr"           $dcfgUnits

# 8. DeepInput (VCL GUI: DeepBase Core/VCL/Persistence/Features + Skia + SynEdit + VTV)
$DI = 'd:\_Progs\02Business\DeepInput'
$diUnits = "$DI\src;$DB\Core;$DB\VCL;$DB\Persistence;$DB\Features;$DB\Governance;" +
           "$SKIA;$SYNEDIT;$SYNEDIT_HL;$VTV"
$results += Compile-Dpr 'DeepInput' "$DI\src\DeepInput.dpr" $diUnits

# Summary
$summary = Join-Path $OUT '_summary.txt'
$results | ForEach-Object {
  "{0,-22}  ExitCode={1}  log={2}" -f $_.Name, $_.ExitCode, $_.Log
} | Set-Content $summary
Write-Host "`n=== SUMMARY ==="
Get-Content $summary
