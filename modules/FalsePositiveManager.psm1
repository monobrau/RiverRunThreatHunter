<#
.SYNOPSIS
    False Positive Management Module
.DESCRIPTION
    Manages false positive detection, storage, and filtering.
    Integrates with Memberberry for client-specific patterns.
.NOTES
    Author: River Run Security Team
    Version: 1.0
#>

$script:FalsePositivesPath = Join-Path $PSScriptRoot "..\config\FalsePositives.json"
$script:FalsePositivesData = $null

function Initialize-FalsePositives {
    <#
    .SYNOPSIS
        Initializes false positive database
    #>
    [CmdletBinding()]
    param()
    
    if (-not (Test-Path $script:FalsePositivesPath)) {
        $defaultData = @{
            FalsePositives = @()
            Patterns = @()
        } | ConvertTo-Json -Depth 10
        
        $defaultData | Out-File -FilePath $script:FalsePositivesPath -Encoding UTF8
    }
    
    try {
        $script:FalsePositivesData = Get-Content $script:FalsePositivesPath -Raw | ConvertFrom-Json
    }
    catch {
        throw "Failed to load false positives database: $($_.Exception.Message)"
    }
}

function Test-FalsePositive {
    <#
    .SYNOPSIS
        Checks if IOC/endpoint combination matches known false positive patterns
    .DESCRIPTION
        Tests against stored false positives and Memberberry patterns.
    .PARAMETER IOC
        IOC value
    .PARAMETER IOCType
        IOC type (hash, ip, domain, process, cmdline)
    .PARAMETER ClientName
        Optional client name for client-specific patterns
    .PARAMETER Endpoint
        Optional endpoint hostname
    .EXAMPLE
        Test-FalsePositive -IOC "abc123..." -IOCType "hash" -ClientName "AcmeCorp"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$IOC,
        
        [Parameter(Mandatory=$true)]
        [string]$IOCType,
        
        [Parameter(Mandatory=$false)]
        [string]$ClientName,
        
        [Parameter(Mandatory=$false)]
        [string]$Endpoint
    )
    
    if (-not $script:FalsePositivesData) {
        Initialize-FalsePositives
    }
    
    # Check stored false positives
    foreach ($fp in $script:FalsePositivesData.FalsePositives) {
        if ($fp.ioc -eq $IOC -and $fp.iocType -eq $IOCType) {
            # Check client match if specified
            if (-not $ClientName -or $fp.client -eq $ClientName -or -not $fp.client) {
                # Check endpoint match if specified
                if (-not $Endpoint -or $fp.endpoint -eq $Endpoint -or -not $fp.endpoint) {
                    # Check expiration
                    if ($fp.expiresDate) {
                        $expires = [DateTime]::Parse($fp.expiresDate)
                        if ($expires -lt (Get-Date)) {
                            continue
                        }
                    }
                    return $true
                }
            }
        }
    }
    
    # Check patterns
    foreach ($pattern in $script:FalsePositivesData.Patterns) {
        if ($pattern.appliesTo -contains $IOCType) {
            # Check client match
            if ($pattern.clients.Count -eq 0 -or $pattern.clients -contains $ClientName) {
                if ($IOC -match $pattern.pattern) {
                    return $true
                }
            }
        }
    }
    
    # Check Memberberry patterns
    $memberberryModule = Get-Module -Name "MemberberryIntegration" -ListAvailable
    if ($memberberryModule -and $ClientName) {
        Import-Module MemberberryIntegration -ErrorAction SilentlyContinue
        $mbPatterns = Get-MemberberryFalsePositivePatterns -ClientName $ClientName
        
        # Check authorized tools
        foreach ($tool in $mbPatterns.AuthorizedTools) {
            if ($IOC -like "*$tool*") {
                return $true
            }
        }
        
        # Check false positive patterns
        foreach ($pattern in $mbPatterns.FalsePositivePatterns) {
            if ($IOC -match $pattern) {
                return $true
            }
        }
        
        # Check IP ranges
        if ($IOCType -eq "ip") {
            foreach ($range in $mbPatterns.CommonIPRanges) {
                if ($IOC -like "$range*") {
                    return $true
                }
            }
        }
    }
    
    return $false
}

function Add-FalsePositive {
    <#
    .SYNOPSIS
        Marks hunt result as false positive
    .DESCRIPTION
        Adds false positive record to database.
    .PARAMETER IOC
        IOC value
    .PARAMETER IOCType
        IOC type
    .PARAMETER ClientName
        Client name
    .PARAMETER Reason
        Reason for false positive
    .PARAMETER Endpoint
        Optional endpoint hostname
    .PARAMETER ExpiresDate
        Optional expiration date
    .PARAMETER Source
        Source of false positive (Manual, Memberberry, Auto-detected)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$IOC,
        
        [Parameter(Mandatory=$true)]
        [string]$IOCType,
        
        [Parameter(Mandatory=$true)]
        [string]$ClientName,
        
        [Parameter(Mandatory=$true)]
        [string]$Reason,
        
        [Parameter(Mandatory=$false)]
        [string]$Endpoint,
        
        [Parameter(Mandatory=$false)]
        [DateTime]$ExpiresDate,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("Manual", "Memberberry", "Auto-detected")]
        [string]$Source = "Manual"
    )
    
    if (-not $script:FalsePositivesData) {
        Initialize-FalsePositives
    }
    
    $fp = @{
        id = [System.Guid]::NewGuid().ToString()
        client = $ClientName
        ioc = $IOC
        iocType = $IOCType
        endpoint = $Endpoint
        reason = $Reason
        source = $Source
        createdBy = $env:USERNAME
        createdDate = (Get-Date).ToString("o")
        expiresDate = if ($ExpiresDate) { $ExpiresDate.ToString("o") } else { $null }
    }
    
    $script:FalsePositivesData.FalsePositives += $fp
    
    # Save to file
    $script:FalsePositivesData | ConvertTo-Json -Depth 10 | Out-File -FilePath $script:FalsePositivesPath -Encoding UTF8 -Force
    
    Write-Host "False positive added: $IOC [$IOCType]" -ForegroundColor Green
    return $fp
}

function Remove-FalsePositive {
    <#
    .SYNOPSIS
        Removes false positive designation
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$FalsePositiveId
    )
    
    if (-not $script:FalsePositivesData) {
        Initialize-FalsePositives
    }
    
    $fp = $script:FalsePositivesData.FalsePositives | Where-Object { $_.id -eq $FalsePositiveId }
    if ($fp) {
        $script:FalsePositivesData.FalsePositives = $script:FalsePositivesData.FalsePositives | Where-Object { $_.id -ne $FalsePositiveId }
        $script:FalsePositivesData | ConvertTo-Json -Depth 10 | Out-File -FilePath $script:FalsePositivesPath -Encoding UTF8 -Force
        Write-Host "False positive removed: $FalsePositiveId" -ForegroundColor Green
        return $true
    }
    
    return $false
}

function Filter-FalsePositives {
    <#
    .SYNOPSIS
        Removes false positives from hunt results
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$HuntResults
    )
    
    $filtered = @()
    
    foreach ($result in $HuntResults) {
        $isFP = Test-FalsePositive -IOC $result.IOC -IOCType $result.IOCType `
            -ClientName $result.Client -Endpoint $result.Endpoint
        
        if (-not $isFP) {
            $filtered += $result
        }
    }
    
    $removed = $HuntResults.Count - $filtered.Count
    if ($removed -gt 0) {
        Write-Host "Filtered $removed false positives from results" -ForegroundColor Yellow
    }
    
    return $filtered
}

function Import-MemberberryFalsePositives {
    <#
    .SYNOPSIS
        Syncs false positive patterns from Memberberry
    #>
    [CmdletBinding()]
    param()
    
    $memberberryModule = Get-Module -Name "MemberberryIntegration" -ListAvailable
    if (-not $memberberryModule) {
        Write-Warning "MemberberryIntegration module not found"
        return
    }
    
    Import-Module MemberberryIntegration -ErrorAction Stop
    
    if (-not $script:FalsePositivesData) {
        Initialize-FalsePositives
    }
    
    # Get all clients from config
    $configModule = Get-Module -Name "ThreatHuntConfig" -ListAvailable
    if ($configModule) {
        Import-Module ThreatHuntConfig -ErrorAction SilentlyContinue
        $clients = Get-AllClients -ErrorAction SilentlyContinue
        
        foreach ($client in $clients) {
            $patterns = Get-MemberberryFalsePositivePatterns -ClientName $client.ClientName
            
            # Add patterns to database
            foreach ($pattern in $patterns.FalsePositivePatterns) {
                $existing = $script:FalsePositivesData.Patterns | Where-Object { $_.pattern -eq $pattern }
                if (-not $existing) {
                    $script:FalsePositivesData.Patterns += @{
                        pattern = $pattern
                        description = "Imported from Memberberry for $($client.ClientName)"
                        appliesTo = @("hash", "process", "cmdline")
                        clients = @($client.ClientName)
                    }
                }
            }
        }
    }
    
    # Save updated patterns
    $script:FalsePositivesData | ConvertTo-Json -Depth 10 | Out-File -FilePath $script:FalsePositivesPath -Encoding UTF8 -Force
    Write-Host "Memberberry false positive patterns imported" -ForegroundColor Green
}

function Create-ExclusionFromFalsePositive {
    <#
    .SYNOPSIS
        Creates S1 exclusion from false positive
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$FalsePositive,
        
        [Parameter(Mandatory=$true)]
        [string]$ClientName,
        
        [Parameter(Mandatory=$false)]
        [switch]$SkipIfExists
    )
    
    # Import required modules
    $modules = @("ThreatHuntConfig", "ConnectionManager", "S1Exclusions")
    foreach ($module in $modules) {
        $mod = Get-Module -Name $module -ListAvailable
        if (-not $mod) {
            Import-Module (Join-Path $PSScriptRoot "$module.psm1") -ErrorAction Stop
        }
        else {
            Import-Module $module -ErrorAction Stop
        }
    }
    
    $client = Get-ClientConfig -ClientName $ClientName
    if (-not $client.CanTakeAction) {
        Write-Warning "Cannot create exclusion for $ClientName - platform is read-only"
        return $null
    }
    
    $conn = Get-PlatformConnection -Platform $client.S1Platform
    
    if ($SkipIfExists) {
        if (Test-S1ExclusionExists -Connection $conn -Value $FalsePositive.IOC -SiteId $client.S1SiteId) {
            Write-Host "Exclusion already exists, skipping" -ForegroundColor Yellow
            return $null
        }
    }
    
    return Convert-FalsePositiveToExclusion -Connection $conn `
        -FalsePositive $FalsePositive -SiteId $client.S1SiteId `
        -Description "False positive: $($FalsePositive.Reason)"
}

Export-ModuleMember -Function Initialize-FalsePositives, Test-FalsePositive, Add-FalsePositive, Remove-FalsePositive, Filter-FalsePositives, Import-MemberberryFalsePositives, Create-ExclusionFromFalsePositive

