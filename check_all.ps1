# Check compilation logs
$logs = @(
    'd:\_Progs\02Business\compile_dbtray_cd.txt',
    'd:\_Progs\02Business\compile_dbrun3.txt', 
    'd:\_Progs\02Business\compile_dc3.txt',
    'd:\_Progs\02Business\compile_cli_final.txt'
)
foreach ($log in $logs) {
    if (Test-Path $log) {
        $size = (Get-Item $log).Length
        Write-Output "$(Split-Path $log -Leaf): size=$size"
        if ($size -gt 0) { Get-Content $log | Select-Object -Last 3 }
    } else {
        Write-Output "$(Split-Path $log -Leaf): NOT FOUND"
    }
    Write-Output "---"
}

# Check executables
Write-Output "EXE CHECK:"
Write-Output "DeepBase.exe:$(Test-Path 'd:\_Progs\02Business\DeepBase\Tools\CLI\bin\DeepBase.exe')"
Write-Output "DeepBaseRun.exe:$(Test-Path 'd:\_Progs\02Business\DeepBase\DeepBaseRun\bin\DeepBaseRun.exe')"
Write-Output "DeepBaseTray.exe:$(Test-Path 'd:\_Progs\02Business\DeepBase\Tools\Tray\bin\DeepBaseTray.exe')"
Write-Output "DeepCompare.exe:$(Test-Path 'd:\_Progs\02Business\DeepCompare\delphi\bin\DeepCompare.exe')"
Write-Output "DeepInput.exe:$(Test-Path 'd:\_Progs\02Business\DeepInput\bin\DeepInput.exe')"
