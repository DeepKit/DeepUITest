# G2 batch compile script for AIErrorHandler rollout
# Generated 2026-05-16

$ErrorActionPreference = 'Continue'
$DCC = 'D:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe'
$DB  = 'd:\_Progs\02Business\DeepBase'
$OUT = 'd:\_Progs\02Business\.kiro\specs\aierrorhandler-rollout\exec-log\_g2_compile'
$SYNEDIT = 'd:\Personal\Documents\Embarcadero\Studio\23.0\CatalogRepository\SynEdit-12\Source'
$SYNEDIT_HL = "$SYNEDIT\Highlighters"
$SKIA = 'd:\ProgramData\delphi\Skia4Delphi'
$VTV = 'd:\ProgramData\delphi\VirtualTreeView-master'
$WV = 'd:\ProgramData\delphi\WebView4Delphi\source'

New-Item -ItemType Directory -Force -Path $OUT | Out-Null

$results = @()

function Compile-Dpr($name, $dpr, $unitPath, $extraNS = '') {
  $log = Join-Path $OUT "$name.log"
  $ns = "System;Vcl;Winapi;System.Win;Data;Xml;Soap;Web"
  if ($extraNS) { $ns = "$ns;$extraNS" }
  Write-Host "=== Compiling $name ==="
  & $DCC "-E$OUT" "-U$unitPath" "-NS$ns" $dpr *> $log
  $code = $LASTEXITCODE
  Write-Host "ExitCode: $code"
  return @{ Name = $name; Dpr = $dpr; ExitCode = $code; Log = $log }
}

# 1. DeepLLMProxy (AssayerProxy console)
$ASSAYER = 'd:\_Progs\02Business\Assayer\src'
$results += Compile-Dpr 'DeepLLMProxy' "$ASSAYER\DeepLLMProxy.dpr" `
  "$DB\Core;$DB\VCL;$DB\Persistence;$DB\Features;$DB\Governance;$DB\FMX;$ASSAYER;$ASSAYER\core\quality;$ASSAYER\core\security;$ASSAYER\core\proxy"

# 3. DeepCharset (VCL GUI)
$DCS = 'd:\_Progs\02Business\DeepCharset'
$results += Compile-Dpr 'DeepCharset' "$DCS\DeepCharset.dpr" `
  "$DB\Core;$DB\VCL;$DB\Persistence;$DB\Features;$DB\Governance;$DCS;$SYNEDIT;$SYNEDIT_HL"

# 4. DeepClip (VCL GUI)
$DCLIP = 'd:\_Progs\02Business\DeepClip'
$dclipUnits = "$DB\Core;$DB\VCL;$DB\Persistence;$DB\Features;$DB\Governance;" +
              "$DCLIP\src\App;$DCLIP\src\UI;$DCLIP\src\Storage;$DCLIP\src\Core;" +
              "$DCLIP\src\AI;$DCLIP\src\Capture;$DCLIP\src\Commerce;$DCLIP\src\Privacy;$DCLIP\src\Voice;" +
              "$SYNEDIT;$SYNEDIT_HL;$SKIA;$VTV"
$results += Compile-Dpr 'DeepClip' "$DCLIP\DeepClip.dpr" $dclipUnits

# 5. DeepClipLite (VCL GUI)
$results += Compile-Dpr 'DeepClipLite' "$DCLIP\DeepClipLite.dpr" $dclipUnits

# 6. DeepCompare (VCL GUI w/ WebView4Delphi + Skia + SynEdit + VTV)
$DC = 'd:\_Progs\02Business\DeepCompare\delphi'
$dcUnits = "$DC\Core;$DC\DeepCompare;$DC\DeepCompareU;" +
           "$DB\Core;$DB\VCL;$DB\Persistence;$DB\Features;$DB\Governance;" +
           "$SKIA;$SYNEDIT;$SYNEDIT_HL;$VTV;$WV"
$results += Compile-Dpr 'DeepCompare' "$DC\DeepCompare.dpr" $dcUnits

# 7. DeepCompareDebug
$results += Compile-Dpr 'DeepCompareDebug' "$DC\DeepCompareDebug.dpr" $dcUnits

# 8. DeepCompareU
$results += Compile-Dpr 'DeepCompareU' "$DC\DeepCompareU.dpr" $dcUnits

# Summary
$summary = Join-Path $OUT '_summary.txt'
$results | ForEach-Object {
  "{0,-20}  ExitCode={1}  log={2}" -f $_.Name, $_.ExitCode, $_.Log
} | Set-Content $summary
Write-Host "`n=== SUMMARY ==="
Get-Content $summary
