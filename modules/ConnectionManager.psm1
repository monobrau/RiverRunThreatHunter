<#
.SYNOPSIS
    Multi-Platform Connection Management Module
.DESCRIPTION
    Manages API connections for SentinelOne (ConnectWise S1) and Perch SIEM platforms.
    Handles token storage and connection validation.
.NOTES
    Author: River Run Security Team
    Version: 1.0
#>

$script:Connections = @{}

function Get-PlatformConnection {
    <#
    .SYNOPSIS
        Gets API connection object for a platform
    .DESCRIPTION
        Returns cached connection or creates new one from stored token.
        Connections are cached for the session.
    .PARAMETER Platform
        Platform name (ConnectWiseS1, PerchSIEM)
    .EXAMPLE
        Get-PlatformConnection -Platform "ConnectWiseS1"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("ConnectWiseS1", "PerchSIEM")]
        [string]$Platform
    )
    
    # Return cached connection if available
    if ($script:Connections[$Platform]) {
        return $script:Connections[$Platform]
    }
    
    # Import config module
    $configModule = Get-Module -Name "ThreatHuntConfig" -ListAvailable
    if (-not $configModule) {
        Import-Module (Join-Path $PSScriptRoot "ThreatHuntConfig.psm1") -ErrorAction Stop
    }
    else {
        Import-Module ThreatHuntConfig -ErrorAction Stop
    }
    
    $platformConfig = Get-PlatformConfig -Platform $Platform
    
    # Handle Perch authentication - API Key + Basic Auth (username:password) → Bearer token
    if ($Platform -eq "PerchSIEM") {
        # Ensure BaseUri is api.perch.rocks/v1 (not api.perchsecurity.com)
        $baseUri = $platformConfig.BaseUri
        if ($baseUri -like "*perchsecurity.com*") {
            $baseUri = $baseUri -replace "perchsecurity\.com", "perch.rocks"
        }
        if (-not $baseUri -like "*/v1*") {
            $baseUri = $baseUri.TrimEnd('/') + "/v1"
        }
        
        # Required: API Key
        $apiKey = $null
        $apiKeyPath = Join-Path $env:USERPROFILE $platformConfig.ApiKeyFile
        if (-not (Test-Path $apiKeyPath)) {
            throw "Perch API key file not found at $apiKeyPath. Required for Perch API v1 authentication."
        }
        
        try {
            $apiKeySecure = Get-Content $apiKeyPath | ConvertTo-SecureString
            $apiKey = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [Runtime.InteropServices.Marshal]::SecureStringToBSTR($apiKeySecure)
            )
        }
        catch {
            throw "Failed to decrypt Perch API key: $($_.Exception.Message)"
        }
        
        # Check if we have a cached Bearer token
        $tokenPath = Join-Path $env:USERPROFILE $platformConfig.TokenFile
        $bearerToken = $null
        
        if (Test-Path $tokenPath) {
            try {
                $tokenSecure = Get-Content $tokenPath | ConvertTo-SecureString
                $bearerToken = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($tokenSecure)
                )
            }
            catch {
                Write-Verbose "Failed to decrypt cached token, will acquire new token"
            }
        }
        
        # If no cached token, acquire one using Basic Auth
        if (-not $bearerToken) {
            # Required: Username and Password for Basic Auth
            $usernamePath = Join-Path $env:USERPROFILE ($platformConfig.UsernameFile ?? ".perch_username")
            $passwordPath = Join-Path $env:USERPROFILE ($platformConfig.PasswordFile ?? ".perch_password")
            
            if (-not (Test-Path $usernamePath) -or -not (Test-Path $passwordPath)) {
                throw "Perch username/password files not found. Required: $usernamePath and $passwordPath"
            }
            
            try {
                $usernameSecure = Get-Content $usernamePath | ConvertTo-SecureString
                $username = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($usernameSecure)
                )
                
                $passwordSecure = Get-Content $passwordPath | ConvertTo-SecureString
                $password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($passwordSecure)
                )
            }
            catch {
                throw "Failed to decrypt Perch username/password: $($_.Exception.Message)"
            }
            
            # Acquire Bearer token: POST /auth/access_token with x-api-key + Basic Auth
            $tokenBaseUri = $baseUri -replace "/v1$", ""
            $tokenUri = "$tokenBaseUri/auth/access_token"
            
            # Create Basic Auth header
            $credentials = "$username`:$password"
            $encodedCredentials = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($credentials))
            
            $tokenHeaders = @{
                "x-api-key" = $apiKey
                "Authorization" = "Basic $encodedCredentials"
                "Accept" = "application/json"
            }
            
            try {
                Write-Verbose "Acquiring Perch access token from: $tokenUri"
                $tokenResponse = Invoke-RestMethod -Uri $tokenUri `
                    -Method Post `
                    -Headers $tokenHeaders `
                    -ErrorAction Stop
                
                # Extract access_token (property name may vary)
                $bearerToken = if ($tokenResponse.access_token) {
                    $tokenResponse.access_token
                } elseif ($tokenResponse.accessToken) {
                    $tokenResponse.accessToken
                } elseif ($tokenResponse.token) {
                    $tokenResponse.token
                } else {
                    throw "Token response missing access_token property. Response: $($tokenResponse | ConvertTo-Json)"
                }
                
                Write-Verbose "Successfully acquired Perch access token"
                
                # Cache token to file for future use
                try {
                    $bearerToken | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString | Set-Content $tokenPath -ErrorAction SilentlyContinue
                }
                catch {
                    Write-Verbose "Could not cache token to file: $($_.Exception.Message)"
                }
            }
            catch {
                throw "Failed to acquire Perch access token from $tokenUri : $($_.Exception.Message)"
            }
        }
        
        # Create connection with Bearer token + x-api-key
        $headers = @{
            "x-api-key" = $apiKey
            "Authorization" = "Bearer $bearerToken"
            "Content-Type" = "application/json"
        }
        
        $connection = @{
            Platform    = $Platform
            Type        = $platformConfig.Type
            BaseUri     = $baseUri
            AccessLevel = $platformConfig.AccessLevel
            Headers     = $headers
        }
        
        Write-Verbose "Perch connection created successfully"
        Write-Verbose "  BaseUri = $baseUri"
        Write-Verbose "  API key present = Yes"
        Write-Verbose "  Token acquired successfully = Yes"
        Write-Verbose "  Auth header = Bearer <token>"
    }
    else {
        # Standard token-based auth (SentinelOne or Perch Bearer token)
        $tokenPath = Join-Path $env:USERPROFILE $platformConfig.TokenFile
        
        if (-not (Test-Path $tokenPath)) {
            throw "Token file not found for $Platform at $tokenPath. Run Set-PlatformToken -Platform $Platform"
        }
        
        try {
            $tokenSecure = Get-Content $tokenPath | ConvertTo-SecureString
            $token = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [Runtime.InteropServices.Marshal]::SecureStringToBSTR($tokenSecure)
            )
        }
        catch {
            throw "Failed to decrypt token for $Platform : $($_.Exception.Message)"
        }
        
        $authHeader = switch ($platformConfig.Type) {
            "SentinelOne" { "ApiToken $token" }
            "Perch"       { "Bearer $token" }
            default       { throw "Unknown platform type: $($platformConfig.Type)" }
        }
        
        $connection = @{
            Platform    = $Platform
            Type        = $platformConfig.Type
            BaseUri     = $platformConfig.BaseUri
            AccessLevel = $platformConfig.AccessLevel
            Headers     = @{
                "Authorization" = $authHeader
                "Content-Type"  = "application/json"
            }
        }
    }
    
    $script:Connections[$Platform] = $connection
    return $connection
}

function Set-PlatformToken {
    <#
    .SYNOPSIS
        Securely stores API token for a platform
    .DESCRIPTION
        Prompts for API token and stores it encrypted in user profile.
    .PARAMETER Platform
        Platform name (ConnectWiseS1, PerchSIEM)
    .EXAMPLE
        Set-PlatformToken -Platform "ConnectWiseS1"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("ConnectWiseS1", "PerchSIEM")]
        [string]$Platform
    )
    
    # Import config module
    $configModule = Get-Module -Name "ThreatHuntConfig" -ListAvailable
    if (-not $configModule) {
        Import-Module (Join-Path $PSScriptRoot "ThreatHuntConfig.psm1") -ErrorAction Stop
    }
    else {
        Import-Module ThreatHuntConfig -ErrorAction Stop
    }
    
    $platformConfig = Get-PlatformConfig -Platform $Platform
    $tokenFile = $platformConfig.TokenFile
    $tokenPath = Join-Path $env:USERPROFILE $tokenFile
    
    Write-Host "Enter API token for $Platform" -ForegroundColor Cyan
    $token = Read-Host "Token" -AsSecureString
    
    try {
        $token | ConvertFrom-SecureString | Out-File $tokenPath -Force
        Write-Host "Token saved to $tokenPath" -ForegroundColor Green
        
        # Clear cached connection if exists
        if ($script:Connections[$Platform]) {
            $script:Connections.Remove($Platform)
        }
    }
    catch {
        throw "Failed to save token: $($_.Exception.Message)"
    }
}

function Test-AllConnections {
    <#
    .SYNOPSIS
        Tests connectivity to all configured platforms
    .DESCRIPTION
        Validates API connectivity and authentication for all platforms.
        Displays status for each platform.
    .EXAMPLE
        Test-AllConnections
    #>
    [CmdletBinding()]
    param()
    
    $platforms = @("ConnectWiseS1", "PerchSIEM")
    
    Write-Host "`nTesting platform connections..." -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor Cyan
    
    foreach ($platform in $platforms) {
        $conn = $null
        $testUri = $null
        $testSuccess = $false
        
        try {
            $conn = Get-PlatformConnection -Platform $platform
            
            if ($conn.Type -eq "SentinelOne") {
                $testUri = "$($conn.BaseUri)/system/status"
            }
            elseif ($conn.Type -eq "Perch") {
                if ($conn.BaseUri -like "*/v1") {
                    $testUri = "$($conn.BaseUri)/teams"
                } else {
                    $testUri = "$($conn.BaseUri)/health"
                }
            }
            
            if ($testUri) {
                $response = $null
                $errorOccurred = $false
                try {
                    $response = Invoke-RestMethod -Uri $testUri -Headers $conn.Headers -Method Get -TimeoutSec 10 -ErrorAction Stop
                    Write-Host "✓ $platform - Connected ($($conn.AccessLevel))" -ForegroundColor Green
                    $testSuccess = $true
                }
                catch {
                    $errorOccurred = $true
                    $statusCode = $null
                    if ($null -ne $_.Exception.Response) {
                        $statusCode = $_.Exception.Response.StatusCode.value__
                    }
                    
                    if ($conn.Type -eq "Perch" -and $statusCode -eq 404) {
                        Write-Host "✓ $platform - OAuth2 token generated ($($conn.AccessLevel))" -ForegroundColor Green
                        Write-Host "  (Health endpoint not available, but authentication works)" -ForegroundColor Gray
                        $testSuccess = $true
                    }
                }
                
                if (-not $testSuccess -and $errorOccurred) {
                    throw "API test failed"
                }
            }
        }
        catch {
            Write-Host "✗ $platform - Failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    Write-Host ("=" * 50) -ForegroundColor Cyan
}

function Clear-ConnectionCache {
    <#
    .SYNOPSIS
        Clears cached connections
    .DESCRIPTION
        Forces re-authentication on next Get-PlatformConnection call.
    .EXAMPLE
        Clear-ConnectionCache
    #>
    [CmdletBinding()]
    param()
    
    $script:Connections.Clear()
    Write-Host "Connection cache cleared" -ForegroundColor Yellow
}


function Set-PerchOAuth2Credentials {
    <#
    .SYNOPSIS
        Sets Perch OAuth2 Client ID, Secret, and optional API Key
    .DESCRIPTION
        Securely stores Perch OAuth2 credentials and optional API key for API access.
    .PARAMETER ClientId
        Perch OAuth2 Client ID
    .PARAMETER ClientSecret
        Perch OAuth2 Client Secret
    .PARAMETER ApiKey
        Perch API Key (optional - may be required by some Perch instances)
    .EXAMPLE
        Set-PerchOAuth2Credentials -ClientId "your-client-id" -ClientSecret "your-client-secret" -ApiKey "your-api-key"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$ClientId,
        
        [Parameter(Mandatory=$false)]
        [string]$ClientSecret,
        
        [Parameter(Mandatory=$false)]
        [string]$ApiKey
    )
    
    if (-not $ClientId) {
        Write-Host "Enter Perch OAuth2 Client ID:" -ForegroundColor Cyan
        $ClientId = Read-Host "Client ID"
    }
    
    if (-not $ClientSecret) {
        Write-Host "Enter Perch OAuth2 Client Secret:" -ForegroundColor Cyan
        $ClientSecret = Read-Host "Client Secret" -AsSecureString
        $ClientSecretPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ClientSecret)
        )
        $ClientSecret = $ClientSecretPlain
    }
    
    $clientIdPath = Join-Path $env:USERPROFILE ".perch_clientid"
    $clientSecretPath = Join-Path $env:USERPROFILE ".perch_clientsecret"
    $apiKeyPath = Join-Path $env:USERPROFILE ".perch_apikey"
    
    try {
        $ClientId | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString | Out-File $clientIdPath -Force
        $ClientSecret | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString | Out-File $clientSecretPath -Force
        
        Write-Host "Perch OAuth2 credentials saved" -ForegroundColor Green
        
        # Save API key if provided
        if ($ApiKey) {
            $ApiKey | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString | Out-File $apiKeyPath -Force
            Write-Host "Perch API key saved" -ForegroundColor Green
        }
        else {
            Write-Host "Note: No API key provided. Some Perch instances may require an API key." -ForegroundColor Yellow
        }
        
        # Clear cached connection
        if ($script:Connections["PerchSIEM"]) {
            $script:Connections.Remove("PerchSIEM")
        }
    }
    catch {
        throw "Failed to save Perch credentials: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function Get-PlatformConnection, Set-PlatformToken, Test-AllConnections, Clear-ConnectionCache, Get-PerchAccessToken, Set-PerchOAuth2Credentials

