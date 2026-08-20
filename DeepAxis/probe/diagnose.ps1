$proc = Get-Process Weixin | Select-Object -First 1
Write-Host "PID: $($proc.Id)"
Write-Host ""

# Scan Weixin.dll specifically for 32-byte sequences in writable sections only
$mod = $proc.Modules | Where-Object {$_.ModuleName -eq 'Weixin.dll'} | Select-Object -First 1
Write-Host "Weixin.dll: $($mod.FileName)"
Write-Host "Size: $([math]::Round($mod.Size/1MB,0)) MB"

# WeChat 4.x - key may be stored differently. Check all DLLs > 1MB
Write-Host ""
Write-Host "All DLLs > 5MB:"
$proc.Modules | Where-Object {$_.Size -gt 5242880} | Sort-Object Size -Descending | Select-Object -First 15 | ForEach-Object {
    $mb = '{0,5:F0}' -f ($_.Size/1MB)
    $addr = '0x{0:X}' -f $_.BaseAddress.ToInt64()
    Write-Host "  $mb MB  $addr  $($_.ModuleName)"
}

# Check if WeChat 4.x has SQLCipher .dll in program dir
Write-Host ""
Write-Host "Files in Weixin install dir:"
Get-ChildItem "D:\Program Files\Tencent\Weixin" -Filter "*.dll" | Where-Object {$_.Length -gt 1MB} | Sort-Object Length -Descending | Select-Object -First 20 | ForEach-Object {
    $mb = '{0,5:F1}' -f ($_.Length/1MB)
    Write-Host "  $mb MB  $($_.Name)"
}

# Check DB encryption - is it even SQLCipher?
Write-Host ""
Write-Host "First 64 bytes of message_0.db (hex):"
$bytes = [System.IO.File]::ReadAllBytes("D:\xwechat_files\wxid_swkc1c57428i21_b5a0\db_storage\message\message_0.db")
$hex = [System.BitConverter]::ToString($bytes[0..63]) -replace '-',' '
Write-Host "  $hex"

# Check if starts with "SQLite format 3"
$header = [System.Text.Encoding]::ASCII.GetString($bytes[0..15])
Write-Host "  Header: '$header'"

# Check page size (SQLCipher stores it at offset 16)
$pageSize = [System.BitConverter]::ToInt16($bytes, 16)
Write-Host "  Page size (offset 16): $pageSize"
if ($pageSize -gt 0 -and $pageSize -le 65536) {
    Write-Host "  File size: $((Get-Item 'D:\xwechat_files\wxid_swkc1c57428i21_b5a0\db_storage\message\message_0.db').Length) bytes"
    Write-Host "  Pages: $( [math]::Floor((Get-Item 'D:\xwechat_files\wxid_swkc1c57428i21_b5a0\db_storage\message\message_0.db').Length / $pageSize) )"
}
