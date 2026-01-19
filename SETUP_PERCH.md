# Setting Up Perch SIEM Connection

This guide walks you through connecting to Perch SIEM for network and log visibility.

## Step 1: Get Your Perch API Token

1. Log into your Perch SIEM console
2. Navigate to: **Settings → API Tokens** (or **Account → API Tokens**)
3. Click **Create API Token** or use an existing token
4. Copy the token (you won't be able to see it again!)

**Note:** Perch API tokens are typically Bearer tokens. Make sure you have read permissions at minimum.

## Step 2: Get Your Perch Instance URL

- Perch API base URL: `https://api.perch.rocks/v1`
- If you have a custom instance, check with your Perch administrator
- The base URL should end with `/v1` for API v1

## Step 3: Get Team/Organization IDs

Perch uses Team IDs (also called Organization IDs) to scope queries:

1. Log into Perch console
2. Navigate to **Settings → Teams** (or **Organizations**)
3. Each team/organization has a unique ID
4. Note the Team ID for each client that uses Perch

**Finding Team ID:**
- Usually visible in the URL when viewing a team: `.../teams/[team-id]/...`
- Or in team settings/details page
- Format is typically: `team-123456` or `org-abc123` or just a UUID

## Step 4: Configure ClientConfig.json

Edit `config\ClientConfig.json` and ensure PerchSIEM platform is configured:

```json
{
  "Platforms": {
    "PerchSIEM": {
      "Type": "Perch",
      "BaseUri": "https://api.perch.rocks/v1",
      "TokenFile": ".perch_token",
      "AccessLevel": "ReadOnly",
      "Description": "Perch SIEM - Query Only"
    }
  },
  "Clients": {
    "YourClientName": {
      "CWCompanyId": "12345",
      "S1Platform": "ConnectWiseS1",
      "S1SiteId": "9876543210",
      "S1SiteName": "Your Client Name",
      "HasPerch": true,
      "PerchTeamId": "your-perch-team-id-here",
      "PrimarySocContact": "admin@client.com",
      "Tier": "Premium"
    }
  }
}
```

**Important:** Only clients with `"HasPerch": true` will have Perch queries executed during hunts.

## Step 5: Set Perch OAuth2 Credentials

Perch uses **OAuth2** authentication with Client ID and Client Secret (not a simple Bearer token).

### Quick Setup Script:
```powershell
cd C:\git\RiverRunThreatHunter
.\setup-perch-oauth2.ps1
```

### Manual Setup:
```powershell
cd C:\git\RiverRunThreatHunter

# Import the connection manager
Import-Module .\modules\ConnectionManager.psm1

# Set Perch OAuth2 credentials
Set-PerchOAuth2Credentials -ClientId "your-client-id" -ClientSecret "your-client-secret"

# Or interactively:
Set-PerchOAuth2Credentials
# When prompted, enter your Client ID and Client Secret
```

**Note:** Your credentials are stored encrypted in your user profile (`.perch_clientid` and `.perch_clientsecret`).

## Step 6: Test Perch Connection

```powershell
# Test Perch connection
Import-Module .\modules\ConnectionManager.psm1
Import-Module .\modules\PerchHunter.psm1

$conn = Get-PlatformConnection -Platform "PerchSIEM"

# Test with a simple query (adjust team ID)
$results = Search-PerchLogs -Connection $conn -Query "event_type:login" -TeamId "your-team-id" -Limit 10
```

## Step 7: Verify Client Configuration

```powershell
# Check which clients have Perch
Import-Module .\modules\ThreatHuntConfig.psm1
Initialize-ThreatHuntConfig

# Get clients with Perch
Get-AllClients -WithPerch | Format-Table ClientName, PerchTeamId
```

## Perch Query Examples

### Hunt for IP Address
```powershell
$conn = Get-PlatformConnection -Platform "PerchSIEM"
$results = Hunt-PerchIP -Connection $conn -IP "192.168.1.100" -TeamId "team-123" -DaysBack 14
```

### Hunt for Domain
```powershell
$results = Hunt-PerchDomain -Connection $conn -Domain "malicious.com" -TeamId "team-123" -DaysBack 14
```

### Hunt for Username
```powershell
$results = Hunt-PerchUser -Connection $conn -Username "jsmith" -TeamId "team-123" -DaysBack 14
```

### Search Custom Query
```powershell
$results = Search-PerchLogs -Connection $conn `
    -Query "src_ip:192.168.1.100 AND event_type:firewall" `
    -TeamId "team-123" `
    -DaysBack 7 `
    -LogSources @("firewall", "ids")
```

## Perch Query Syntax

Perch uses a query syntax similar to Elasticsearch. Common operators:

- `field:value` - Exact match
- `field:*value*` - Contains
- `field1:value1 AND field2:value2` - Both conditions
- `field1:value1 OR field2:value2` - Either condition
- `NOT field:value` - Exclude

### Common Fields:
- `src_ip` - Source IP address
- `dst_ip` - Destination IP address
- `client_ip` - Client IP (for auth logs)
- `user` or `username` - Username
- `domain` - Domain name
- `event_type` - Event type (login, firewall, dns, etc.)
- `log_source` - Log source name
- `timestamp` - Event timestamp

## Troubleshooting

### "Failed to search Perch logs" Error
- Verify your API token is valid and not expired
- Check that the BaseUri in ClientConfig.json is correct
- Ensure your network can reach the Perch API endpoint
- Verify the token has read permissions

### "Team ID not found" Error
- Double-check the PerchTeamId in ClientConfig.json
- Ensure the team ID format matches what Perch expects
- Verify you have access to that team/organization

### "No results returned" Error
- Check your query syntax
- Verify the time range (DaysBack parameter)
- Ensure the team ID is correct
- Check if logs exist for that time period in Perch

### Testing Perch Connection Directly

```powershell
# Test API connectivity
$conn = Get-PlatformConnection -Platform "PerchSIEM"

# Try a simple health check (if Perch supports it)
try {
    Invoke-RestMethod -Uri "$($conn.BaseUri)/health" -Headers $conn.Headers -Method Get
    Write-Host "✓ Perch API is reachable" -ForegroundColor Green
}
catch {
    Write-Host "✗ Perch API connection failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Try a simple log search
try {
    $testQuery = Search-PerchLogs -Connection $conn -Query "*" -TeamId "your-team-id" -Limit 1
    Write-Host "✓ Perch query successful" -ForegroundColor Green
}
catch {
    Write-Host "✗ Perch query failed: $($_.Exception.Message)" -ForegroundColor Red
}
```

## Integration with Threat Hunts

When you run a threat hunt, Perch queries are automatically executed for clients that have `"HasPerch": true`:

```powershell
# Hunt IOCs - Perch will be queried automatically for clients with HasPerch: true
$iocs = @(
    @{ Type = "ip"; Value = "192.168.1.100" },
    @{ Type = "domain"; Value = "malicious.com" }
)

# This will query both S1 and Perch (if client has Perch enabled)
$results = Invoke-ClientThreatHunt -IOCs $iocs -ClientName "YourClient" -DaysBack 14

# Results will include both endpoint (S1) and network (Perch) hits
$results | Where-Object { $_.SourceType -eq "Network" }  # Perch results
$results | Where-Object { $_.SourceType -eq "Endpoint" } # S1 results
```

## Perch vs SentinelOne Results

Results from Perch will have:
- `Source = "PerchSIEM"`
- `SourceType = "Network"`
- `Platform = "Perch"`
- `CanTakeAction = false` (Perch is read-only)
- Network-specific fields like `LogSource`, `RawMessage`

This allows you to correlate endpoint activity (S1) with network activity (Perch) for a complete picture.

## Next Steps

Once Perch is configured:
1. Run threat hunts - Perch will be queried automatically
2. View correlated results - See IOCs on both endpoint and network
3. Generate reports - Reports include both S1 and Perch hits

