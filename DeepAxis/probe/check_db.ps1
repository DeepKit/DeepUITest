$db = 'D:\Temp\message_0_copy.db'
$bytes = [IO.File]::ReadAllBytes($db)
$len = [Math]::Min(64, $bytes.Length)
Write-Host "File size: $($bytes.Length)"
Write-Host "First $len hex bytes:"
for ($i = 0; $i -lt $len; $i++) {
    $hex = '{0:X2}' -f $bytes[$i]
    Write-Host -NoNewline "$hex "
    if (($i + 1) % 16 -eq 0) { Write-Host "" }
}
Write-Host ""
Write-Host "Header string: " -NoNewline
for ($i = 0; $i -lt 16; $i++) {
    $c = $bytes[$i]
    if ($c -ge 32 -and $c -le 126) {
        Write-Host -NoNewline ([char]$c)
    } else {
        Write-Host -NoNewline "."
    }
}
