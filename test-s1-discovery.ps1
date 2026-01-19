# Test script for SentinelOne site discovery
# Run this directly to diagnose why Get-S1Sites might return empty results

Write-Host "=== SentinelOne Discovery Test ===" -ForegroundColor Cyan
Write-Host ""

# Get script directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$modulesPath = Join-Path $scriptDir "modules"

Write-Host "Script directory: $scriptDir" -ForegroundColor Gray
Write-Host "Modules path: $modulesPath" -ForegroundColor Gray
Write-Host ""

# Import required modules
Write-Host "Importing modules..." -ForegroundColor Yellow
try {
    Import-Module (Join-Path $modulesPath "ConnectionManager.psm1") -Force -ErrorAction Stop
    Write-Host "  ✓ ConnectionManager imported" -ForegroundColor Green
    
    Import-Module (Join-Path $modulesPath "ThreatHuntConfig.psm1") -Force -ErrorAction Stop
    Write-Host "  ✓ ThreatHuntConfig imported" -ForegroundColor Green
    
    Import-Module (Join-Path $modulesPath "SentinelOneHunter.psm1") -Force -ErrorAction Stop
    Write-Host "  ✓ SentinelOneHunter imported" -ForegroundColor Green
}
catch {
    Write-Host "  ✗ Failed to import modules: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Initialize config
Write-Host "Initializing ThreatHuntConfig..." -ForegroundColor Yellow
try {
    Initialize-ThreatHuntConfig -ErrorAction Stop
    Write-Host "  ✓ Config initialized" -ForegroundColor Green
}
catch {
    Write-Host "  ⚠ Config initialization warning: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "    (This is OK - connection might still work)" -ForegroundColor Gray
}

Write-Host ""

# Get connection
Write-Host "Getting platform connection..." -ForegroundColor Yellow
try {
    $conn = Get-PlatformConnection -Platform "ConnectWiseS1" -ErrorAction Stop
    
    if (-not $conn) {
        Write-Host "  ✗ Connection is null" -ForegroundColor Red
        Write-Host "    Check your token file: .s1token_connectwise" -ForegroundColor Yellow
        exit 1
    }
    
    Write-Host "  ✓ Connection object created" -ForegroundColor Green
    
    # Display connection details
    Write-Host ""
    Write-Host "Connection Details:" -ForegroundColor Cyan
    Write-Host "  BaseUri: $($conn.BaseUri)" -ForegroundColor White
    
    if ($conn.Headers) {
        Write-Host "  Headers:" -ForegroundColor White
        foreach ($key in $conn.Headers.Keys) {
            if ($key -eq "Authorization") {
                $authValue = $conn.Headers[$key]
                if ($authValue -like "Bearer *") {
                    $tokenPreview = $authValue.Substring(0, [Math]::Min(20, $authValue.Length)) + "..."
                    Write-Host "    $key : $tokenPreview" -ForegroundColor Gray
                }
                else {
                    Write-Host "    $key : [hidden]" -ForegroundColor Gray
                }
            }
            else {
                Write-Host "    $key : $($conn.Headers[$key])" -ForegroundColor Gray
            }
        }
    }
    else {
        Write-Host "  ⚠ No headers found in connection object" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "  ✗ Failed to get connection: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "    Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Gray
    exit 1
}

Write-Host ""

# Test API call
Write-Host "Calling Get-S1Sites..." -ForegroundColor Yellow
try {
    $sites = Get-S1Sites -Connection $conn -ErrorAction Stop
    
    Write-Host ""
    if ($null -eq $sites) {
        Write-Host "  ⚠ Get-S1Sites returned NULL" -ForegroundColor Yellow
    }
    elseif ($sites.Count -eq 0) {
        Write-Host "  ⚠ Get-S1Sites returned EMPTY ARRAY (0 sites)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Possible reasons:" -ForegroundColor Cyan
        Write-Host "  1. Your API token doesn't have access to any sites" -ForegroundColor Gray
        Write-Host "  2. The API endpoint structure has changed" -ForegroundColor Gray
        Write-Host "  3. The account has no sites configured" -ForegroundColor Gray
        Write-Host "  4. There's a pagination issue" -ForegroundColor Gray
    }
    else {
        Write-Host "  ✓ Found $($sites.Count) sites" -ForegroundColor Green
        Write-Host ""
        Write-Host "First 5 sites:" -ForegroundColor Cyan
        $sites | Select-Object -First 5 | Format-Table SiteId, SiteName, TotalAgents, ActiveAgents -AutoSize
    }
    
    Write-Host ""
    Write-Host "Raw JSON output:" -ForegroundColor Cyan
    $sites | ConvertTo-Json -Depth 10 | Write-Host
    
    Write-Host ""
    Write-Host "=== Test Complete ===" -ForegroundColor Green
}
catch {
    Write-Host "  ✗ Get-S1Sites failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "    Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Gray
    exit 1
}

