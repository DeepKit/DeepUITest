$root = "d:\_Progs\02Business\DeepMoveC"
$backupRoot = "d:\_Progs\04bakcup\02Business\MoveC"
$files = Get-ChildItem $root -Filter "*.pas" -Recurse -File -ErrorAction SilentlyContinue
$fixed = 0
foreach ($f in $files) {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $hasDamage = $false
    for ($idx=0; $idx -lt ($bytes.Length - 3); $idx++) {
        if ($bytes[$idx] -eq 0xEF -and $bytes[$idx+1] -eq 0xBF -and $bytes[$idx+2] -eq 0xBD -and $bytes[$idx+3] -eq 0x3F) {
            $hasDamage = $true; break
        }
    }
    if (-not $hasDamage) { continue }
    $relPath = $f.FullName.Replace($root, "").TrimStart("\")
    $backupPath = "$backupRoot\$relPath"
    if (Test-Path $backupPath) {
        $backupBytes = [System.IO.File]::ReadAllBytes($backupPath)
        $newBytes = New-Object System.Collections.Generic.List[byte]
        $idx = 0
        while ($idx -lt $backupBytes.Length) {
            if ($idx + 3 -lt $backupBytes.Length -and $backupBytes[$idx] -eq 0xEF -and $backupBytes[$idx+1] -eq 0xBF -and $backupBytes[$idx+2] -eq 0xBD -and $backupBytes[$idx+3] -eq 0x3F) {
                $newBytes.Add(0xE7); $newBytes.Add(0x90); $newBytes.Add(0x86); $newBytes.Add(0x27); $idx += 4
            } else { $newBytes.Add($backupBytes[$idx]); $idx++ }
        }
        $text = [System.Text.Encoding]::UTF8.GetString($newBytes.ToArray())
        $text = $text.Replace("MoveC", "DeepMoveC")
        $enc = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllBytes($f.FullName, $enc.GetBytes($text))
        $fixed++
        Write-Host "Fixed: $($f.Name)"
    }
}
Write-Host "Total fixed: $fixed"
