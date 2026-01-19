<#
.SYNOPSIS
    Perch SIEM Threat Hunting Module
.DESCRIPTION
    Provides functions for querying Perch SIEM logs and performing
    IOC-based threat hunts across network and log sources.
.NOTES
    Author: River Run Security Team
    Version: 1.0
#>

function Search-PerchLogs {
    <#
    .SYNOPSIS
        Generic Perch log search function
    .DESCRIPTION
        Searches Perch SIEM logs using query syntax and returns matching events.
    .PARAMETER Connection
        Platform connection object from Get-PlatformConnection
    .PARAMETER Query
        Perch query string
    .PARAMETER TeamId
        Perch team/organization ID
    .PARAMETER StartTime
        Start time for search (default: 14 days ago)
    .PARAMETER EndTime
        End time for search (default: now)
    .PARAMETER LogSources
        Array of log source names to filter (optional)
    .PARAMETER Limit
        Maximum number of results (default: 1000)
    .EXAMPLE
        $conn = Get-PlatformConnection -Platform "PerchSIEM"
        Search-PerchLogs -Connection $conn -Query "src_ip:192.168.1.100" -TeamId "team-123"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Connection,
        
        [Parameter(Mandatory=$true)]
        [string]$Query,
        
        [Parameter(Mandatory=$false)]
        [string]$TeamId,
        
        [Parameter(Mandatory=$false)]
        [datetime]$StartTime = (Get-Date).AddDays(-14),
        
        [Parameter(Mandatory=$false)]
        [datetime]$EndTime = (Get-Date),
        
        [Parameter(Mandatory=$false)]
        [string[]]$LogSources,
        
        [Parameter(Mandatory=$false)]
        [int]$Limit = 1000
    )
    
    $body = @{
        query      = $Query
        start_time = $StartTime.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        end_time   = $EndTime.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        limit      = $Limit
    }
    
    if ($TeamId) {
        $body.team_id = $TeamId
    }
    
    if ($LogSources) {
        $body.sources = $LogSources
    }
    
    try {
        # Ensure BaseUri uses /v1/ path
        $baseUri = $Connection.BaseUri.ToString().Trim().TrimEnd('/')
        if (-not $baseUri -like "*/v1*") {
            $baseUri = $baseUri.TrimEnd('/') + "/v1"
        }
        # Ensure BaseUri is api.perch.rocks (not api.perchsecurity.com)
        if ($baseUri -like "*perchsecurity.com*") {
            $baseUri = $baseUri -replace "perchsecurity\.com", "perch.rocks"
        }
        
        $response = Invoke-RestMethod -Uri "$baseUri/logs/search" `
            -Method Post -Headers $Connection.Headers `
            -Body ($body | ConvertTo-Json -Depth 10) `
            -ErrorAction Stop
        
        return $response.data
    }
    catch {
        throw "Failed to search Perch logs: $($_.Exception.Message)"
    }
}

function Hunt-PerchIP {
    <#
    .SYNOPSIS
        Hunts for IP address in Perch SIEM logs
    .DESCRIPTION
        Searches firewall, auth, and network logs for IP address activity.
    .PARAMETER Connection
        Platform connection object
    .PARAMETER IP
        IP address to search for
    .PARAMETER TeamId
        Perch team ID
    .PARAMETER DaysBack
        Days to look back (default: 14)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Connection,
        
        [Parameter(Mandatory=$true)]
        [string]$IP,
        
        [Parameter(Mandatory=$false)]
        [string]$TeamId,
        
        [Parameter(Mandatory=$false)]
        [int]$DaysBack = 14
    )
    
    $query = "src_ip:$IP OR dst_ip:$IP OR client_ip:$IP OR remote_ip:$IP"
    $startTime = (Get-Date).AddDays(-$DaysBack)
    
    return Search-PerchLogs -Connection $Connection -Query $query -TeamId $TeamId -StartTime $startTime
}

function Hunt-PerchDomain {
    <#
    .SYNOPSIS
        Hunts for domain in Perch SIEM logs
    .DESCRIPTION
        Searches DNS, URL, and email logs for domain activity.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Connection,
        
        [Parameter(Mandatory=$true)]
        [string]$Domain,
        
        [Parameter(Mandatory=$false)]
        [string]$TeamId,
        
        [Parameter(Mandatory=$false)]
        [int]$DaysBack = 14
    )
    
    $query = "domain:*$Domain* OR query:*$Domain* OR url:*$Domain* OR sender_domain:$Domain"
    $startTime = (Get-Date).AddDays(-$DaysBack)
    
    return Search-PerchLogs -Connection $Connection -Query $query -TeamId $TeamId -StartTime $startTime
}

function Hunt-PerchUser {
    <#
    .SYNOPSIS
        Hunts for username in Perch SIEM logs
    .DESCRIPTION
        Searches authentication and cloud app logs for user activity.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Connection,
        
        [Parameter(Mandatory=$true)]
        [string]$Username,
        
        [Parameter(Mandatory=$false)]
        [string]$TeamId,
        
        [Parameter(Mandatory=$false)]
        [int]$DaysBack = 14
    )
    
    $query = "user:$Username OR username:$Username OR account:$Username"
    $startTime = (Get-Date).AddDays(-$DaysBack)
    
    return Search-PerchLogs -Connection $Connection -Query $query -TeamId $TeamId -StartTime $startTime
}

function Hunt-PerchHash {
    <#
    .SYNOPSIS
        Hunts for file hash in Perch SIEM logs
    .DESCRIPTION
        Searches email attachment and file transfer logs for hash matches.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Connection,
        
        [Parameter(Mandatory=$true)]
        [string]$Hash,
        
        [Parameter(Mandatory=$false)]
        [string]$TeamId,
        
        [Parameter(Mandatory=$false)]
        [int]$DaysBack = 14
    )
    
    $query = "file_hash:$Hash OR sha256:$Hash OR md5:$Hash"
    $startTime = (Get-Date).AddDays(-$DaysBack)
    
    return Search-PerchLogs -Connection $Connection -Query $query -TeamId $TeamId -StartTime $startTime
}

function Get-PerchAlerts {
    <#
    .SYNOPSIS
        Retrieves Perch alerts
    .DESCRIPTION
        Gets alerts from Perch SIEM filtered by severity and status.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Connection,
        
        [Parameter(Mandatory=$false)]
        [string]$TeamId,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("critical", "high", "medium", "low")]
        [string]$Severity,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("open", "closed", "investigating")]
        [string]$Status = "open",
        
        [Parameter(Mandatory=$false)]
        [datetime]$Since = (Get-Date).AddDays(-14),
        
        [Parameter(Mandatory=$false)]
        [int]$Limit = 100
    )
    
    # Ensure BaseUri uses /v1/ path
    $baseUri = $Connection.BaseUri.ToString().Trim().TrimEnd('/')
    if (-not $baseUri -like "*/v1*") {
        $baseUri = $baseUri.TrimEnd('/') + "/v1"
    }
    # Ensure BaseUri is api.perch.rocks (not api.perchsecurity.com)
    if ($baseUri -like "*perchsecurity.com*") {
        $baseUri = $baseUri -replace "perchsecurity\.com", "perch.rocks"
    }
    
    $queryParams = @(
        "limit=$Limit",
        "status=$Status",
        "created_after=$($Since.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))"
    )
    
    if ($TeamId) {
        $queryParams += "team_id=$TeamId"
    }
    
    if ($Severity) {
        $queryParams += "severity=$Severity"
    }
    
    $uri = "$baseUri/alerts?" + ($queryParams -join "&")
    
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $Connection.Headers -ErrorAction Stop
        return $response.data
    }
    catch {
        throw "Failed to retrieve Perch alerts: $($_.Exception.Message)"
    }
}

function Test-PerchConnection {
    <#
    .SYNOPSIS
        Validates Perch API connection
    .DESCRIPTION
        Tests connectivity to Perch API v1 by calling /v1/access/check/
        Returns connection status and details.
    .PARAMETER Connection
        Platform connection object from Get-PlatformConnection (optional if Platform is provided)
    .PARAMETER Platform
        Platform name (PerchSIEM) - will get connection automatically
    .EXAMPLE
        $conn = Get-PlatformConnection -Platform "PerchSIEM"
        Test-PerchConnection -Connection $conn
    .EXAMPLE
        Test-PerchConnection -Platform "PerchSIEM"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [hashtable]$Connection,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("PerchSIEM")]
        [string]$Platform
    )
    
    # Get connection if Platform provided instead of Connection
    if (-not $Connection -and $Platform) {
        $connModule = Get-Module -Name "ConnectionManager" -ListAvailable
        if (-not $connModule) {
            Import-Module (Join-Path $PSScriptRoot "ConnectionManager.psm1") -ErrorAction Stop
        }
        else {
            Import-Module ConnectionManager -ErrorAction Stop
        }
        $Connection = Get-PlatformConnection -Platform $Platform
    }
    
    if (-not $Connection) {
        throw "Either Connection or Platform parameter must be provided"
    }
    
    try {
        # Validate connection object
        if (-not $Connection.BaseUri) {
            throw "Connection object missing BaseUri property"
        }
        
        $baseUri = $Connection.BaseUri.ToString().Trim().TrimEnd('/')
        if ([string]::IsNullOrWhiteSpace($baseUri)) {
            throw "BaseUri is empty or null"
        }
        
        # Ensure BaseUri uses /v1/ path
        if (-not $baseUri -like "*/v1*") {
            $baseUri = $baseUri.TrimEnd('/') + "/v1"
        }
        
        # Ensure BaseUri is api.perch.rocks (not api.perchsecurity.com)
        if ($baseUri -like "*perchsecurity.com*") {
            $baseUri = $baseUri -replace "perchsecurity\.com", "perch.rocks"
        }
        
        # Perch API v1 connectivity check endpoint
        $checkUri = "$baseUri/access/check/"
        
        Write-Verbose "Testing Perch API connection: $checkUri"
        
        $response = Invoke-RestMethod -Uri $checkUri `
            -Method Get `
            -Headers $Connection.Headers `
            -ErrorAction Stop
        
        return [PSCustomObject]@{
            Success = $true
            BaseUri = $baseUri
            StatusCode = 200
            Message = "Perch API connection successful"
            Response = $response
        }
    }
    catch {
        $statusCode = $null
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode.value__
        }
        
        return [PSCustomObject]@{
            Success = $false
            BaseUri = $baseUri
            StatusCode = $statusCode
            Message = "Perch API connection failed: $($_.Exception.Message)"
            Error = $_.Exception.Message
        }
    }
}

Export-ModuleMember -Function Search-PerchLogs, Hunt-PerchIP, Hunt-PerchDomain, Hunt-PerchUser, Hunt-PerchHash, Get-PerchAlerts, Test-PerchConnection

