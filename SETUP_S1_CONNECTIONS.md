# Setting Up SentinelOne Connections

This guide walks you through connecting to your SentinelOne tenants (Barracuda XDR and ConnectWise S1).

## Step 1: Get Your SentinelOne API Tokens

### For Barracuda XDR (Read-Only):
1. Log into your Barracuda XDR SentinelOne console
2. Navigate to: **Settings → Users → [Your User] → API Token**
3. Click **Generate Token** or copy existing token
4. Save this token securely

### For ConnectWise S1 (Read/Write):
1. Log into your ConnectWise SentinelOne console
2. Navigate to: **Settings → Users → [Your User] → API Token**
3. Click **Generate Token** or copy existing token
4. Save this token securely

**Note:** You can also create dedicated service user accounts specifically for API access with minimum required permissions.

## Step 2: Get Your SentinelOne Instance URLs

### Finding Your Instance URL:
- Your SentinelOne URL format is: `https://[instance-name].sentinelone.net`
- Examples:
  - `https://usea1-cwmsp.sentinelone.net` (ConnectWise US East)
  - `https://barracuda-instance.sentinelone.net` (Barracuda)
- The API base URL is: `https://[instance-name].sentinelone.net/web/api/v2.1`

## Step 3: Configure ClientConfig.json

Edit `config\ClientConfig.json` with your actual values:

```json
{
  "Platforms": {
    "BarracudaXDR": {
      "Type": "SentinelOne",
      "BaseUri": "https://YOUR-BARRACUDA-INSTANCE.sentinelone.net/web/api/v2.1",
      "TokenFile": ".s1token_barracuda",
      "AccessLevel": "ReadOnly",
      "HasSIEM": false,
      "Description": "Barracuda Managed XDR - Query Only"
    },
    "ConnectWiseS1": {
      "Type": "SentinelOne",
      "BaseUri": "https://YOUR-CW-INSTANCE.sentinelone.net/web/api/v2.1",
      "TokenFile": ".s1token_connectwise",
      "AccessLevel": "ReadWrite",
      "HasSIEM": true,
      "SIEMPlatform": "Perch",
      "Description": "ConnectWise S1 - Full Access"
    }
  },
  "Clients": {
    "YourClientName": {
      "CWCompanyId": "12345",
      "S1Platform": "ConnectWiseS1",
      "S1SiteId": "9876543210",
      "S1SiteName": "Your Client Name",
      "HasPerch": true,
      "PerchTeamId": "perch-team-001",
      "PrimarySocContact": "admin@client.com",
      "Tier": "Premium"
    }
  }
}
```

### Finding Site IDs:
1. Log into SentinelOne console
2. Navigate to **Settings → Sites**
3. Click on a site to view details
4. The Site ID is shown in the URL or site details (usually a long number like `9876543210123456789`)

## Step 4: Set API Tokens

Open PowerShell and run:

```powershell
cd C:\git\RiverRunThreatHunter

# Import the connection manager
Import-Module .\modules\ConnectionManager.psm1

# Set token for Barracuda XDR
Set-PlatformToken -Platform "BarracudaXDR"
# When prompted, paste your Barracuda XDR API token

# Set token for ConnectWise S1
Set-PlatformToken -Platform "ConnectWiseS1"
# When prompted, paste your ConnectWise S1 API token
```

**What this does:**
- Stores tokens encrypted in your user profile (`%USERPROFILE%\.s1token_barracuda` and `.s1token_connectwise`)
- Tokens are encrypted using Windows SecureString

## Step 5: Test Connections

```powershell
# Test all connections
Import-Module .\modules\ConnectionManager.psm1
Test-AllConnections
```

You should see:
```
✓ BarracudaXDR - Connected (ReadOnly)
✓ ConnectWiseS1 - Connected (ReadWrite)
```

## Step 6: Verify Client Configuration

```powershell
# Import config module
Import-Module .\modules\ThreatHuntConfig.psm1

# Initialize config
Initialize-ThreatHuntConfig

# List all clients
Get-AllClients

# Get specific client details
Get-ClientConfig -ClientName "YourClientName"
```

## Troubleshooting

### "Token file not found" Error
- Make sure you ran `Set-PlatformToken` for each platform
- Check that tokens are stored in `%USERPROFILE%\.s1token_*`

### "Failed to connect" Error
- Verify the BaseUri in ClientConfig.json is correct
- Check that your API token is valid and not expired
- Ensure your network can reach the SentinelOne instance
- Verify the token has appropriate permissions

### "Site ID not found" Error
- Double-check the S1SiteId in ClientConfig.json matches the actual site ID
- Site IDs are case-sensitive and must match exactly

### Testing Individual Platform Connection

```powershell
# Test Barracuda XDR specifically
$conn = Get-PlatformConnection -Platform "BarracudaXDR"
Invoke-RestMethod -Uri "$($conn.BaseUri)/system/status" -Headers $conn.Headers -Method Get

# Test ConnectWise S1 specifically
$conn = Get-PlatformConnection -Platform "ConnectWiseS1"
Invoke-RestMethod -Uri "$($conn.BaseUri)/system/status" -Headers $conn.Headers -Method Get
```

## Example: Complete Setup Script

Save this as `setup-connections.ps1`:

```powershell
# Setup SentinelOne Connections
cd C:\git\RiverRunThreatHunter

Write-Host "=== SentinelOne Connection Setup ===" -ForegroundColor Cyan
Write-Host ""

# Import modules
Import-Module .\modules\ConnectionManager.psm1
Import-Module .\modules\ThreatHuntConfig.psm1

# Set tokens
Write-Host "Setting Barracuda XDR token..." -ForegroundColor Yellow
Set-PlatformToken -Platform "BarracudaXDR"

Write-Host "Setting ConnectWise S1 token..." -ForegroundColor Yellow
Set-PlatformToken -Platform "ConnectWiseS1"

# Test connections
Write-Host ""
Write-Host "Testing connections..." -ForegroundColor Cyan
Test-AllConnections

# Verify config
Write-Host ""
Write-Host "Verifying configuration..." -ForegroundColor Cyan
Initialize-ThreatHuntConfig
Get-AllClients | Format-Table ClientName, S1Platform, S1SiteId, CanTakeAction

Write-Host ""
Write-Host "Setup complete!" -ForegroundColor Green
```

Run it:
```powershell
.\setup-connections.ps1
```

## Next Steps

Once connected, you can:
1. Run threat hunts: `Invoke-ClientThreatHunt -IOCs $iocs -ClientName "YourClient"`
2. Query Deep Visibility: `Hunt-S1FileHash -Connection $conn -Hash "abc123..."`
3. Take response actions: `Invoke-S1Isolate -Platform "ConnectWiseS1" -AgentId "123456"`

