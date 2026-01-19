<#
.SYNOPSIS
    Standalone script to set Perch OAuth2 credentials
.DESCRIPTION
    Sets Perch OAuth2 Client ID and Client Secret without requiring ConnectionManager module.
    Both Client ID and Client Secret are REQUIRED for Perch OAuth2 authentication.
.PARAMETER ClientId
    Perch OAuth2 Client ID (optional - will prompt if not provided)
.PARAMETER ClientSecret
    Perch OAuth2 Client Secret (optional - will prompt if not provided)
.EXAMPLE
    .\set-perch-oauth2-standalone.ps1
    # Prompts for both Client ID and Client Secret
    
.EXAMPLE
    .\set-perch-oauth2-standalone.ps1 -ClientId "your-client-id" -ClientSecret "your-client-secret"
    # Provides both credentials as parameters
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$ClientId,
    
    [Parameter(Mandatory=$false)]
    [string]$ClientSecret,
    
    [Parameter(Mandatory=$false)]
    [string]$ApiKey
)

Write-Host "=== Perch OAuth2 Setup (Standalone) ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Perch requires BOTH Client ID and Client Secret for OAuth2 authentication." -ForegroundColor Yellow
Write-Host "Some Perch instances may also require an API Key." -ForegroundColor Yellow
Write-Host ""

# Get Client ID if not provided
if (-not $ClientId) {
    $ClientId = Read-Host "Enter Perch Client ID"
    if ([string]::IsNullOrWhiteSpace($ClientId)) {
        Write-Host "ERROR: Client ID is required!" -ForegroundColor Red
        exit 1
    }
}

# Get Client Secret if not provided
if (-not $ClientSecret) {
    $clientSecretSecure = Read-Host "Enter Perch Client Secret" -AsSecureString
    if (-not $clientSecretSecure) {
        Write-Host "ERROR: Client Secret is required!" -ForegroundColor Red
        exit 1
    }
    # Convert secure string to plain text
    $ClientSecret = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($clientSecretSecure)
    )
}

# Get API Key if not provided (optional)
if (-not $ApiKey) {
    Write-Host ""
    $apiKeyInput = Read-Host "Enter Perch API Key (optional - press Enter to skip)"
    if (-not [string]::IsNullOrWhiteSpace($apiKeyInput)) {
        $ApiKey = $apiKeyInput
    }
}

# Validate both credentials are provided
if ([string]::IsNullOrWhiteSpace($ClientId)) {
    Write-Host "ERROR: Client ID cannot be empty!" -ForegroundColor Red
    exit 1
}

if ([string]::IsNullOrWhiteSpace($ClientSecret)) {
    Write-Host "ERROR: Client Secret cannot be empty!" -ForegroundColor Red
    exit 1
}

# Save credentials encrypted
$clientIdPath = Join-Path $env:USERPROFILE ".perch_clientid"
$clientSecretPath = Join-Path $env:USERPROFILE ".perch_clientsecret"
$apiKeyPath = Join-Path $env:USERPROFILE ".perch_apikey"

try {
    $ClientId | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString | Out-File $clientIdPath -Force
    $ClientSecret | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString | Out-File $clientSecretPath -Force
    
    Write-Host ""
    Write-Host "✓ Perch OAuth2 credentials saved successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Saved to:" -ForegroundColor Cyan
    Write-Host "  - Client ID: $clientIdPath" -ForegroundColor Gray
    Write-Host "  - Client Secret: $clientSecretPath" -ForegroundColor Gray
    
    # Save API key if provided
    if ($ApiKey) {
        $ApiKey | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString | Out-File $apiKeyPath -Force
        Write-Host "  - API Key: $apiKeyPath" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "All credentials are stored encrypted in your user profile." -ForegroundColor Gray
}
catch {
    Write-Host "✗ Failed to save credentials: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Setup complete!" -ForegroundColor Green

