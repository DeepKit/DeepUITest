$root = 'D:\_Progs\02Business\DeepBase'
$files = Get-ChildItem -Path $root -Recurse -Filter *.pas | Where-Object { $_.FullName -notmatch '\\__history\\|\\backup\\' }
$total = 0
foreach ($f in $files) {
  $lines = [System.IO.File]::ReadAllLines($f.FullName)
  for ($i = 0; $i -lt $lines.Length; $i++) {
    $L = $lines[$i]
    if (($L -match ':=\s+if\s+.+\s+then\s') -or ($L -match ',\s*if\s+.+\s+then\s.*\s+else')) {
      $total++
      Write-Output ("[{0}:{1}] {2}" -f $f.FullName.Substring($root.Length + 1), ($i+1), $L.Trim())
    }
  }
}
Write-Output "Total: $total"
