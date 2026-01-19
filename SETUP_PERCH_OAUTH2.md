# Perch OAuth2 Setup Guide

## Yes, You Need OAuth2 Credentials for Perch!

Perch uses **OAuth2 Client Credentials** flow, not simple Bearer tokens. 

⚠️ **BOTH Client ID and Client Secret are REQUIRED** - you cannot use Perch API without both!

Some Perch instances may also require an **API Key** in addition to OAuth2 credentials.

You need:
- **Client ID**: `ThIWsV5NhztMqymR4PqbqVTytEZWv6j2` (required)
- **Client Secret**: `-dDTrglbi7xz-K0OM98EAb1bxkYoQQpCWg7f4EySdMk8fdipDi9yl6fP9U5aIWPH` (required)
- **API Key**: (optional - check with your Perch administrator if required)

## Quick Setup

### Option 1: Standalone Script (Recommended - Works Even If Module Has Issues)

```powershell
cd C:\git\RiverRunThreatHunter
.\set-perch-oauth2-standalone.ps1
```

When prompted, enter:
- **Client ID**: `ThIWsV5NhztMqymR4PqbqVTytEZWv6j2`
- **Client Secret**: `-dDTrglbi7xz-K0OM98EAb1bxkYoQQpCWg7f4EySdMk8fdipDi9yl6fP9U5aIWPH`
- **API Key**: (optional - press Enter to skip if not needed)

**Or provide all three as parameters:**
```powershell
.\set-perch-oauth2-standalone.ps1 `
    -ClientId "ThIWsV5NhztMqymR4PqbqVTytEZWv6j2" `
    -ClientSecret "-dDTrglbi7xz-K0OM98EAb1bxkYoQQpCWg7f4EySdMk8fdipDi9yl6fP9U5aIWPH" `
    -ApiKey "your-api-key-here"
```

### Option 2: Module Script (If ConnectionManager Module Works)

```powershell
cd C:\git\RiverRunThreatHunter
.\setup-perch-oauth2.ps1
```

When prompted, enter:
- **Client ID**: `ThIWsV5NhztMqymR4PqbqVTytEZWv6j2`
- **Client Secret**: `-dDTrglbi7xz-K0OM98EAb1bxkYoQQpCWg7f4EySdMk8fdipDi9yl6fP9U5aIWPH`

## Manual Setup

```powershell
Import-Module .\modules\ConnectionManager.psm1

Set-PerchOAuth2Credentials `
    -ClientId "ThIWsV5NhztMqymR4PqbqVTytEZWv6j2" `
    -ClientSecret "-dDTrglbi7xz-K0OM98EAb1bxkYoQQpCWg7f4EySdMk8fdipDi9yl6fP9U5aIWPH"
```

## How It Works

1. **Credentials are stored encrypted** in your user profile:
   - `%USERPROFILE%\.perch_clientid` (Client ID)
   - `%USERPROFILE%\.perch_clientsecret` (Client Secret)
   - `%USERPROFILE%\.perch_apikey` (API Key - if provided)

2. **On each API call**, the tool:
   - Exchanges Client ID/Secret for an OAuth2 access token
   - Uses the access token for API requests
   - Caches the token (refreshes automatically when expired)

3. **No manual token management needed** - it's all automatic!

## Testing

```powershell
# Test Perch connection
Import-Module .\modules\ConnectionManager.psm1
Import-Module .\modules\PerchHunter.psm1

$conn = Get-PlatformConnection -Platform "PerchSIEM"

# Try a simple query (replace with your actual team ID)
$results = Search-PerchLogs -Connection $conn `
    -Query "event_type:login" `
    -TeamId "your-team-id" `
    -Limit 10
```

## Security Note

⚠️ **Keep your Client Secret secure!**
- Never commit it to version control
- Don't share it in screenshots or logs
- It's stored encrypted on your machine only
- If compromised, regenerate it in Perch console

## Troubleshooting

### "Failed to get Perch OAuth2 token"
- Verify Client ID and Secret are correct
- Check that BaseUri in ClientConfig.json is correct
- Ensure your network can reach the Perch API
- Verify the OAuth2 endpoint path (may vary by instance)

### "401 Unauthorized"
- Client ID or Secret is incorrect
- Credentials may have been revoked
- Check Perch console for OAuth2 app status

### Token Exchange Works But Queries Fail
- Verify you have the correct Team ID
- Check API permissions for your OAuth2 app
- Ensure the app has read access to logs

## Next Steps

Once OAuth2 is configured:
1. Add Team IDs to your clients in `ClientConfig.json`
2. Set `"HasPerch": true` for clients with Perch
3. Run threat hunts - Perch queries will work automatically!

