<#
.SYNOPSIS
    Quick setup script for Perch OAuth2 credentials
.DESCRIPTION
    Sets up Perch OAuth2 Client ID and Secret for API access
#>

Write-Host "=== Perch OAuth2 Setup ===" -ForegroundColor Cyan
Write-Host ""

# Import module and handle errors
try {
    Import-Module .\modules\ConnectionManager.psm1 -Force -ErrorAction Stop
}
catch {
    Write-Host "ERROR: Failed to import ConnectionManager module: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "The module may have syntax errors. Please check the file." -ForegroundColor Yellow
    exit 1
}

# Verify function exists
if (-not (Get-Command Set-PerchOAuth2Credentials -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Set-PerchOAuth2Credentials function not found!" -ForegroundColor Red
    Write-Host "The module may not have loaded correctly." -ForegroundColor Yellow
    exit 1
}

Write-Host "Perch uses OAuth2 authentication with Client ID and Client Secret." -ForegroundColor Yellow
Write-Host ""

$clientId = Read-Host "Enter Perch Client ID"
$clientSecret = Read-Host "Enter Perch Client Secret" -AsSecureString

# Convert secure string to plain text for the function
$clientSecretPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($clientSecret)
)

Set-PerchOAuth2Credentials -ClientId $clientId -ClientSecret $clientSecretPlain

Write-Host ""
Write-Host "Testing Perch connection..." -ForegroundColor Cyan

try {
    $conn = Get-PlatformConnection -Platform "PerchSIEM"
    Write-Host "✓ Perch OAuth2 credentials configured successfully" -ForegroundColor Green
    
    # Try a test query if we have a team ID
    Write-Host ""
    $testTeam = Read-Host "Enter a Team ID to test (or press Enter to skip)"
    if ($testTeam) {
        Write-Host "Testing query..." -ForegroundColor Gray
        Import-Module .\modules\PerchHunter.psm1 -ErrorAction SilentlyContinue
        $testResults = Search-PerchLogs -Connection $conn -Query "*" -TeamId $testTeam -Limit 1
        Write-Host "✓ Perch API is working!" -ForegroundColor Green
    }
}
catch {
    Write-Host "✗ Connection test failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please verify:" -ForegroundColor Yellow
    Write-Host "  - Client ID and Secret are correct" -ForegroundColor Gray
    Write-Host "  - BaseUri in ClientConfig.json is correct" -ForegroundColor Gray
    Write-Host "  - Your network can reach the Perch API" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Setup complete!" -ForegroundColor Green

