# G2 batch compile retry: only DeepCompare/DeepCompareDebug with -I for SynEdit
# (matches compile_all.bat working invocation)

$ErrorActionPreference = 'Continue'
$DCC = 'D:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe'
$DB  = 'd:\_Progs\02Business\DeepBase'
$OUT = 'd:\_Progs\02Business\.kiro\specs\aierrorhandler-rollout\exec-log\_g2_compile'
$SYNEDIT_M = 'd:\ProgramData\delphi\SynEdit-master\Source'
$SYNEDIT = 'd:\Personal\Documents\Embarcadero\Studio\23.0\CatalogRepository\SynEdit-12\Source'
$SKIA = 'd:\ProgramData\delphi\Skia4Delphi'
$VTV = 'd:\ProgramData\delphi\VirtualTreeView-master'
$WV = 'd:\ProgramData\delphi\WebView4Delphi\source'

$DC = 'd:\_Progs\02Business\DeepCompare\delphi'
$dcUnits = "$DC\Core;$DC\DeepCompare;$DC\DeepCompareU;" +
           "$DB\Core;$DB\VCL;$DB\Persistence;$DB\Features;$DB\Governance;" +
           "$SKIA;$SYNEDIT;$SYNEDIT\Highlighters;$VTV;$WV"

function CompileWithI($name, $dpr, $unitPath) {
  $log = Join-Path $OUT "$name.log"
  Write-Host "=== Compiling $name (with -I) ==="
  & $DCC "-E$OUT" "-U$unitPath" "-I$SYNEDIT_M;$SYNEDIT" `
         "-NSSystem;Vcl;Winapi;System.Win;Data;Xml;Soap;Web" `
         $dpr *> $log
  Write-Host "ExitCode: $LASTEXITCODE"
}

CompileWithI 'DeepCompare' "$DC\DeepCompare.dpr" $dcUnits
CompileWithI 'DeepCompareDebug' "$DC\DeepCompareDebug.dpr" $dcUnits
