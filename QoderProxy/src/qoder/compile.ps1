# QoderProxy v2.2 - Delphi 13.1 Compilation Script
# Use this script to compile outside the sandbox

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "QoderProxy v2.2 Compilation Script" -ForegroundColor Cyan
Write-Host "Using Delphi 13.1 (bcc64.exe)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$compilerPath = "D:\Program Files (x86)\Embarcadero\Studio\37.0\bin\bcc64.exe"
$projectFile = "QokerProxy.v2_2.dpr"
$outputDir = Split-Path $PWD -Parent

# Check compiler exists
if (!(Test-Path $compilerPath)) {
    Write-Host "ERROR: Compiler not found at: $compilerPath" -ForegroundColor Red
    exit 1
}
Write-Host "✅ Compiler found: $compilerPath" -ForegroundColor Green

# Change to project directory
Set-Location $outputDir
Write-Host "📁 Working directory: $(Get-Location)" -ForegroundColor Yellow

# Clean previous build artifacts
Write-Host "🧹 Cleaning old artifacts..." -ForegroundColor Yellow
Get-ChildItem -Path "." -Filter "*.dcu" | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path "." -Filter "*.obj" | Remove-Item -Force -ErrorAction SilentlyContinue  
Get-ChildItem -Path "." -Filter "*.exe" -Exclude "bcc64.exe" | Remove-Item -Force -ErrorAction SilentlyContinue

# Prepare include paths
$includePaths = @(
    (Get-Location).Path,
    "D:\_Progs\02Business\QoderProxy\node_modules",
    "D:\_Progs\02Business\QoderProxy\DeepBase\Source"
)

Write-Host "Include paths:" -ForegroundColor Yellow
$includePaths | ForEach-Object { Write-Host "  $_" }
Write-Host ""

# Compile
Write-Host "🔨 Starting compilation..." -ForegroundColor Cyan
Write-Host ""

try {
    & $compilerPath "-B$($includePaths -join ';')" $projectFile 2>&1 | ForEach-Object {
        $_ | Write-Host
    }
    
    if (LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "✅ COMPILATION SUCCESSFUL!" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        
        if (Test-Path $projectFile.Replace(".dpr", ".exe")) {
            $exeSize = (Get-Item ($projectFile.Replace(".dpr", ".exe"))).Length / 1MB
            Write-Host "Output: $($projectFile.Replace('.dpr', '.exe')) [$([math]::Round($exeSize, 2)) MB]" -ForegroundColor White
        }
        
        Write-Host ""
        Write-Host "You can now run: .\$($projectFile.Replace('.dpr', '.exe'))" -ForegroundColor Cyan
    } else {
        Write-Host ""
        Write-Host "❌ COMPILATION FAILED!" -ForegroundColor Red
        Write-Host "Exit code: $LASTEXITCODE" -ForegroundColor Red
    }
    
} catch {
    Write-Host ""
    Write-Host "💥 Compilation error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Press any key to continue..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
