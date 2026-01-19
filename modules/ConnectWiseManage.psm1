<#
.SYNOPSIS
    ConnectWise Manage Integration Module
.DESCRIPTION
    Provides functions for interacting with ConnectWise Manage API,
    extracting IOCs from tickets, and updating tickets with hunt results.
.NOTES
    Author: River Run Security Team
    Version: 1.0
#>

$script:CWConfig = $null

function Initialize-CWConfig {
    <#
    .SYNOPSIS
        Initializes ConnectWise Manage API configuration
    .DESCRIPTION
        Sets up API credentials and base URL for ConnectWise Manage.
        Credentials can be stored in environment variables or passed as parameters.
    .PARAMETER CompanyId
        ConnectWise Manage company ID
    .PARAMETER PublicKey
        ConnectWise Manage public API key
    .PARAMETER PrivateKey
        ConnectWise Manage private API key
    .PARAMETER BaseUrl
        ConnectWise Manage API base URL (e.g., https://api-connectwise.com)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$CompanyId = $env:CW_COMPANY_ID,
        
        [Parameter(Mandatory=$false)]
        [string]$PublicKey = $env:CW_PUBLIC_KEY,
        
        [Parameter(Mandatory=$false)]
        [string]$PrivateKey = $env:CW_PRIVATE_KEY,
        
        [Parameter(Mandatory=$false)]
        [string]$BaseUrl = $env:CW_BASE_URL
    )
    
    if (-not $CompanyId -or -not $PublicKey -or -not $PrivateKey -or -not $BaseUrl) {
        throw "ConnectWise credentials not configured. Set environment variables or pass parameters."
    }
    
    $script:CWConfig = @{
        CompanyId = $CompanyId
        PublicKey = $PublicKey
        PrivateKey = $PrivateKey
        BaseUrl = $BaseUrl
    }
}

function Get-CWHeaders {
    <#
    .SYNOPSIS
        Gets ConnectWise API headers with authentication
    #>
    [CmdletBinding()]
    param()
    
    if (-not $script:CWConfig) {
        Initialize-CWConfig
    }
    
    $authString = "$($script:CWConfig.CompanyId)+$($script:CWConfig.PublicKey):$($script:CWConfig.PrivateKey)"
    $authBytes = [System.Text.Encoding]::UTF8.GetBytes($authString)
    $authToken = [System.Convert]::ToBase64String($authBytes)
    
    return @{
        "Authorization" = "Basic $authToken"
        "Content-Type" = "application/json"
        "ClientId" = "RiverRunThreatHunter"
    }
}

function Get-CWTicket {
    <#
    .SYNOPSIS
        Retrieves a ConnectWise ticket by ID
    .DESCRIPTION
        Fetches ticket details including summary, notes, and custom fields.
    .PARAMETER TicketId
        ConnectWise ticket ID
    .EXAMPLE
        Get-CWTicket -TicketId 123456
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$TicketId
    )
    
    if (-not $script:CWConfig) {
        Initialize-CWConfig
    }
    
    $headers = Get-CWHeaders
    $uri = "$($script:CWConfig.BaseUrl)/v4_6_release/apis/3.0/service/tickets/$TicketId"
    
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -ErrorAction Stop
        return $response
    }
    catch {
        throw "Failed to retrieve ticket $TicketId : $($_.Exception.Message)"
    }
}

function Extract-IOCsFromTicket {
    <#
    .SYNOPSIS
        Extracts IOCs from ConnectWise ticket content
    .DESCRIPTION
        Parses ticket text for hashes, IPs, domains, processes, and command lines.
        Returns array of IOC objects with Type and Value properties.
    .PARAMETER Ticket
        ConnectWise ticket object or ticket text
    .EXAMPLE
        $ticket = Get-CWTicket -TicketId 123456
        $iocs = Extract-IOCsFromTicket -Ticket $ticket
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$Ticket
    )
    
    # Extract text from ticket object or use as-is if string
    $ticketText = if ($Ticket -is [string]) {
        $Ticket
    }
    else {
        $textParts = @()
        if ($Ticket.summary) { $textParts += $Ticket.summary }
        if ($Ticket.initialDescription) { $textParts += $Ticket.initialDescription }
        if ($Ticket.resolution) { $textParts += $Ticket.resolution }
        
        # Get all notes
        if ($Ticket.notes) {
            foreach ($note in $Ticket.notes) {
                if ($note.text) { $textParts += $note.text }
            }
        }
        
        $textParts -join "`n"
    }
    
    $iocs = @()
    
    # Extract SHA256 hashes (64 hex characters)
    $sha256Pattern = '\b[A-Fa-f0-9]{64}\b'
    $ticketText | Select-String -Pattern $sha256Pattern -AllMatches | ForEach-Object {
        foreach ($match in $_.Matches) {
            $iocs += @{ Type = "hash"; Value = $match.Value }
        }
    }
    
    # Extract SHA1 hashes (40 hex characters)
    $sha1Pattern = '\b[A-Fa-f0-9]{40}\b'
    $ticketText | Select-String -Pattern $sha1Pattern -AllMatches | ForEach-Object {
        foreach ($match in $_.Matches) {
            if ($match.Value.Length -eq 40) {
                $iocs += @{ Type = "hash"; Value = $match.Value }
            }
        }
    }
    
    # Extract MD5 hashes (32 hex characters)
    $md5Pattern = '\b[A-Fa-f0-9]{32}\b'
    $ticketText | Select-String -Pattern $md5Pattern -AllMatches | ForEach-Object {
        foreach ($match in $_.Matches) {
            if ($match.Value.Length -eq 32) {
                $iocs += @{ Type = "hash"; Value = $match.Value }
            }
        }
    }
    
    # Extract IPv4 addresses
    $ipv4Pattern = '\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b'
    $ticketText | Select-String -Pattern $ipv4Pattern -AllMatches | ForEach-Object {
        foreach ($match in $_.Matches) {
            $iocs += @{ Type = "ip"; Value = $match.Value }
        }
    }
    
    # Extract domains (handle defanged domains like example[.]com)
    $domainPattern = '(?:[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}'
    $ticketText | Select-String -Pattern $domainPattern -AllMatches | ForEach-Object {
        foreach ($match in $_.Matches) {
            $domain = $match.Value -replace '\[\.\]', '.' -replace '\(\.\)', '.'
            # Filter out common false positives
            if ($domain -notmatch '\.(com|net|org|edu|gov|microsoft|google|amazon|cloud)$' -or 
                $domain -match '\.(tk|ml|ga|cf|gq|xyz|top|click|download|stream|online)$') {
                $iocs += @{ Type = "domain"; Value = $domain }
            }
        }
    }
    
    # Extract process names (common executable names)
    $processPattern = '\b([a-zA-Z0-9_-]+\.(exe|dll|bat|cmd|ps1|vbs|js|scr|com))\b'
    $ticketText | Select-String -Pattern $processPattern -AllMatches | ForEach-Object {
        foreach ($match in $_.Matches) {
            $iocs += @{ Type = "process"; Value = $match.Groups[1].Value }
        }
    }
    
    # Extract command line patterns (powershell -enc, cmd /c, etc.)
    $cmdlinePatterns = @(
        'powershell\s+-enc\s+[A-Za-z0-9+/=]+',
        'cmd\s+/c\s+[^\s]+',
        'wmic\s+[^\s]+',
        'schtasks\s+[^\s]+'
    )
    
    foreach ($pattern in $cmdlinePatterns) {
        $ticketText | Select-String -Pattern $pattern -AllMatches | ForEach-Object {
            foreach ($match in $_.Matches) {
                $iocs += @{ Type = "cmdline"; Value = $match.Value }
            }
        }
    }
    
    # Remove duplicates
    $uniqueIOCs = $iocs | Sort-Object -Property Type, Value -Unique
    
    return $uniqueIOCs
}

function Update-CWTicketWithResults {
    <#
    .SYNOPSIS
        Updates ConnectWise ticket with hunt results
    .DESCRIPTION
        Adds an internal note to the ticket with hunt results summary.
    .PARAMETER TicketId
        ConnectWise ticket ID
    .PARAMETER HuntResults
        Array of hunt result objects
    .PARAMETER Summary
        Summary text to include in note
    .EXAMPLE
        Update-CWTicketWithResults -TicketId 123456 -HuntResults $results -Summary "Threat hunt completed"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$TicketId,
        
        [Parameter(Mandatory=$false)]
        [array]$HuntResults,
        
        [Parameter(Mandatory=$false)]
        [string]$Summary
    )
    
    if (-not $script:CWConfig) {
        Initialize-CWConfig
    }
    
    $headers = Get-CWHeaders
    
    # Build note text
    $noteText = "=== Threat Hunt Results ===`n`n"
    
    if ($Summary) {
        $noteText += "$Summary`n`n"
    }
    
    if ($HuntResults) {
        $noteText += "IOCs Searched: $($HuntResults.Count)`n"
        $noteText += "Hits Found: $(($HuntResults | Where-Object { $_.HitCount -gt 0 }).Count)`n`n"
        
        $noteText += "Results by IOC:`n"
        $HuntResults | Group-Object IOC | ForEach-Object {
            $noteText += "  - $($_.Name): $($_.Group.HitCount) hits`n"
        }
    }
    
    $noteText += "`nGenerated by RiverRunThreatHunter"
    
    $body = @{
        text = $noteText
        internalFlag = $true
        member = @{
            identifier = $env:USERNAME
        }
    } | ConvertTo-Json -Depth 10
    
    $uri = "$($script:CWConfig.BaseUrl)/v4_6_release/apis/3.0/service/tickets/$TicketId/notes"
    
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -ErrorAction Stop
        Write-Host "Ticket $TicketId updated successfully" -ForegroundColor Green
        return $response
    }
    catch {
        throw "Failed to update ticket $TicketId : $($_.Exception.Message)"
    }
}

function Get-ClientByTicket {
    <#
    .SYNOPSIS
        Gets client configuration from ConnectWise ticket
    .DESCRIPTION
        Retrieves ticket, extracts company ID, and returns matching client config.
    .PARAMETER TicketId
        ConnectWise ticket ID
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$TicketId
    )
    
    $ticket = Get-CWTicket -TicketId $TicketId
    $companyId = $ticket.company.id
    
    # Import config module
    $configModule = Get-Module -Name "ThreatHuntConfig" -ListAvailable
    if (-not $configModule) {
        Import-Module (Join-Path $PSScriptRoot "ThreatHuntConfig.psm1") -ErrorAction Stop
    }
    else {
        Import-Module ThreatHuntConfig -ErrorAction Stop
    }
    
    return Get-ClientByTicket -TicketId $TicketId
}

Export-ModuleMember -Function Initialize-CWConfig, Get-CWTicket, Extract-IOCsFromTicket, Update-CWTicketWithResults, Get-ClientByTicket

