Get-Process Weixin -ErrorAction SilentlyContinue | ForEach-Object {
    $proc = $_
    $proc.Modules | Where-Object {
        $_.ModuleName -match 'WeChatWin|wrapper|mmmojo|WeMail|wmpf|Qt|browser'
    } | Select-Object @{N='PID';E={$proc.Id}}, ModuleName, @{N='BaseAddr';E={'0x{0:X}' -f $_.BaseAddress.ToInt64()}}, @{N='SizeKB';E={[math]::Round($_.Size/1KB,0)}} | Format-Table -AutoSize
}
