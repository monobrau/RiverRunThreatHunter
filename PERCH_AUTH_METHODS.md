# Perch Authentication Methods

## Important: Perch May Use Simple API Tokens, Not OAuth2

Based on your setup, Perch Security SIEM might use **simple Bearer tokens** instead of OAuth2 Client Credentials flow.

## Option 1: Simple Bearer Token (Try This First)

If Perch uses simple API tokens:

```powershell
# Set as a simple Bearer token
Import-Module .\modules\ConnectionManager.psm1

# Use your Client ID as the API token (or get actual API token from Perch)
Set-PlatformToken -Platform "PerchSIEM"
# When prompted, paste your API token
```

Then update `config\ClientConfig.json`:
```json
"PerchSIEM": {
  "Type": "Perch",
      "BaseUri": "https://api.perch.rocks/v1",
  "TokenFile": ".perch_token",
  "AccessLevel": "ReadOnly",
  "OAuth2": false,  // ← Set to false for simple Bearer token
  "Description": "Perch SIEM - Query Only"
}
```

## Option 2: OAuth2 Client Credentials (If Supported)

If Perch actually uses OAuth2:

```powershell
Set-PerchOAuth2Credentials `
    -ClientId "your-client-id-here" `
    -ClientSecret "your-client-secret-here"
```

Keep `"OAuth2": true` in ClientConfig.json.

## Testing Which Method Works

Run the diagnostic script:

```powershell
.\test-perch-connection.ps1
```

This will:
1. Try OAuth2 if credentials are configured
2. Fall back to Bearer token if OAuth2 fails
3. Show you which method works

## What Your Credentials Actually Are

The "Client ID" and "Client Secret" you have might be:
- **OAuth2 credentials** (if Perch supports OAuth2)
- **API Token** (if Perch uses simple tokens - use Client ID as the token)
- **Different format** (check Perch API documentation)

## Finding the Right Method

1. **Check Perch API Documentation**
   - Look for authentication examples
   - See if they mention OAuth2 or Bearer tokens

2. **Try Simple Bearer Token First**
   ```powershell
   # Use your Client ID as the token
   Set-PlatformToken -Platform "PerchSIEM"
   # Paste: your-client-id-here
   ```

3. **If That Doesn't Work, Try OAuth2**
   ```powershell
   Set-PerchOAuth2Credentials `
       -ClientId "your-client-id-here" `
       -ClientSecret "your-client-secret-here"
   ```

4. **Check the Error Messages**
   - 401 Unauthorized = Wrong credentials or wrong auth method
   - 404 Not Found = Wrong endpoint (OAuth2 endpoint might not exist)
   - 200 OK = It works!

## Current Status

You've saved OAuth2 credentials, but getting 404 on the OAuth2 token endpoint. This suggests:
- Perch might not use OAuth2
- Or the OAuth2 endpoint path is different
- Or you need to use simple Bearer token instead

**Try this:**
```powershell
# Remove OAuth2 config, use simple token
Remove-Item "$env:USERPROFILE\.perch_clientid" -ErrorAction SilentlyContinue
Remove-Item "$env:USERPROFILE\.perch_clientsecret" -ErrorAction SilentlyContinue

# Set as simple Bearer token (use your Client ID as the token)
Set-PlatformToken -Platform "PerchSIEM"
# Paste: your-client-id-here

# Update config
# Edit config\ClientConfig.json, set "OAuth2": false

# Test
Test-AllConnections
```

