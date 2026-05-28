param([string]$Path, [string]$AnchorAfter, [string]$Insert)
# Reads file as raw bytes, finds the ASCII anchor (terminated by \r\n or \n),
# inserts the supplied (ASCII) string + line terminator AFTER that line,
# writes back as raw bytes (preserves any non-UTF8 trailing region).
$bytes = [System.IO.File]::ReadAllBytes($Path)
$anchorBytes = [System.Text.Encoding]::ASCII.GetBytes($AnchorAfter)
# Search for anchor bytes
$pos = -1
for ($i = 0; $i -le $bytes.Length - $anchorBytes.Length; $i++) {
  $match = $true
  for ($j = 0; $j -lt $anchorBytes.Length; $j++) {
    if ($bytes[$i + $j] -ne $anchorBytes[$j]) { $match = $false; break }
  }
  if ($match) { $pos = $i; break }
}
if ($pos -lt 0) { throw "Anchor not found in $Path" }
# Find end of line after anchor
$end = $pos + $anchorBytes.Length
while ($end -lt $bytes.Length -and $bytes[$end] -ne 0x0A) { $end++ }
if ($end -lt $bytes.Length) { $end++ }  # consume the \n
# Determine line terminator: \r\n or \n
$useCrLf = ($end -ge 2 -and $bytes[$end-2] -eq 0x0D)
$lineSep = if ($useCrLf) { "`r`n" } else { "`n" }
$insertBytes = [System.Text.Encoding]::ASCII.GetBytes($Insert + $lineSep)
$out = New-Object byte[] ($bytes.Length + $insertBytes.Length)
[Array]::Copy($bytes, 0, $out, 0, $end)
[Array]::Copy($insertBytes, 0, $out, $end, $insertBytes.Length)
[Array]::Copy($bytes, $end, $out, $end + $insertBytes.Length, $bytes.Length - $end)
[System.IO.File]::WriteAllBytes($Path, $out)
Write-Output "Inserted $($insertBytes.Length) bytes after byte $end in $Path"
