<#
.SYNOPSIS
    SentinelOne Deep Visibility Threat Hunting Module
.DESCRIPTION
    Provides functions for querying SentinelOne Deep Visibility and
    performing IOC-based threat hunts across endpoints.
.NOTES
    Author: River Run Security Team
    Version: 1.0
#>

function Invoke-S1DeepVisibility {
    <#
    .SYNOPSIS
        Executes a Deep Visibility query with polling
    .DESCRIPTION
        Initializes a DV query, polls for completion, and returns results.
    .PARAMETER Connection
        Platform connection object from Get-PlatformConnection
    .PARAMETER Query
        Deep Visibility query string
    .PARAMETER SiteId
        Site ID to query (optional, queries all sites if not specified)
    .PARAMETER DaysBack
        Number of days to look back (default: 14)
    .PARAMETER Limit
        Maximum number of results to return (default: 1000)
    .EXAMPLE
        $conn = Get-PlatformConnection -Platform "ConnectWiseS1"
        Invoke-S1DeepVisibility -Connection $conn -Query "SHA1 = 'abc123...'" -SiteId "1234567890"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Connection,
        
        [Parameter(Mandatory=$true)]
        [string]$Query,
        
        [Parameter(Mandatory=$false)]
        [string]$SiteId,
        
        [Parameter(Mandatory=$false)]
        [int]$DaysBack = 14,
        
        [Parameter(Mandatory=$false)]
        [int]$Limit = 1000
    )
    
    $fromDate = (Get-Date).AddDays(-$DaysBack).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $toDate = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    
    # Build query body
    $body = @{
        query     = $Query
        fromDate  = $fromDate
        toDate    = $toDate
        limit     = $Limit
    }
    
    if ($SiteId) {
        $body.siteIds = @($SiteId)
    }
    
    # Initialize query
    try {
        $initResponse = Invoke-RestMethod -Uri "$($Connection.BaseUri)/dv/init-query" `
            -Method Post -Headers $Connection.Headers `
            -Body ($body | ConvertTo-Json -Depth 10) `
            -ErrorAction Stop
        
        $queryId = $initResponse.data.queryId
        Write-Verbose "Query initiated: $queryId"
    }
    catch {
        throw "Failed to initialize DV query: $($_.Exception.Message)"
    }
    
    # Poll for completion
    $maxAttempts = 60
    $attempt = 0
    $status = $null
    
    do {
        Start-Sleep -Seconds 2
        $attempt++
        
        try {
            $statusResponse = Invoke-RestMethod -Uri "$($Connection.BaseUri)/dv/query-status?queryId=$queryId" `
                -Method Get -Headers $Connection.Headers -ErrorAction Stop
            
            $status = $statusResponse.data.responseState
            Write-Verbose "Query status ($attempt/$maxAttempts): $status"
        }
        catch {
            throw "Failed to check query status: $($_.Exception.Message)"
        }
        
        if ($attempt -ge $maxAttempts) {
            throw "Query timed out after $($maxAttempts * 2) seconds"
        }
    } while ($status -eq "RUNNING")
    
    if ($status -ne "SUCCESS") {
        throw "Query failed with status: $status"
    }
    
    # Get results
    try {
        $resultsResponse = Invoke-RestMethod -Uri "$($Connection.BaseUri)/dv/events?queryId=$queryId&limit=$Limit" `
            -Method Get -Headers $Connection.Headers -ErrorAction Stop
        
        return $resultsResponse.data
    }
    catch {
        throw "Failed to retrieve query results: $($_.Exception.Message)"
    }
}

function Build-S1Query {
    <#
    .SYNOPSIS
        Builds a Deep Visibility query from IOC
    .DESCRIPTION
        Converts an IOC object to SentinelOne Deep Visibility query syntax
    .PARAMETER IOC
        IOC object with Type and Value properties
    .EXAMPLE
        $ioc = @{ Type = "hash"; Value = "abc123..." }
        Build-S1Query -IOC $ioc
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$IOC
    )
    
    $type = $IOC.Type.ToLower()
    $value = $IOC.Value
    
    switch ($type) {
        "hash" {
            # Try to detect hash type
            if ($value.Length -eq 64) {
                return "SHA256 = `"$value`" OR SHA1 = `"$value`" OR MD5 = `"$value`""
            }
            elseif ($value.Length -eq 40) {
                return "SHA1 = `"$value`" OR SHA256 = `"$value`" OR MD5 = `"$value`""
            }
            elseif ($value.Length -eq 32) {
                return "MD5 = `"$value`" OR SHA1 = `"$value`" OR SHA256 = `"$value`""
            }
            else {
                return "SHA256 = `"$value`" OR SHA1 = `"$value`" OR MD5 = `"$value`""
            }
        }
        "ip" {
            return "DstIP = `"$value`" OR SrcIP = `"$value`""
        }
        "domain" {
            return "DNS Contains `"$value`""
        }
        "process" {
            return "ProcessName Contains `"$value`""
        }
        "cmdline" {
            return "CmdLine Contains `"$value`""
        }
        "filepath" {
            return "FilePath Contains `"$value`""
        }
        default {
            throw "Unsupported IOC type: $type"
        }
    }
}

function Hunt-S1FileHash {
    <#
    .SYNOPSIS
        Hunts for file hash in SentinelOne Deep Visibility
    .PARAMETER Connection
        Platform connection object
    .PARAMETER Hash
        File hash (SHA1, SHA256, or MD5)
    .PARAMETER SiteId
        Site ID (optional)
    .PARAMETER DaysBack
        Days to look back (default: 14)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Connection,
        
        [Parameter(Mandatory=$true)]
        [string]$Hash,
        
        [Parameter(Mandatory=$false)]
        [string]$SiteId,
        
        [Parameter(Mandatory=$false)]
        [int]$DaysBack = 14
    )
    
    $ioc = @{ Type = "hash"; Value = $Hash }
    $query = Build-S1Query -IOC $ioc
    return Invoke-S1DeepVisibility -Connection $Connection -Query $query -SiteId $SiteId -DaysBack $DaysBack
}

function Hunt-S1IPAddress {
    <#
    .SYNOPSIS
        Hunts for IP address in SentinelOne Deep Visibility
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Connection,
        
        [Parameter(Mandatory=$true)]
        [string]$IP,
        
        [Parameter(Mandatory=$false)]
        [string]$SiteId,
        
        [Parameter(Mandatory=$false)]
        [int]$DaysBack = 14
    )
    
    $ioc = @{ Type = "ip"; Value = $IP }
    $query = Build-S1Query -IOC $ioc
    return Invoke-S1DeepVisibility -Connection $Connection -Query $query -SiteId $SiteId -DaysBack $DaysBack
}

function Hunt-S1Domain {
    <#
    .SYNOPSIS
        Hunts for domain in SentinelOne Deep Visibility
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Connection,
        
        [Parameter(Mandatory=$true)]
        [string]$Domain,
        
        [Parameter(Mandatory=$false)]
        [string]$SiteId,
        
        [Parameter(Mandatory=$false)]
        [int]$DaysBack = 14
    )
    
    $ioc = @{ Type = "domain"; Value = $Domain }
    $query = Build-S1Query -IOC $ioc
    return Invoke-S1DeepVisibility -Connection $Connection -Query $query -SiteId $SiteId -DaysBack $DaysBack
}

function Hunt-S1Process {
    <#
    .SYNOPSIS
        Hunts for process name in SentinelOne Deep Visibility
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Connection,
        
        [Parameter(Mandatory=$true)]
        [string]$ProcessName,
        
        [Parameter(Mandatory=$false)]
        [string]$SiteId,
        
        [Parameter(Mandatory=$false)]
        [int]$DaysBack = 14
    )
    
    $ioc = @{ Type = "process"; Value = $ProcessName }
    $query = Build-S1Query -IOC $ioc
    return Invoke-S1DeepVisibility -Connection $Connection -Query $query -SiteId $SiteId -DaysBack $DaysBack
}

function Hunt-S1CommandLine {
    <#
    .SYNOPSIS
        Hunts for command line pattern in SentinelOne Deep Visibility
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Connection,
        
        [Parameter(Mandatory=$true)]
        [string]$CmdPattern,
        
        [Parameter(Mandatory=$false)]
        [string]$SiteId,
        
        [Parameter(Mandatory=$false)]
        [int]$DaysBack = 14
    )
    
    $ioc = @{ Type = "cmdline"; Value = $CmdPattern }
    $query = Build-S1Query -IOC $ioc
    return Invoke-S1DeepVisibility -Connection $Connection -Query $query -SiteId $SiteId -DaysBack $DaysBack
}

function Get-S1Sites {
    <#
    .SYNOPSIS
        Retrieves all SentinelOne sites
    .DESCRIPTION
        Lists all sites (companies/organizations) from SentinelOne platform.
        Useful for discovering clients and their site IDs.
    .PARAMETER Connection
        Platform connection object from Get-PlatformConnection (optional if Platform is provided)
    .PARAMETER Platform
        Platform name (ConnectWiseS1) - will get connection automatically
    .PARAMETER SiteName
        Optional filter by site name (partial match)
    .EXAMPLE
        $conn = Get-PlatformConnection -Platform "ConnectWiseS1"
        Get-S1Sites -Connection $conn
    .EXAMPLE
        Get-S1Sites -Platform "ConnectWiseS1"
    .EXAMPLE
        Get-S1Sites -Connection $conn -SiteName "Acme"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [hashtable]$Connection,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("ConnectWiseS1")]
        [string]$Platform,
        
        [Parameter(Mandatory=$false)]
        [string]$SiteName
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
        
        $baseUri = $Connection.BaseUri.ToString().Trim()
        if ([string]::IsNullOrWhiteSpace($baseUri)) {
            throw "BaseUri is empty or null"
        }
        
        # Ensure BaseUri doesn't end with a slash
        $baseUri = $baseUri.TrimEnd('/')
        
        $baseUriPath = "$baseUri/sites"
        Write-Verbose "Querying SentinelOne sites from: $baseUriPath"
        
        $allSites = @()
        $cursor = $null
        $maxPages = 100  # Safety limit
        
        do {
            # Build URI - SentinelOne uses cursor-based pagination, not offset
            if ($cursor) {
                # URL encode the cursor for query parameter using PowerShell's built-in method
                $encodedCursor = [System.Uri]::EscapeDataString($cursor)
                # Use string concatenation to avoid PowerShell parsing issues
                $fullUri = $baseUriPath + "?cursor=" + $encodedCursor
            }
            else {
                $fullUri = $baseUriPath
            }
            
            Write-Verbose "Requesting: $fullUri"
            
            try {
                $response = Invoke-RestMethod -Uri $fullUri `
                    -Method Get -Headers $Connection.Headers -ErrorAction Stop
                
                # Extract sites from response.data.sites (not response.data)
                if ($response.data -and $response.data.sites) {
                    $allSites += $response.data.sites
                    Write-Verbose "Retrieved $($response.data.sites.Count) sites (total: $($allSites.Count))"
                }
                elseif ($response.data) {
                    # Fallback: some API versions might return sites directly in data
                    $allSites += $response.data
                }
                elseif ($response.sites) {
                    # Another fallback pattern
                    $allSites += $response.sites
                }
                
                # Check for pagination using nextCursor
                $cursor = $null
                if ($response.pagination -and $response.pagination.nextCursor) {
                    $cursor = $response.pagination.nextCursor
                    Write-Verbose "More pages available, cursor: $cursor"
                }
                else {
                    Write-Verbose "No more pages"
                    break
                }
            }
            catch {
                $statusCode = $null
                $errorBody = $null
                
                if ($_.Exception.Response) {
                    $statusCode = $_.Exception.Response.StatusCode.value__
                    
                    # Try to read error response body
                    try {
                        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                        $errorBody = $reader.ReadToEnd()
                        $reader.Close()
                    }
                    catch {
                        $errorBody = "Unable to read error response"
                    }
                }
                
                if ($statusCode -eq 401) {
                    throw "Authentication failed (401). Your API token may be expired. Run: Set-PlatformToken -Platform ConnectWiseS1"
                }
                elseif ($statusCode -eq 400) {
                    $errorMsg = "Bad Request (400). The API request format may be incorrect."
                    if ($errorBody) {
                        $errorMsg += " Error details: $errorBody"
                    }
                    $errorMsg += " URI: $fullUri"
                    throw $errorMsg
                }
                else {
                    $errorMsg = "HTTP $statusCode : $($_.Exception.Message)"
                    if ($errorBody) {
                        $errorMsg += " Response: $errorBody"
                    }
                    throw $errorMsg
                }
            }
            
            $maxPages--
            if ($maxPages -le 0) {
                Write-Warning "Reached maximum page limit (100). There may be more sites available."
                break
            }
        } while ($cursor)
        
        # Filter by site name if provided
        if ($SiteName) {
            $allSites = $allSites | Where-Object { 
                $_.name -like "*$SiteName*" -or $_.siteName -like "*$SiteName*" 
            }
        }
        
        return $allSites | ForEach-Object {
            [PSCustomObject]@{
                SiteId      = $_.id
                SiteName    = if ($_.name) { $_.name } else { $_.siteName }
                CreatedAt   = $_.createdAt
                TotalAgents = $_.totalAgents
                ActiveAgents = $_.activeAgents
                InactiveAgents = $_.inactiveAgents
                HealthStatus = $_.healthStatus
                AccountName = $_.accountName
            }
        }
    }
    catch {
        throw "Failed to retrieve SentinelOne sites: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function Invoke-S1DeepVisibility, Build-S1Query, Hunt-S1FileHash, Hunt-S1IPAddress, Hunt-S1Domain, Hunt-S1Process, Hunt-S1CommandLine, Get-S1Sites

