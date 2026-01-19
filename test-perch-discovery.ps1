# Test script for Perch team discovery
# Run this directly to diagnose why Get-PerchTeams might return empty results

Write-Host "=== Perch Discovery Test ===" -ForegroundColor Cyan
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
    
    Import-Module (Join-Path $modulesPath "PerchHunter.psm1") -Force -ErrorAction Stop
    Write-Host "  ✓ PerchHunter imported" -ForegroundColor Green
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

# Check for token files
Write-Host "Checking for Perch token files..." -ForegroundColor Yellow
$tokenFiles = @(
    ".perch_token",
    ".perch_apikey",
    ".perch_clientid",
    ".perch_clientsecret"
)

$foundTokens = @()
foreach ($tokenFile in $tokenFiles) {
    $tokenPath = Join-Path $scriptDir $tokenFile
    if (Test-Path $tokenPath) {
        Write-Host "  ✓ Found: $tokenFile" -ForegroundColor Green
        $foundTokens += $tokenFile
    }
    else {
        Write-Host "  ✗ Missing: $tokenFile" -ForegroundColor Red
    }
}

if ($foundTokens.Count -eq 0) {
    Write-Host ""
    Write-Host "  ⚠ No Perch token files found!" -ForegroundColor Yellow
    Write-Host "    You need at least one of: .perch_token, .perch_apikey" -ForegroundColor Gray
}

Write-Host ""

# Get connection
Write-Host "Getting platform connection..." -ForegroundColor Yellow
try {
    $conn = Get-PlatformConnection -Platform "PerchSIEM" -ErrorAction Stop
    
    if (-not $conn) {
        Write-Host "  ✗ Connection is null" -ForegroundColor Red
        Write-Host "    Check your Perch token files" -ForegroundColor Yellow
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
            if ($key -eq "Authorization" -or $key -eq "X-API-Key") {
                $authValue = $conn.Headers[$key]
                if ($authValue -like "* *") {
                    $parts = $authValue -split " "
                    if ($parts.Length -gt 1) {
                        $tokenPreview = $parts[0] + " " + $parts[1].Substring(0, [Math]::Min(20, $parts[1].Length)) + "..."
                        Write-Host "    $key : $tokenPreview" -ForegroundColor Gray
                    }
                    else {
                        Write-Host "    $key : [hidden]" -ForegroundColor Gray
                    }
                }
                else {
                    $tokenPreview = $authValue.Substring(0, [Math]::Min(20, $authValue.Length)) + "..."
                    Write-Host "    $key : $tokenPreview" -ForegroundColor Gray
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

# Test API call with detailed endpoint testing
Write-Host "Calling Get-PerchTeams..." -ForegroundColor Yellow
Write-Host ""

# Test each endpoint manually to see what's happening
$baseUri = $conn.BaseUri.ToString().Trim().TrimEnd('/')
$testEndpoints = @(
    "$baseUri/teams",
    "$baseUri/v1/teams",
    "$baseUri/organizations",
    "$baseUri/v1/organizations",
    "$baseUri/accounts",
    "$baseUri/v1/accounts"
)

Write-Host "Testing individual endpoints:" -ForegroundColor Cyan
foreach ($endpoint in $testEndpoints) {
    try {
        Write-Host "  Testing: $endpoint" -ForegroundColor Gray -NoNewline
        $testResponse = Invoke-RestMethod -Uri $endpoint -Method Get -Headers $conn.Headers -ErrorAction Stop
        Write-Host " ✓ SUCCESS" -ForegroundColor Green
        Write-Host "    Response type: $($testResponse.GetType().Name)" -ForegroundColor Gray
        if ($testResponse.PSObject.Properties.Name) {
            Write-Host "    Response properties: $($testResponse.PSObject.Properties.Name -join ', ')" -ForegroundColor Gray
        }
        break
    }
    catch {
        $statusCode = $null
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode.value__
        }
        if ($statusCode -eq 404) {
            Write-Host " ✗ 404 Not Found" -ForegroundColor Yellow
        }
        elseif ($statusCode -eq 401) {
            Write-Host " ✗ 401 Unauthorized (auth failed)" -ForegroundColor Red
            Write-Host "    Check your API key or token" -ForegroundColor Yellow
        }
        elseif ($statusCode -eq 403) {
            Write-Host " ✗ 403 Forbidden (no permission)" -ForegroundColor Red
        }
        else {
            Write-Host " ✗ Error: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

Write-Host ""

# Now try the actual function
try {
    $teams = Get-PerchTeams -Connection $conn -ErrorAction Stop
    
    Write-Host ""
    if ($null -eq $teams) {
        Write-Host "  ⚠ Get-PerchTeams returned NULL" -ForegroundColor Yellow
    }
    elseif ($teams.Count -eq 0) {
        Write-Host "  ⚠ Get-PerchTeams returned EMPTY ARRAY (0 teams)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Possible reasons:" -ForegroundColor Cyan
        Write-Host "  1. Your API token doesn't have access to any teams" -ForegroundColor Gray
        Write-Host "  2. The API endpoint structure has changed" -ForegroundColor Gray
        Write-Host "  3. The account has no teams configured" -ForegroundColor Gray
        Write-Host "  4. The API endpoint URL is incorrect" -ForegroundColor Gray
        Write-Host "  5. Authentication method mismatch (try API key vs Bearer token)" -ForegroundColor Gray
    }
    else {
        Write-Host "  ✓ Found $($teams.Count) teams" -ForegroundColor Green
        Write-Host ""
        Write-Host "First 5 teams:" -ForegroundColor Cyan
        $teams | Select-Object -First 5 | Format-Table TeamId, TeamName, Status, MemberCount -AutoSize
    }
    
    Write-Host ""
    Write-Host "Raw JSON output:" -ForegroundColor Cyan
    $teams | ConvertTo-Json -Depth 10 | Write-Host
    
    Write-Host ""
    Write-Host "=== Test Complete ===" -ForegroundColor Green
}
catch {
    Write-Host "  ✗ Get-PerchTeams failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "    Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Cyan
    Write-Host "  1. Verify your BaseUri in ClientConfig.json is correct" -ForegroundColor Gray
    Write-Host "  2. Check if you need API Key (.perch_apikey) or Bearer token (.perch_token)" -ForegroundColor Gray
    Write-Host "  3. Verify your token/API key has the correct permissions" -ForegroundColor Gray
    Write-Host "  4. Check Perch API documentation for correct endpoint paths" -ForegroundColor Gray
    exit 1
}

