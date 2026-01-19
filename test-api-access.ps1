<#
.SYNOPSIS
    Tests API access for all configured platforms
.DESCRIPTION
    Attempts to connect to each platform and reports what access you have
#>

Write-Host "=== Testing API Access ===" -ForegroundColor Cyan
Write-Host ""

# Import modules
Import-Module .\modules\ConnectionManager.psm1 -ErrorAction SilentlyContinue
Import-Module .\modules\ThreatHuntConfig.psm1 -ErrorAction SilentlyContinue

# Test each platform
$platforms = @("ConnectWiseS1", "PerchSIEM")

foreach ($platform in $platforms) {
    Write-Host "Testing $platform..." -ForegroundColor Yellow
    
    # Check if token exists
    $configModule = Get-Module -Name "ThreatHuntConfig" -ListAvailable
    if (-not $configModule) {
        Import-Module (Join-Path $PSScriptRoot "modules\ThreatHuntConfig.psm1") -ErrorAction Stop
    }
    
    try {
        $platformConfig = Get-PlatformConfig -Platform $platform -ErrorAction Stop
        $tokenPath = Join-Path $env:USERPROFILE $platformConfig.TokenFile
        
        if (-not (Test-Path $tokenPath)) {
            Write-Host "  ⚠ Token not configured" -ForegroundColor Yellow
            Write-Host "     Run: Set-PlatformToken -Platform `"$platform`"" -ForegroundColor Gray
            continue
        }
        
        Write-Host "  ✓ Token file exists" -ForegroundColor Green
        
        # Try to get connection
        try {
            $conn = Get-PlatformConnection -Platform $platform -ErrorAction Stop
            Write-Host "  ✓ Connection object created" -ForegroundColor Green
            
            # Test API endpoint
            $testUri = switch ($conn.Type) {
                "SentinelOne" { "$($conn.BaseUri)/system/status" }
                "Perch"       { "$($conn.BaseUri)/health" }
            }
            
            Write-Host "  → Testing API endpoint: $testUri" -ForegroundColor Gray
            
            try {
                $response = Invoke-RestMethod -Uri $testUri -Headers $conn.Headers -Method Get -TimeoutSec 10 -ErrorAction Stop
                Write-Host "  ✓ API ACCESS CONFIRMED" -ForegroundColor Green
                Write-Host "     Access Level: $($conn.AccessLevel)" -ForegroundColor Gray
                
                # For SentinelOne, try to get sites to verify read access
                if ($conn.Type -eq "SentinelOne") {
                    try {
                        $sitesUri = "$($conn.BaseUri)/sites"
                        $sitesResponse = Invoke-RestMethod -Uri $sitesUri -Headers $conn.Headers -Method Get -TimeoutSec 10 -ErrorAction Stop
                        $siteCount = if ($sitesResponse.data) { $sitesResponse.data.Count } else { 0 }
                        Write-Host "     Sites accessible: $siteCount" -ForegroundColor Gray
                    }
                    catch {
                        Write-Host "     ⚠ Cannot read sites (may be account-level restriction)" -ForegroundColor Yellow
                    }
                }
            }
            catch {
                $errorMsg = $_.Exception.Message
                if ($errorMsg -like "*401*" -or $errorMsg -like "*403*" -or $errorMsg -like "*Unauthorized*") {
                    Write-Host "  ✗ ACCESS DENIED - Invalid token or no API access" -ForegroundColor Red
                    Write-Host "     Error: $errorMsg" -ForegroundColor Red
                    Write-Host ""
                    Write-Host "     Possible reasons:" -ForegroundColor Yellow
                    Write-Host "     - Token is invalid or expired" -ForegroundColor Gray
                    Write-Host "     - Your account doesn't have API access" -ForegroundColor Gray
                }
                elseif ($errorMsg -like "*404*") {
                    Write-Host "  ✗ ENDPOINT NOT FOUND - Check BaseUri in config" -ForegroundColor Red
                    Write-Host "     Error: $errorMsg" -ForegroundColor Red
                }
                else {
                    Write-Host "  ✗ CONNECTION FAILED" -ForegroundColor Red
                    Write-Host "     Error: $errorMsg" -ForegroundColor Red
                }
            }
        }
        catch {
            Write-Host "  ✗ Failed to create connection: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "  ✗ Platform not configured: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    Write-Host ""
}

Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "All configured platforms tested!" -ForegroundColor Green
Write-Host ""

