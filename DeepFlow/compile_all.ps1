# 完整编译 DeepFlow 所有单元（PowerShell 版 compile_all.cmd）
# 读取 build.rsp 中的 -U 搜索路径，逐个编译 compile_all.cmd 中列出的 .pas 文件
$ErrorActionPreference = "Continue"
Set-Location "d:\_Progs\02Business\DeepFlow"

$dcc = "D:\Program Files (x86)\Embarcadero\Studio\37.0\bin\Dcc64.exe"
if (-not (Test-Path $dcc)) { Write-Host "DCC64 not found: $dcc"; exit 1 }

# 读取 build.rsp 参数
$rspLines = Get-Content build.rsp
$unitPath = $null
foreach ($line in $rspLines) {
    if ($line -match '^-U"(.+)"$') { $unitPath = $Matches[1] }
}
if (-not $unitPath) { Write-Host "build.rsp has no -U path"; exit 1 }
Write-Host "Unit path: $unitPath"

# 收集要编译的文件
$files = Get-Content compile_all.cmd | Where-Object { $_ -match '^\s*Source\\.*\.pas\s*$' } | ForEach-Object { $_.Trim() }
Write-Host "Files to compile: $($files.Count)"

$logFile = "compile_all_out.txt"
Remove-Item $logFile -ErrorAction SilentlyContinue

$okCount = 0
$failCount = 0
$failList = @()

foreach ($f in $files) {
    $out = & $dcc "-NU`"d:\_Progs\02Business\DeepFlow\BuildOutput\dcu64`"" "-U`"$unitPath`"" $f 2>&1
    $out | Add-Content $logFile
    $hasError = $out | Where-Object { $_ -match "Error:" } | Select-Object -First 1
    if ($hasError) {
        $failCount++
        $failList += $f
        Write-Host "FAIL: $f"
    } else {
        $okCount++
        Write-Host "OK:   $f"
    }
}

Write-Host ""
Write-Host "=== Summary: OK=$okCount FAIL=$failCount Total=$($files.Count) ==="
if ($failList.Count -gt 0) {
    Write-Host "Failed files:"
    $failList | ForEach-Object { Write-Host "  $_" }
}
if ($failCount -gt 0) { exit 1 } else { exit 0 }
