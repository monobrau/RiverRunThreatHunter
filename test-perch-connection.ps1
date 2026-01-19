<#
.SYNOPSIS
    Tests Perch OAuth2 connection specifically
#>

Write-Host "=== Testing Perch OAuth2 Connection ===" -ForegroundColor Cyan
Write-Host ""

Import-Module .\modules\ConnectionManager.psm1 -Force -ErrorAction Stop
Import-Module .\modules\ThreatHuntConfig.psm1 -Force -ErrorAction Stop
Import-Module .\modules\PerchHunter.psm1 -Force -ErrorAction SilentlyContinue

try {
    Write-Host "Getting Perch connection..." -ForegroundColor Yellow
    $conn = Get-PlatformConnection -Platform "PerchSIEM"
    Write-Host "✓ Connection object created" -ForegroundColor Green
    Write-Host "  BaseUri: $($conn.BaseUri)" -ForegroundColor Gray
    Write-Host "  Auth Header Present: $($conn.Headers.ContainsKey('Authorization'))" -ForegroundColor Gray
    
    Write-Host ""
    Write-Host "Testing OAuth2 token generation..." -ForegroundColor Yellow
    
    # Check if we have credentials
    $clientIdPath = Join-Path $env:USERPROFILE ".perch_clientid"
    $clientSecretPath = Join-Path $env:USERPROFILE ".perch_clientsecret"
    
    if (-not (Test-Path $clientIdPath) -or -not (Test-Path $clientSecretPath)) {
        Write-Host "✗ OAuth2 credentials not found!" -ForegroundColor Red
        Write-Host "  Run: Set-PerchOAuth2Credentials" -ForegroundColor Yellow
        exit 1
    }
    
    Write-Host "✓ OAuth2 credentials found" -ForegroundColor Green
    
    # Try to get a token
    $platformConfig = Get-PlatformConfig -Platform "PerchSIEM"
    $clientIdSecure = Get-Content $clientIdPath | ConvertTo-SecureString
    $clientId = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($clientIdSecure)
    )
    $clientSecretSecure = Get-Content $clientSecretPath | ConvertTo-SecureString
    $clientSecret = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($clientSecretSecure)
    )
    
    Write-Host ""
    Write-Host "Attempting OAuth2 token exchange..." -ForegroundColor Yellow
    Write-Host "  Token URI: $($platformConfig.BaseUri -replace '/v1$', '/auth/access_token')" -ForegroundColor Gray
    
    try {
        $accessToken = Get-PerchAccessToken -ClientId $clientId -ClientSecret $clientSecret -BaseUri $platformConfig.BaseUri
        Write-Host "✓ OAuth2 access token obtained!" -ForegroundColor Green
        Write-Host "  Token (first 20 chars): $($accessToken.Substring(0, [Math]::Min(20, $accessToken.Length)))..." -ForegroundColor Gray
    }
    catch {
        Write-Host "✗ Failed to get OAuth2 token: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        Write-Host "Possible issues:" -ForegroundColor Yellow
        Write-Host "  - OAuth2 endpoint path might be different" -ForegroundColor Gray
        Write-Host "  - Client ID or Secret might be incorrect" -ForegroundColor Gray
        Write-Host "  - Network connectivity issue" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Try checking:" -ForegroundColor Yellow
        Write-Host "  - Perch API documentation for correct OAuth2 endpoint" -ForegroundColor Gray
        Write-Host "  - Your Perch instance URL in ClientConfig.json" -ForegroundColor Gray
        exit 1
    }
    
    Write-Host ""
    Write-Host "Testing API call with token..." -ForegroundColor Yellow
    
    # Try a simple API call
    $testTeam = Read-Host "Enter a Team ID to test (or press Enter to skip)"
    if ($testTeam) {
        try {
            $results = Search-PerchLogs -Connection $conn -Query "*" -TeamId $testTeam -Limit 1
            Write-Host "✓ Perch API query successful!" -ForegroundColor Green
            Write-Host "  Results returned: $($results.Count)" -ForegroundColor Gray
        }
        catch {
            Write-Host "⚠ Query failed: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "  But OAuth2 authentication worked!" -ForegroundColor Green
        }
    }
    else {
        Write-Host "⊘ Skipped API query test (no Team ID provided)" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "=== Perch Connection Test Complete ===" -ForegroundColor Green
}
catch {
    Write-Host "✗ Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
}

