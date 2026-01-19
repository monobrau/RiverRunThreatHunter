<#
.SYNOPSIS
    Unified Threat Hunt Engine Module
.DESCRIPTION
    Orchestrates threat hunts across multiple platforms (SentinelOne, Perch SIEM)
    for single or multiple clients, with correlation and result aggregation.
.NOTES
    Author: River Run Security Team
    Version: 1.0
#>

function Invoke-ClientThreatHunt {
    <#
    .SYNOPSIS
        Hunts IOCs for a single client across all platforms
    .DESCRIPTION
        Executes threat hunt for specified client across SentinelOne and Perch SIEM.
        Returns unified results with source attribution.
    .PARAMETER IOCs
        Array of IOC objects with Type and Value properties
    .PARAMETER ClientName
        Client name as configured in ClientConfig.json
    .PARAMETER DaysBack
        Number of days to look back (default: 14)
    .EXAMPLE
        $iocs = @(@{ Type = "hash"; Value = "abc123..." })
        Invoke-ClientThreatHunt -IOCs $iocs -ClientName "AcmeCorp"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$IOCs,
        
        [Parameter(Mandatory=$true)]
        [string]$ClientName,
        
        [Parameter(Mandatory=$false)]
        [int]$DaysBack = 14
    )
    
    # Import required modules
    $modules = @("ThreatHuntConfig", "ConnectionManager", "SentinelOneHunter", "PerchHunter")
    foreach ($module in $modules) {
        $mod = Get-Module -Name $module -ListAvailable
        if (-not $mod) {
            Import-Module (Join-Path $PSScriptRoot "$module.psm1") -ErrorAction Stop
        }
        else {
            Import-Module $module -ErrorAction Stop
        }
    }
    
    # Get client configuration
    $client = Get-ClientConfig -ClientName $ClientName
    Write-Host "`n=== Hunting in $ClientName ===" -ForegroundColor Cyan
    Write-Host "Platform: $($client.S1Platform) | Site: $($client.S1SiteName) | Actions: $($client.CanTakeAction)" -ForegroundColor Gray
    
    $results = [System.Collections.ArrayList]@()
    
    # --- SentinelOne Deep Visibility ---
    try {
        $s1Conn = Get-PlatformConnection -Platform $client.S1Platform
        
        foreach ($ioc in $IOCs) {
            Write-Host "  Searching S1 for: $($ioc.Value) [$($ioc.Type)]" -ForegroundColor Yellow
            
            $hits = switch ($ioc.Type.ToLower()) {
                "hash"    { Hunt-S1FileHash -Connection $s1Conn -Hash $ioc.Value -SiteId $client.S1SiteId -DaysBack $DaysBack }
                "ip"      { Hunt-S1IPAddress -Connection $s1Conn -IP $ioc.Value -SiteId $client.S1SiteId -DaysBack $DaysBack }
                "domain"  { Hunt-S1Domain -Connection $s1Conn -Domain $ioc.Value -SiteId $client.S1SiteId -DaysBack $DaysBack }
                "process" { Hunt-S1Process -Connection $s1Conn -ProcessName $ioc.Value -SiteId $client.S1SiteId -DaysBack $DaysBack }
                "cmdline" { Hunt-S1CommandLine -Connection $s1Conn -CmdPattern $ioc.Value -SiteId $client.S1SiteId -DaysBack $DaysBack }
                default   { Write-Warning "Unsupported IOC type: $($ioc.Type)"; @() }
            }
            
            foreach ($hit in $hits) {
                [void]$results.Add([PSCustomObject]@{
                    Client         = $ClientName
                    Source         = $client.S1Platform
                    SourceType     = "Endpoint"
                    IOC            = $ioc.Value
                    IOCType        = $ioc.Type
                    Timestamp      = $hit.createdAt
                    Endpoint       = $hit.agentName
                    EndpointId     = $hit.agentId
                    User           = $hit.user
                    ProcessName    = $hit.processName
                    CommandLine    = $hit.processCmd
                    FilePath       = $hit.filePath
                    EventType      = $hit.eventType
                    CanTakeAction  = $client.CanTakeAction
                    Platform       = $client.S1Platform
                    RawEvent       = $hit
                })
            }
        }
    }
    catch {
        Write-Warning "Failed to query SentinelOne: $($_.Exception.Message)"
    }
    
    # --- Perch SIEM (if available) ---
    if ($client.HasPerch) {
        try {
            $perchConn = Get-PlatformConnection -Platform "PerchSIEM"
            
            foreach ($ioc in $IOCs) {
                Write-Host "  Searching Perch for: $($ioc.Value) [$($ioc.Type)]" -ForegroundColor Yellow
                
                $perchHits = switch ($ioc.Type.ToLower()) {
                    "hash"    { Hunt-PerchHash -Connection $perchConn -Hash $ioc.Value -TeamId $client.PerchTeamId -DaysBack $DaysBack }
                    "ip"      { Hunt-PerchIP -Connection $perchConn -IP $ioc.Value -TeamId $client.PerchTeamId -DaysBack $DaysBack }
                    "domain"  { Hunt-PerchDomain -Connection $perchConn -Domain $ioc.Value -TeamId $client.PerchTeamId -DaysBack $DaysBack }
                    default   { Write-Verbose "Perch doesn't support IOC type: $($ioc.Type)"; @() }
                }
                
                foreach ($hit in $perchHits) {
                    [void]$results.Add([PSCustomObject]@{
                        Client         = $ClientName
                        Source         = "PerchSIEM"
                        SourceType     = "Network"
                        IOC            = $ioc.Value
                        IOCType        = $ioc.Type
                        Timestamp      = $hit.timestamp
                        Endpoint       = $hit.src_host ?? $hit.hostname ?? $hit.client_ip
                        EndpointId     = $null
                        User           = $hit.user ?? $hit.username
                        ProcessName    = $null
                        CommandLine    = $null
                        FilePath       = $null
                        EventType      = $hit.event_type
                        CanTakeAction  = $false
                        Platform       = "Perch"
                        LogSource      = $hit.log_source
                        RawMessage     = $hit.message
                        RawEvent       = $hit
                    })
                }
            }
        }
        catch {
            Write-Warning "Failed to query Perch SIEM: $($_.Exception.Message)"
        }
    }
    
    Write-Host "  Found $($results.Count) total hits" -ForegroundColor $(if ($results.Count -gt 0) { "Red" } else { "Green" })
    return $results
}

function Invoke-MultiClientThreatHunt {
    <#
    .SYNOPSIS
        Hunts IOCs across multiple or all clients
    .DESCRIPTION
        Executes threat hunt across specified clients or all clients.
        Supports filtering by platform and actionability.
    .PARAMETER IOCs
        Array of IOC objects
    .PARAMETER ClientNames
        Optional array of specific client names. If not specified, hunts all clients.
    .PARAMETER Platform
        Filter by S1 platform (BarracudaXDR or ConnectWiseS1)
    .PARAMETER ActionableOnly
        Only hunt clients where response actions can be taken
    .PARAMETER DaysBack
        Number of days to look back (default: 14)
    .EXAMPLE
        $iocs = @(@{ Type = "domain"; Value = "malicious.com" })
        Invoke-MultiClientThreatHunt -IOCs $iocs -Platform "ConnectWiseS1"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$IOCs,
        
        [Parameter(Mandatory=$false)]
        [string[]]$ClientNames,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("BarracudaXDR", "ConnectWiseS1")]
        [string]$Platform,
        
        [Parameter(Mandatory=$false)]
        [switch]$ActionableOnly,
        
        [Parameter(Mandatory=$false)]
        [int]$DaysBack = 14
    )
    
    # Import config module
    $configModule = Get-Module -Name "ThreatHuntConfig" -ListAvailable
    if (-not $configModule) {
        Import-Module (Join-Path $PSScriptRoot "ThreatHuntConfig.psm1") -ErrorAction Stop
    }
    else {
        Import-Module ThreatHuntConfig -ErrorAction Stop
    }
    
    # Determine which clients to hunt
    if ($ClientNames) {
        $clients = $ClientNames | ForEach-Object { Get-ClientConfig -ClientName $_ }
    }
    else {
        $clients = Get-AllClients -Platform $Platform -Actionable:$ActionableOnly
    }
    
    Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║           MSP-WIDE THREAT HUNT                               ║" -ForegroundColor Cyan
    Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "║  IOCs to search: $($IOCs.Count.ToString().PadRight(43))║" -ForegroundColor Cyan
    Write-Host "║  Clients to scan: $($clients.Count.ToString().PadRight(42))║" -ForegroundColor Cyan
    Write-Host "║  Lookback period: $($DaysBack.ToString().PadRight(42))days ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    $allResults = [System.Collections.ArrayList]@()
    
    foreach ($client in $clients) {
        $clientResults = Invoke-ClientThreatHunt -IOCs $IOCs -ClientName $client.ClientName -DaysBack $DaysBack
        
        foreach ($result in $clientResults) {
            [void]$allResults.Add($result)
        }
    }
    
    return $allResults
}

function Get-CorrelatedTimeline {
    <#
    .SYNOPSIS
        Correlates endpoint and network events
    .DESCRIPTION
        Groups events by IOC and identifies correlations between endpoint
        (SentinelOne) and network (Perch) sources.
    .PARAMETER HuntResults
        Array of hunt result objects
    .PARAMETER WindowMinutes
        Time window for correlation (default: 30)
    .EXAMPLE
        $correlations = Get-CorrelatedTimeline -HuntResults $results
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$HuntResults,
        
        [Parameter(Mandatory=$false)]
        [int]$WindowMinutes = 30
    )
    
    # Group by IOC
    $iocGroups = $HuntResults | Group-Object IOC
    
    $correlations = @()
    
    foreach ($group in $iocGroups) {
        $endpointHits = $group.Group | Where-Object { $_.SourceType -eq "Endpoint" }
        $networkHits = $group.Group | Where-Object { $_.SourceType -eq "Network" }
        
        if ($endpointHits -and $networkHits) {
            $correlations += [PSCustomObject]@{
                IOC              = $group.Name
                IOCType          = ($group.Group | Select-Object -First 1).IOCType
                EndpointHits     = $endpointHits.Count
                NetworkHits      = $networkHits.Count
                AffectedAssets   = ($group.Group.Endpoint | Where-Object { $_ } | Select-Object -Unique) -join ", "
                FirstSeen        = ($group.Group.Timestamp | Sort-Object | Select-Object -First 1)
                LastSeen         = ($group.Group.Timestamp | Sort-Object | Select-Object -Last 1)
                ActionRecommended = ($group.Group | Where-Object { $_.CanTakeAction }).Count -gt 0
            }
        }
    }
    
    return $correlations
}

function Get-HuntSummary {
    <#
    .SYNOPSIS
        Generates summary statistics for hunt results
    .DESCRIPTION
        Provides overview of hunt results including hits by client, IOC, and platform.
    .PARAMETER Results
        Array of hunt result objects
    .EXAMPLE
        $summary = Get-HuntSummary -Results $huntResults
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$Results
    )
    
    Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║                    HUNT SUMMARY                              ║" -ForegroundColor Yellow
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    
    # By Client
    Write-Host "`n[Hits by Client]" -ForegroundColor Cyan
    $Results | Group-Object Client | Sort-Object Count -Descending | ForEach-Object {
        $client = Get-ClientConfig -ClientName $_.Name -ErrorAction SilentlyContinue
        $actionIcon = if ($client -and $client.CanTakeAction) { "⚡" } else { "👁" }
        Write-Host "  $actionIcon $($_.Name): $($_.Count) hits ($($client.S1Platform))"
    }
    
    # By IOC
    Write-Host "`n[Hits by IOC]" -ForegroundColor Cyan
    $Results | Group-Object IOC | Sort-Object Count -Descending | ForEach-Object {
        $clients = ($_.Group.Client | Select-Object -Unique) -join ", "
        Write-Host "  $($_.Name): $($_.Count) hits across $($_.Group.Client | Select-Object -Unique | Measure-Object | Select-Object -Expand Count) clients"
    }
    
    # Actionable vs Non-Actionable
    $actionable = $Results | Where-Object { $_.CanTakeAction }
    $readOnly = $Results | Where-Object { -not $_.CanTakeAction }
    
    Write-Host "`n[Response Capability]" -ForegroundColor Cyan
    Write-Host "  ⚡ Actionable (ConnectWise S1): $($actionable.Count) hits"
    Write-Host "  👁 Read-Only (Barracuda XDR):   $($readOnly.Count) hits"
    
    # Endpoint + Network correlation
    $correlatedIOCs = $Results | Group-Object IOC | Where-Object {
        $types = $_.Group.SourceType | Select-Object -Unique
        ($types -contains "Endpoint") -and ($types -contains "Network")
    }
    
    if ($correlatedIOCs) {
        Write-Host "`n[Correlated IOCs - Seen on Endpoint AND Network]" -ForegroundColor Magenta
        foreach ($ioc in $correlatedIOCs) {
            Write-Host "  🔗 $($ioc.Name)"
            Write-Host "     Endpoint hits: $(($ioc.Group | Where-Object SourceType -eq 'Endpoint').Count)"
            Write-Host "     Network hits:  $(($ioc.Group | Where-Object SourceType -eq 'Network').Count)"
        }
    }
    
    # Return structured summary
    return [PSCustomObject]@{
        TotalHits          = $Results.Count
        ClientsAffected    = ($Results.Client | Select-Object -Unique).Count
        ActionableHits     = $actionable.Count
        ReadOnlyHits       = $readOnly.Count
        CorrelatedIOCs     = $correlatedIOCs.Count
        UniqueEndpoints    = ($Results | Where-Object { $_.Endpoint } | Select-Object -ExpandProperty Endpoint -Unique).Count
    }
}

Export-ModuleMember -Function Invoke-ClientThreatHunt, Invoke-MultiClientThreatHunt, Get-CorrelatedTimeline, Get-HuntSummary

