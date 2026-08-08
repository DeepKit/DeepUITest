# DeepFlow MVP P0 - 金路径端到端演示编译运行脚本

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "DeepFlow MVP P0 Gold Path Demo - 编译与执行" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$BCC = 'D:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc32.exe'
$Source = 'Examples\Integration\DeepFlow.P0.GoldPathDemo.pas'
$Output = 'Examples\Integration\DeepFlow.P0.GoldPathDemo.exe'

Write-Host "[1/2] 编译 Delphi 程序..." -ForegroundColor Yellow

& $BCC "/S^1" "/M" "/N"".\" $Source

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ 编译失败！" -ForegroundColor Red
    Write-Host "请手动检查编译器错误。" -ForegroundColor Gray
    exit 1
}

Write-Host "✅ 编译成功：$Output" -ForegroundColor Green
Write-Host ""
Write-Host "[2/2] 启动金路径端到端演示..." -ForegroundColor Yellow

Start-Process -FilePath ".\$Output" -WorkingDirectory "Examples\Integration"
Write-Host ""
Write-Host "提示：等待演示完成后，检查 outputs/目录下的胶片文件" -ForegroundColor Gray
Write-Host ""
Read-Host "按 Enter 退出脚本窗口"
