<#
.SYNOPSIS
    Quick launcher script for RiverRunThreatHunter
.DESCRIPTION
    Launches the WPF GUI application or opens PowerShell with modules loaded
.PARAMETER Mode
    Launch mode: GUI (default) or PowerShell
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("GUI", "PowerShell")]
    [string]$Mode = "GUI"
)

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptPath

if ($Mode -eq "PowerShell") {
    Write-Host "Loading PowerShell modules..." -ForegroundColor Cyan
    Write-Host "Available modules:" -ForegroundColor Yellow
    
    Get-ChildItem -Path "modules\*.psm1" | ForEach-Object {
        Write-Host "  - $($_.BaseName)" -ForegroundColor Gray
        Import-Module $_.FullName -ErrorAction SilentlyContinue
    }
    
    Write-Host "`nModules loaded! Try:" -ForegroundColor Green
    Write-Host "  Initialize-ThreatHuntConfig" -ForegroundColor Yellow
    Write-Host "  Test-AllConnections" -ForegroundColor Yellow
    Write-Host "  Get-AllClients" -ForegroundColor Yellow
}
else {
    Write-Host "Building and launching WPF GUI..." -ForegroundColor Cyan
    
    # Check if .NET SDK is available
    $dotnetVersion = & dotnet --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: .NET SDK not found. Please install .NET 6.0 or later." -ForegroundColor Red
        Write-Host "Download from: https://dotnet.microsoft.com/download" -ForegroundColor Yellow
        exit 1
    }
    
    Write-Host "Found .NET SDK version: $dotnetVersion" -ForegroundColor Green
    
    # Build and run
    Push-Location "src"
    try {
        Write-Host "Restoring packages..." -ForegroundColor Cyan
        & dotnet restore
        
        Write-Host "Building application..." -ForegroundColor Cyan
        & dotnet build
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Launching GUI..." -ForegroundColor Green
            & dotnet run
        }
        else {
            Write-Host "Build failed. Check errors above." -ForegroundColor Red
        }
    }
    finally {
        Pop-Location
    }
}

