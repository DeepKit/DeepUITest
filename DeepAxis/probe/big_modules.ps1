$proc = Get-Process Weixin | Select-Object -First 1
Write-Host "PID: $($proc.Id)  Path: $($proc.Path)"
Write-Host "Total modules: $($proc.Modules.Count)"
Write-Host ""

# List top 30 by module size
$proc.Modules | Sort-Object {$_.ModuleMemorySize} -Descending | Select-Object -First 30 | ForEach-Object {
    $mb = '{0,6:F1}' -f ($_.ModuleMemorySize / 1MB)
    $addr = '0x{0:X}' -f $_.BaseAddress.ToInt64()
    $name = $_.ModuleName.PadRight(40)
    Write-Host "  $mb MB  $addr  $name"
}
