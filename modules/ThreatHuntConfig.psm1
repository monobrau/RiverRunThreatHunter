<#
.SYNOPSIS
    Threat Hunt Configuration Management Module
.DESCRIPTION
    Manages client-to-platform configuration mapping and provides functions
    to retrieve client configurations for threat hunting operations.
.NOTES
    Author: River Run Security Team
    Version: 1.0
#>

$script:ConfigPath = Join-Path $PSScriptRoot "..\config\ClientConfig.json"
$script:Config = $null

function Initialize-ThreatHuntConfig {
    <#
    .SYNOPSIS
        Loads the client configuration from JSON file
    .DESCRIPTION
        Loads and validates the ClientConfig.json file. Must be called before
        using other configuration functions.
    .PARAMETER ConfigPath
        Optional path to configuration file. Defaults to config\ClientConfig.json
    .EXAMPLE
        Initialize-ThreatHuntConfig
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$ConfigPath
    )
    
    # If no path provided, search multiple locations
    if (-not $ConfigPath) {
        $possiblePaths = @(
            (Join-Path $PSScriptRoot "..\config\ClientConfig.json"),  # Relative to module
            (Join-Path (Split-Path $PSScriptRoot -Parent) "config\ClientConfig.json"),  # Parent of modules
            (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "config\ClientConfig.json"),  # 2 levels up
            (Join-Path (Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent) "config\ClientConfig.json"),  # 3 levels up (project root)
            "config\ClientConfig.json",  # Current directory
            (Join-Path (Get-Location) "config\ClientConfig.json"),  # Working directory
            (Join-Path $env:USERPROFILE "RiverRunThreatHunter\config\ClientConfig.json"),  # User profile
            "C:\git\RiverRunThreatHunter\config\ClientConfig.json"  # Common project location
        )
        
        $ConfigPath = $null
        foreach ($path in $possiblePaths) {
            $fullPath = [System.IO.Path]::GetFullPath($path)
            if (Test-Path $fullPath) {
                $ConfigPath = $fullPath
                Write-Verbose "Found config file at: $ConfigPath"
                break
            }
        }
        
        if (-not $ConfigPath) {
            throw "Configuration file not found. Searched: $($possiblePaths -join ', '). Please create ClientConfig.json first."
        }
    }
    
    if (-not (Test-Path $ConfigPath)) {
        throw "Configuration file not found: $ConfigPath. Please create ClientConfig.json first."
    }
    
    try {
        $script:Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json -AsHashtable
        # Write to stderr so it doesn't interfere with JSON output
        [Console]::Error.WriteLine("Loaded configuration for $($script:Config.Clients.Count) clients")
    }
    catch {
        throw "Failed to load configuration file: $($_.Exception.Message)"
    }
}

function Get-ClientConfig {
    <#
    .SYNOPSIS
        Gets configuration for a specific client
    .DESCRIPTION
        Retrieves client configuration including platform mappings, site IDs,
        and Perch team information.
    .PARAMETER ClientName
        Name of the client as defined in ClientConfig.json
    .EXAMPLE
        Get-ClientConfig -ClientName "AcmeCorp"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ClientName
    )
    
    if (-not $script:Config) { 
        Initialize-ThreatHuntConfig 
    }
    
    if (-not $script:Config.Clients.ContainsKey($ClientName)) {
        throw "Client '$ClientName' not found in configuration"
    }
    
    $client = $script:Config.Clients[$ClientName]
    $platform = $script:Config.Platforms[$client.S1Platform]
    
    return [PSCustomObject]@{
        ClientName      = $ClientName
        CWCompanyId     = $client.CWCompanyId
        S1Platform      = $client.S1Platform
        S1SiteId        = $client.S1SiteId
        S1SiteName      = $client.S1SiteName
        S1BaseUri       = $platform.BaseUri
        S1AccessLevel   = $platform.AccessLevel
        CanTakeAction   = $platform.AccessLevel -eq "ReadWrite"
        HasPerch        = $client.HasPerch -eq $true
        PerchTeamId     = $client.PerchTeamId
        Tier            = $client.Tier
        PrimarySocContact = $client.PrimarySocContact
    }
}

function Get-AllClients {
    <#
    .SYNOPSIS
        Lists all clients with optional filtering
    .DESCRIPTION
        Returns all configured clients, optionally filtered by platform,
        Perch availability, or actionability.
    .PARAMETER Platform
        Filter by S1 platform (BarracudaXDR or ConnectWiseS1)
    .PARAMETER WithPerch
        Only return clients with Perch SIEM enabled
    .PARAMETER Actionable
        Only return clients where response actions can be taken
    .EXAMPLE
        Get-AllClients -Platform "ConnectWiseS1" -Actionable
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [ValidateSet("ConnectWiseS1")]
        [string]$Platform,
        
        [Parameter(Mandatory=$false)]
        [switch]$WithPerch,
        
        [Parameter(Mandatory=$false)]
        [switch]$Actionable
    )
    
    if (-not $script:Config) { 
        Initialize-ThreatHuntConfig 
    }
    
    $clients = $script:Config.Clients.Keys | ForEach-Object {
        Get-ClientConfig -ClientName $_
    }
    
    if ($Platform) {
        $clients = $clients | Where-Object { $_.S1Platform -eq $Platform }
    }
    
    if ($WithPerch) {
        $clients = $clients | Where-Object { $_.HasPerch }
    }
    
    if ($Actionable) {
        $clients = $clients | Where-Object { $_.CanTakeAction }
    }
    
    return $clients
}

function Get-ClientByTicket {
    <#
    .SYNOPSIS
        Gets client configuration from ConnectWise ticket
    .DESCRIPTION
        Retrieves ticket from ConnectWise Manage, extracts company ID,
        and returns matching client configuration.
    .PARAMETER TicketId
        ConnectWise ticket ID
    .EXAMPLE
        Get-ClientByTicket -TicketId 123456
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$TicketId
    )
    
    # Import ConnectWise module if available
    $cwModule = Get-Module -Name "ConnectWiseManage" -ListAvailable
    if (-not $cwModule) {
        throw "ConnectWiseManage module not found. Cannot retrieve ticket."
    }
    
    Import-Module ConnectWiseManage -ErrorAction Stop
    
    try {
        $ticket = Get-CWTicket -TicketId $TicketId
        $companyId = $ticket.company.id
        
        if (-not $script:Config) { 
            Initialize-ThreatHuntConfig 
        }
        
        $clientName = $script:Config.Clients.GetEnumerator() | 
            Where-Object { $_.Value.CWCompanyId -eq $companyId } |
            Select-Object -ExpandProperty Key -First 1
        
        if ($clientName) {
            return Get-ClientConfig -ClientName $clientName
        }
        
        throw "No client configuration found for CW Company ID: $companyId"
    }
    catch {
        throw "Failed to get client from ticket: $($_.Exception.Message)"
    }
}

function Get-PlatformConfig {
    <#
    .SYNOPSIS
        Gets platform configuration
    .DESCRIPTION
        Returns configuration for a specific platform (BarracudaXDR, ConnectWiseS1, PerchSIEM)
    .PARAMETER Platform
        Platform name
    .EXAMPLE
        Get-PlatformConfig -Platform "ConnectWiseS1"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("ConnectWiseS1", "PerchSIEM")]
        [string]$Platform
    )
    
    if (-not $script:Config) { 
        Initialize-ThreatHuntConfig 
    }
    
    if (-not $script:Config.Platforms.ContainsKey($Platform)) {
        throw "Platform '$Platform' not found in configuration"
    }
    
    return $script:Config.Platforms[$Platform]
}

Export-ModuleMember -Function Initialize-ThreatHuntConfig, Get-ClientConfig, Get-AllClients, Get-ClientByTicket, Get-PlatformConfig

