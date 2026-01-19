<#
.SYNOPSIS
    SentinelOne Exclusions Management Module
.DESCRIPTION
    Manages SentinelOne exclusions for ConnectWise S1 platform only.
    Provides CRUD operations for exclusions and integration with false positive system.
.NOTES
    Author: River Run Security Team
    Version: 1.0
#>

function Get-S1Exclusions {
    <#
    .SYNOPSIS
        Lists all exclusions for a site/client
    .DESCRIPTION
        Retrieves exclusions from SentinelOne for specified site.
    .PARAMETER Connection
        Platform connection object
    .PARAMETER SiteId
        Site ID to filter exclusions (optional)
    .PARAMETER ExclusionType
        Filter by exclusion type (optional)
    .EXAMPLE
        $conn = Get-PlatformConnection -Platform "ConnectWiseS1"
        Get-S1Exclusions -Connection $conn -SiteId "1234567890"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Connection,
        
        [Parameter(Mandatory=$false)]
        [string]$SiteId,
        
        [Parameter(Mandatory=$false)]
        [string]$ExclusionType
    )
    
    $uri = "$($Connection.BaseUri)/exclusions"
    $queryParams = @()
    
    if ($SiteId) {
        $queryParams += "siteIds=$SiteId"
    }
    
    if ($ExclusionType) {
        $queryParams += "type=$ExclusionType"
    }
    
    if ($queryParams.Count -gt 0) {
        $uri += "?" + ($queryParams -join "&")
    }
    
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $Connection.Headers -ErrorAction Stop
        return $response.data
    }
    catch {
        throw "Failed to retrieve exclusions: $($_.Exception.Message)"
    }
}

function New-S1Exclusion {
    <#
    .SYNOPSIS
        Creates a new SentinelOne exclusion
    .DESCRIPTION
        Creates exclusion for file hash, path, process, command line, etc.
    .PARAMETER Connection
        Platform connection object (must be ConnectWiseS1)
    .PARAMETER ExclusionType
        Type of exclusion (hash, path, process, cmdline, certificate, browser_extension)
    .PARAMETER Value
        Exclusion value (hash, path pattern, process name, etc.)
    .PARAMETER SiteId
        Site ID for site-specific exclusion (optional, account-wide if not specified)
    .PARAMETER Description
        Description/justification for exclusion
    .EXAMPLE
        New-S1Exclusion -Connection $conn -ExclusionType "hash" -Value "abc123..." -Description "Authorized tool"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Connection,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet("hash", "path", "process", "cmdline", "certificate", "browser_extension")]
        [string]$ExclusionType,
        
        [Parameter(Mandatory=$true)]
        [string]$Value,
        
        [Parameter(Mandatory=$false)]
        [string]$SiteId,
        
        [Parameter(Mandatory=$false)]
        [string]$Description
    )
    
    # Validate connection is read/write
    if ($Connection.AccessLevel -ne "ReadWrite") {
        throw "Exclusions can only be created on ReadWrite platforms (ConnectWiseS1)"
    }
    
    $body = @{
        type = $ExclusionType
        value = $Value
    }
    
    if ($SiteId) {
        $body.siteIds = @($SiteId)
    }
    
    if ($Description) {
        $body.description = $Description
    }
    
    try {
        $response = Invoke-RestMethod -Uri "$($Connection.BaseUri)/exclusions" `
            -Method Post -Headers $Connection.Headers `
            -Body ($body | ConvertTo-Json -Depth 10) `
            -ErrorAction Stop
        
        Write-Host "Exclusion created: $($response.data.id)" -ForegroundColor Green
        return $response.data
    }
    catch {
        throw "Failed to create exclusion: $($_.Exception.Message)"
    }
}

function Remove-S1Exclusion {
    <#
    .SYNOPSIS
        Deletes an exclusion by ID
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Connection,
        
        [Parameter(Mandatory=$true)]
        [string]$ExclusionId
    )
    
    if ($Connection.AccessLevel -ne "ReadWrite") {
        throw "Exclusions can only be deleted on ReadWrite platforms"
    }
    
    try {
        $response = Invoke-RestMethod -Uri "$($Connection.BaseUri)/exclusions/$ExclusionId" `
            -Method Delete -Headers $Connection.Headers `
            -ErrorAction Stop
        
        Write-Host "Exclusion deleted: $ExclusionId" -ForegroundColor Green
        return $true
    }
    catch {
        throw "Failed to delete exclusion: $($_.Exception.Message)"
    }
}

function Test-S1ExclusionExists {
    <#
    .SYNOPSIS
        Checks if exclusion already exists
    .DESCRIPTION
        Searches existing exclusions to prevent duplicates.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Connection,
        
        [Parameter(Mandatory=$true)]
        [string]$Value,
        
        [Parameter(Mandatory=$false)]
        [string]$SiteId
    )
    
    $exclusions = Get-S1Exclusions -Connection $Connection -SiteId $SiteId
    
    foreach ($exclusion in $exclusions) {
        if ($exclusion.value -eq $Value) {
            return $true
        }
    }
    
    return $false
}

function Convert-FalsePositiveToExclusion {
    <#
    .SYNOPSIS
        Creates exclusion from false positive record
    .DESCRIPTION
        Converts a false positive IOC to a SentinelOne exclusion.
    .PARAMETER Connection
        Platform connection object
    .PARAMETER FalsePositive
        False positive object with IOC and IOCType properties
    .PARAMETER SiteId
        Site ID for exclusion
    .PARAMETER Description
        Description for exclusion
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Connection,
        
        [Parameter(Mandatory=$true)]
        [object]$FalsePositive,
        
        [Parameter(Mandatory=$false)]
        [string]$SiteId,
        
        [Parameter(Mandatory=$false)]
        [string]$Description
    )
    
    # Map IOC type to exclusion type
    $exclusionType = switch ($FalsePositive.IOCType.ToLower()) {
        "hash"    { "hash" }
        "process" { "process" }
        "cmdline" { "cmdline" }
        "filepath" { "path" }
        default   { throw "Cannot convert IOC type $($FalsePositive.IOCType) to exclusion" }
    }
    
    if (-not $Description) {
        $Description = "False positive: $($FalsePositive.Reason)"
    }
    
    # Check if already exists
    if (Test-S1ExclusionExists -Connection $Connection -Value $FalsePositive.IOC -SiteId $SiteId) {
        Write-Warning "Exclusion already exists for $($FalsePositive.IOC)"
        return $null
    }
    
    return New-S1Exclusion -Connection $Connection -ExclusionType $exclusionType `
        -Value $FalsePositive.IOC -SiteId $SiteId -Description $Description
}

function Get-S1ExclusionTypes {
    <#
    .SYNOPSIS
        Lists available exclusion types
    #>
    [CmdletBinding()]
    param()
    
    return @(
        @{ Type = "hash"; Description = "File hash (SHA1/SHA256/MD5)" }
        @{ Type = "path"; Description = "File path (supports wildcards)" }
        @{ Type = "process"; Description = "Process name" }
        @{ Type = "cmdline"; Description = "Command line pattern" }
        @{ Type = "certificate"; Description = "Certificate thumbprint" }
        @{ Type = "browser_extension"; Description = "Browser extension ID" }
    )
}

Export-ModuleMember -Function Get-S1Exclusions, New-S1Exclusion, Remove-S1Exclusion, Test-S1ExclusionExists, Convert-FalsePositiveToExclusion, Get-S1ExclusionTypes

