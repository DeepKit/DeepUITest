Get-Process Weixin -ErrorAction SilentlyContinue | ForEach-Object {
    $proc = $_
    $proc.Modules | Where-Object {
        $_.Size -gt 1048576  # > 1MB
    } | Sort-Object Size -Descending | Select-Object -First 30 @{N='PID';E={$proc.Id}}, ModuleName, @{N='BaseAddr';E={'0x{0:X}' -f $_.BaseAddress.ToInt64()}}, @{N='SizeKB';E={[math]::Round($_.Size/1KB,0)}} | Format-Table -AutoSize
}
