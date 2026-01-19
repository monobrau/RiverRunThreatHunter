<#
.SYNOPSIS
    Interactive setup script for SentinelOne connections
.DESCRIPTION
    Guides you through setting up API tokens and testing connections
#>

Write-Host "=== RiverRunThreatHunter - SentinelOne Connection Setup ===" -ForegroundColor Cyan
Write-Host ""

# Check if modules exist
if (-not (Test-Path "modules\ConnectionManager.psm1")) {
    Write-Host "ERROR: ConnectionManager.psm1 not found!" -ForegroundColor Red
    Write-Host "Make sure you're running this from the project root directory." -ForegroundColor Yellow
    exit 1
}

# Import modules
Write-Host "Loading modules..." -ForegroundColor Gray
Import-Module .\modules\ConnectionManager.psm1 -ErrorAction Stop
Import-Module .\modules\ThreatHuntConfig.psm1 -ErrorAction Stop

Write-Host ""

# Check ClientConfig.json
if (-not (Test-Path "config\ClientConfig.json")) {
    Write-Host "WARNING: ClientConfig.json not found!" -ForegroundColor Yellow
    Write-Host "Please create config\ClientConfig.json first." -ForegroundColor Yellow
    Write-Host ""
}

# Step 1: Set ConnectWise S1 Token
Write-Host "Step 1: ConnectWise S1 (Read/Write)" -ForegroundColor Yellow
Write-Host "  Get your API token from: Settings → Users → [Your User] → API Token" -ForegroundColor Gray
$continue = Read-Host "  Ready to set ConnectWise S1 token? (y/n)"
if ($continue -eq "y" -or $continue -eq "Y") {
    Set-PlatformToken -Platform "ConnectWiseS1"
    Write-Host "  ✓ ConnectWise S1 token saved" -ForegroundColor Green
}
Write-Host ""

# Step 2: Set Perch SIEM OAuth2 Credentials (Optional)
Write-Host "Step 2: Perch SIEM (Read-Only, Optional)" -ForegroundColor Yellow
Write-Host "  Perch uses OAuth2 - you need Client ID and Client Secret" -ForegroundColor Cyan
Write-Host "  Get these from: Settings → API Tokens → Create OAuth2 App" -ForegroundColor Gray
$continue = Read-Host "  Set Perch OAuth2 credentials? (y/n)"
if ($continue -eq "y" -or $continue -eq "Y") {
    try {
        # Check if Set-PerchOAuth2Credentials function exists
        if (Get-Command Set-PerchOAuth2Credentials -ErrorAction SilentlyContinue) {
            Set-PerchOAuth2Credentials
            Write-Host "  ✓ Perch OAuth2 credentials saved" -ForegroundColor Green
        }
        else {
            Write-Host "  ⚠ OAuth2 function not loaded. Run: .\setup-perch-oauth2.ps1" -ForegroundColor Yellow
            Write-Host "     Or manually: Set-PerchOAuth2Credentials -ClientId '...' -ClientSecret '...'" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "  ⚠ Failed to save credentials: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "     You can run: .\setup-perch-oauth2.ps1" -ForegroundColor Gray
    }
}
Write-Host ""

# Step 3: Test Connections
Write-Host "Step 3: Testing Connections" -ForegroundColor Yellow
$test = Read-Host "  Test connections now? (y/n)"
if ($test -eq "y" -or $test -eq "Y") {
    Write-Host ""
    Test-AllConnections
}
Write-Host ""

# Step 4: Verify Configuration
Write-Host "Step 4: Verifying Configuration" -ForegroundColor Yellow
if (Test-Path "config\ClientConfig.json") {
    try {
        Initialize-ThreatHuntConfig
        Write-Host ""
        Write-Host "Configured Clients:" -ForegroundColor Cyan
        Get-AllClients | Format-Table ClientName, S1Platform, S1SiteId, CanTakeAction -AutoSize
    }
    catch {
        Write-Host "  ⚠ Could not load configuration: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
else {
    Write-Host "  ⚠ ClientConfig.json not found - skipping configuration check" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Setup Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Test your API access: .\test-api-access.ps1" -ForegroundColor Gray
Write-Host "  2. Edit config\ClientConfig.json with your clients and site IDs" -ForegroundColor Gray
Write-Host "  3. For Perch clients, add PerchTeamId to each client config" -ForegroundColor Gray
Write-Host "  4. Run: Test-AllConnections" -ForegroundColor Gray
Write-Host "  5. Try: Get-AllClients -WithPerch" -ForegroundColor Gray
Write-Host ""
Write-Host "Documentation:" -ForegroundColor Cyan
Write-Host "  - SentinelOne: See SETUP_S1_CONNECTIONS.md" -ForegroundColor Gray
Write-Host "  - Perch SIEM: See SETUP_PERCH.md" -ForegroundColor Gray
Write-Host ""

