<#
.SYNOPSIS
    Test script to verify GUI can load PowerShell modules
#>

Write-Host "Testing PowerShell module loading..." -ForegroundColor Cyan
Write-Host ""

# Test module path resolution
$exeDir = "C:\git\RiverRunThreatHunter\src\bin\Debug\net8.0-windows"
if (Test-Path $exeDir) {
    Write-Host "✓ Exe directory exists: $exeDir" -ForegroundColor Green
} else {
    Write-Host "✗ Exe directory not found: $exeDir" -ForegroundColor Red
}

# Test module loading
$modulePath = "C:\git\RiverRunThreatHunter\modules"
if (Test-Path $modulePath) {
    Write-Host "✓ Modules directory exists: $modulePath" -ForegroundColor Green
    
    # Test loading ThreatHuntConfig
    try {
        Import-Module "$modulePath\ThreatHuntConfig.psm1" -ErrorAction Stop
        Write-Host "✓ ThreatHuntConfig module loaded" -ForegroundColor Green
        
        # Test Initialize-ThreatHuntConfig
        Initialize-ThreatHuntConfig -ErrorAction Stop
        Write-Host "✓ ThreatHuntConfig initialized" -ForegroundColor Green
        
        # Test Get-AllClients
        $clients = Get-AllClients
        Write-Host "✓ Get-AllClients returned $($clients.Count) clients" -ForegroundColor Green
        
        if ($clients.Count -gt 0) {
            $clients | Format-Table ClientName, S1Platform, S1SiteId -AutoSize
        } else {
            Write-Host "⚠ No clients configured in ClientConfig.json" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "✗ Error loading modules: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host $_.Exception.StackTrace -ForegroundColor Gray
    }
} else {
    Write-Host "✗ Modules directory not found: $modulePath" -ForegroundColor Red
}

Write-Host ""
Write-Host "If modules load successfully, the GUI should work." -ForegroundColor Cyan
Write-Host "If not, check the error messages above." -ForegroundColor Yellow

