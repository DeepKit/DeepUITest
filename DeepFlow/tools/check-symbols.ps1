$lines = Get-Content 'C:\Users\Administrator\.qoder\cache\projects\DeepFlow-4b054eeb\conversation-history\cde5cdf9\cde5cdf9.jsonl'
$found = $lines | Select-String -Pattern 'dcc32'
$found | Select-Object -First 3 | ForEach-Object {
  $line = $_.Line
  if ($line.Length -gt 3500) { $line = $line.Substring(0, 3500) }
  Write-Host '===MATCH==='
  Write-Host $line
}
