<#
.SYNOPSIS
    Memberberry Integration Module
.DESCRIPTION
    Integrates with Memberberry to read client exceptions, extract company names
    from tickets, detect alert types, and save hunt results.
.NOTES
    Author: River Run Security Team
    Version: 1.0
#>

$script:MemberberryPath = "C:\git\memberberry"
$script:ExceptionsData = $null

function Get-MemberberryConfig {
    <#
    .SYNOPSIS
        Gets Memberberry configuration path
    .DESCRIPTION
        Returns the path to Memberberry installation and data files.
    #>
    [CmdletBinding()]
    param()
    
    if (-not (Test-Path $script:MemberberryPath)) {
        throw "Memberberry not found at $script:MemberberryPath"
    }
    
    return @{
        Path = $script:MemberberryPath
        ExceptionsFile = Join-Path $script:MemberberryPath "exceptions.json"
        ExtractCompanyScript = Join-Path $script:MemberberryPath "extract-company.ps1"
        DetectAlertTypeScript = Join-Path $script:MemberberryPath "detect-alert-type.ps1"
    }
}

function Get-MemberberryClient {
    <#
    .SYNOPSIS
        Gets client data from Memberberry exceptions.json
    .DESCRIPTION
        Retrieves client-specific exceptions including VPN info, VIP contacts,
        authorized tools, and false positive patterns.
    .PARAMETER ClientName
        Client name as stored in Memberberry
    .EXAMPLE
        Get-MemberberryClient -ClientName "Acme Corp"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ClientName
    )
    
    $config = Get-MemberberryConfig
    $exceptionsFile = $config.ExceptionsFile
    
    if (-not (Test-Path $exceptionsFile)) {
        Write-Warning "Memberberry exceptions.json not found at $exceptionsFile"
        return $null
    }
    
    try {
        if (-not $script:ExceptionsData) {
            $script:ExceptionsData = Get-Content $exceptionsFile -Raw | ConvertFrom-Json
        }
        
        if ($script:ExceptionsData.PSObject.Properties.Name -contains $ClientName) {
            return $script:ExceptionsData.$ClientName
        }
        
        return $null
    }
    catch {
        Write-Warning "Failed to load Memberberry exceptions: $($_.Exception.Message)"
        return $null
    }
}

function Get-ClientFromMemberberry {
    <#
    .SYNOPSIS
        Extracts client name from ticket using Memberberry's extract-company.ps1
    .DESCRIPTION
        Uses Memberberry's company extraction logic to identify client from ticket text.
    .PARAMETER TicketText
        Ticket text or ConnectWise ticket object
    .EXAMPLE
        $client = Get-ClientFromMemberberry -TicketText $ticketContent
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$TicketText
    )
    
    $config = Get-MemberberryConfig
    
    # Extract text if ticket object
    $text = if ($TicketText -is [string]) {
        $TicketText
    }
    else {
        $textParts = @()
        if ($TicketText.summary) { $textParts += $TicketText.summary }
        if ($TicketText.initialDescription) { $textParts += $TicketText.initialDescription }
        $textParts -join "`n"
    }
    
    if (-not (Test-Path $config.ExtractCompanyScript)) {
        Write-Warning "Memberberry extract-company.ps1 not found"
        return $null
    }
    
    try {
        $clientName = & $config.ExtractCompanyScript -TicketText $text
        return $clientName
    }
    catch {
        Write-Warning "Failed to extract company from Memberberry: $($_.Exception.Message)"
        return $null
    }
}

function Get-AlertTypeFromMemberberry {
    <#
    .SYNOPSIS
        Detects alert type from ticket using Memberberry's detect-alert-type.ps1
    .DESCRIPTION
        Uses Memberberry's alert type detection to categorize security alerts.
    .PARAMETER TicketText
        Ticket text or ConnectWise ticket object
    .EXAMPLE
        $alertTypes = Get-AlertTypeFromMemberberry -TicketText $ticketContent
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$TicketText
    )
    
    $config = Get-MemberberryConfig
    
    # Extract text if ticket object
    $text = if ($TicketText -is [string]) {
        $TicketText
    }
    else {
        $textParts = @()
        if ($TicketText.summary) { $textParts += $TicketText.summary }
        if ($TicketText.initialDescription) { $textParts += $TicketText.initialDescription }
        $textParts -join "`n"
    }
    
    if (-not (Test-Path $config.DetectAlertTypeScript)) {
        Write-Warning "Memberberry detect-alert-type.ps1 not found"
        return @()
    }
    
    try {
        $alertTypes = & $config.DetectAlertTypeScript -TicketText $text
        if ($alertTypes) {
            return $alertTypes -split ","
        }
        return @()
    }
    catch {
        Write-Warning "Failed to detect alert type from Memberberry: $($_.Exception.Message)"
        return @()
    }
}

function Get-MemberberryIOCs {
    <#
    .SYNOPSIS
        Extracts IOCs from Memberberry procedures or notes
    .DESCRIPTION
        Searches Memberberry procedures and client notes for IOCs.
        Currently returns empty array as Memberberry doesn't store IOCs directly.
    .PARAMETER CaseId
        Optional case ID to filter
    .PARAMETER Tag
        Optional tag to filter
    .PARAMETER Since
        Only return entries since this date
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$CaseId,
        
        [Parameter(Mandatory=$false)]
        [string]$Tag,
        
        [Parameter(Mandatory=$false)]
        [datetime]$Since,
        
        [Parameter(Mandatory=$false)]
        [string[]]$IOCTypes
    )
    
    # Memberberry doesn't store IOCs directly in exceptions.json
    # This function is a placeholder for future integration
    # Could search procedures/ folder for IOC mentions
    
    Write-Verbose "Memberberry IOC extraction not yet implemented"
    return @()
}

function Save-HuntResultsToMemberberry {
    <#
    .SYNOPSIS
        Saves hunt results to Memberberry format
    .DESCRIPTION
        Formats hunt results for Memberberry case tracking.
        Can append to client notes or create new entries.
    .PARAMETER HuntResults
        Array of hunt result objects
    .PARAMETER ClientName
        Client name
    .PARAMETER TicketId
        Optional ConnectWise ticket ID
    .PARAMETER Notes
        Additional notes to include
    .EXAMPLE
        Save-HuntResultsToMemberberry -HuntResults $results -ClientName "Acme Corp" -TicketId "123456"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$HuntResults,
        
        [Parameter(Mandatory=$true)]
        [string]$ClientName,
        
        [Parameter(Mandatory=$false)]
        [string]$TicketId,
        
        [Parameter(Mandatory=$false)]
        [string]$Notes
    )
    
    $config = Get-MemberberryConfig
    
    # Build notes text
    $noteText = "=== Threat Hunt Results ===`n"
    $noteText += "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n"
    
    if ($TicketId) {
        $noteText += "Ticket: $TicketId`n"
    }
    
    $noteText += "`nIOCs Searched: $($HuntResults.Count)`n"
    $hits = $HuntResults | Where-Object { $_.HitCount -gt 0 }
    $noteText += "Hits Found: $($hits.Count)`n`n"
    
    if ($hits) {
        $noteText += "Results:`n"
        foreach ($result in $hits) {
            $noteText += "  - $($result.IOC) [$($result.IOCType)]: $($result.HitCount) hits`n"
            if ($result.Endpoints) {
                $noteText += "    Endpoints: $($result.Endpoints)`n"
            }
        }
    }
    
    if ($Notes) {
        $noteText += "`nNotes: $Notes`n"
    }
    
    Write-Verbose "Hunt results formatted for Memberberry:"
    Write-Verbose $noteText
    
    # In future, could append to client notes in exceptions.json
    # or create a separate hunt results file
    
    return $noteText
}

function Get-MemberberryFalsePositivePatterns {
    <#
    .SYNOPSIS
        Gets false positive patterns from Memberberry
    .DESCRIPTION
        Retrieves authorized tools, known false positive patterns, and common IP ranges
        from Memberberry exceptions.json for a client or globally.
    .PARAMETER ClientName
        Optional client name. If not specified, returns global patterns.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$ClientName
    )
    
    $config = Get-MemberberryConfig
    $exceptionsFile = $config.ExceptionsFile
    
    if (-not (Test-Path $exceptionsFile)) {
        return @{
            AuthorizedTools = @()
            FalsePositivePatterns = @()
            CommonIPRanges = @()
        }
    }
    
    try {
        if (-not $script:ExceptionsData) {
            $script:ExceptionsData = Get-Content $exceptionsFile -Raw | ConvertFrom-Json
        }
        
        $patterns = @{
            AuthorizedTools = @()
            FalsePositivePatterns = @()
            CommonIPRanges = @()
        }
        
        if ($ClientName -and $script:ExceptionsData.PSObject.Properties.Name -contains $ClientName) {
            $clientData = $script:ExceptionsData.$ClientName
            
            if ($clientData.authorized_tools) {
                $patterns.AuthorizedTools = $clientData.authorized_tools
            }
            
            if ($clientData.known_false_positive_patterns) {
                $patterns.FalsePositivePatterns = $clientData.known_false_positive_patterns
            }
            
            if ($clientData.common_ip_ranges) {
                $patterns.CommonIPRanges = $clientData.common_ip_ranges
            }
        }
        
        # Also get global patterns
        if ($script:ExceptionsData.PSObject.Properties.Name -contains "_global" -or 
            $script:ExceptionsData.PSObject.Properties.Name -contains "global") {
            $globalKey = if ($script:ExceptionsData.PSObject.Properties.Name -contains "_global") { "_global" } else { "global" }
            $globalData = $script:ExceptionsData.$globalKey
            
            if ($globalData.authorized_tools) {
                $patterns.AuthorizedTools += $globalData.authorized_tools
            }
            
            if ($globalData.known_false_positive_patterns) {
                $patterns.FalsePositivePatterns += $globalData.known_false_positive_patterns
            }
        }
        
        return $patterns
    }
    catch {
        Write-Warning "Failed to load Memberberry false positive patterns: $($_.Exception.Message)"
        return @{
            AuthorizedTools = @()
            FalsePositivePatterns = @()
            CommonIPRanges = @()
        }
    }
}

Export-ModuleMember -Function Get-MemberberryConfig, Get-MemberberryClient, Get-ClientFromMemberberry, Get-AlertTypeFromMemberberry, Get-MemberberryIOCs, Save-HuntResultsToMemberberry, Get-MemberberryFalsePositivePatterns

