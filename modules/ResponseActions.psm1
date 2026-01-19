<#
.SYNOPSIS
    SentinelOne Response Actions Module
.DESCRIPTION
    Provides functions for executing response actions on SentinelOne endpoints.
    Only works on ConnectWise S1 (read/write), blocks actions on Barracuda XDR (read-only).
.NOTES
    Author: River Run Security Team
    Version: 1.0
#>

function Invoke-S1Action {
    <#
    .SYNOPSIS
        Executes a SentinelOne response action with access level checking
    .DESCRIPTION
        Validates platform access level before executing action. Blocks write operations
        on read-only platforms (Barracuda XDR).
    .PARAMETER Platform
        Platform name (BarracudaXDR or ConnectWiseS1)
    .PARAMETER Action
        Action type (isolate, unisolate, kill-process, quarantine, scan, etc.)
    .PARAMETER Parameters
        Hashtable of action-specific parameters
    .EXAMPLE
        Invoke-S1Action -Platform "ConnectWiseS1" -Action "isolate" -Parameters @{ agentId = "123456" }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("BarracudaXDR", "ConnectWiseS1")]
        [string]$Platform,
        
        [Parameter(Mandatory=$true)]
        [string]$Action,
        
        [Parameter(Mandatory=$true)]
        [hashtable]$Parameters
    )
    
    # Import required modules
    $configModule = Get-Module -Name "ThreatHuntConfig" -ListAvailable
    if (-not $configModule) {
        Import-Module (Join-Path $PSScriptRoot "ThreatHuntConfig.psm1") -ErrorAction Stop
    }
    else {
        Import-Module ThreatHuntConfig -ErrorAction Stop
    }
    
    $platformConfig = Get-PlatformConfig -Platform $Platform
    $accessLevel = $platformConfig.AccessLevel
    
    $writeActions = @(
        "isolate", "unisolate", "kill-process", "quarantine", 
        "remediate", "rollback", "scan", "remote-script", "fetch-file"
    )
    
    if ($Action -in $writeActions -and $accessLevel -eq "ReadOnly") {
        Write-Warning "BLOCKED: '$Action' not permitted on $Platform (Read-Only)"
        return @{
            Success = $false
            Reason  = "Instance is read-only"
            Action  = $Action
            Platform = $Platform
        }
    }
    
    # Get connection
    $connModule = Get-Module -Name "ConnectionManager" -ListAvailable
    if (-not $connModule) {
        Import-Module (Join-Path $PSScriptRoot "ConnectionManager.psm1") -ErrorAction Stop
    }
    else {
        Import-Module ConnectionManager -ErrorAction Stop
    }
    
    $connection = Get-PlatformConnection -Platform $Platform
    
    # Execute action based on type
    try {
        $result = switch ($Action.ToLower()) {
            "isolate"      { Invoke-S1IsolateInternal -Connection $connection -Parameters $Parameters }
            "unisolate"    { Invoke-S1UnisolateInternal -Connection $connection -Parameters $Parameters }
            "kill-process" { Invoke-S1KillProcessInternal -Connection $connection -Parameters $Parameters }
            "quarantine"   { Invoke-S1QuarantineFileInternal -Connection $connection -Parameters $Parameters }
            "scan"         { Invoke-S1InitiateScanInternal -Connection $connection -Parameters $Parameters }
            default        { throw "Unknown action: $Action" }
        }
        
        return @{
            Success = $true
            Action  = $Action
            Result  = $result
        }
    }
    catch {
        return @{
            Success = $false
            Action  = $Action
            Error   = $_.Exception.Message
        }
    }
}

function Invoke-S1Isolate {
    <#
    .SYNOPSIS
        Network isolates a SentinelOne endpoint
    .DESCRIPTION
        Isolates endpoint from network, preventing all network communication.
    .PARAMETER Platform
        Platform name (must be ConnectWiseS1)
    .PARAMETER AgentId
        SentinelOne agent ID
    .EXAMPLE
        Invoke-S1Isolate -Platform "ConnectWiseS1" -AgentId "1234567890"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("BarracudaXDR", "ConnectWiseS1")]
        [string]$Platform,
        
        [Parameter(Mandatory=$true)]
        [string]$AgentId
    )
    
    return Invoke-S1Action -Platform $Platform -Action "isolate" -Parameters @{ agentId = $AgentId }
}

function Invoke-S1Unisolate {
    <#
    .SYNOPSIS
        Removes network isolation from endpoint
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("BarracudaXDR", "ConnectWiseS1")]
        [string]$Platform,
        
        [Parameter(Mandatory=$true)]
        [string]$AgentId
    )
    
    return Invoke-S1Action -Platform $Platform -Action "unisolate" -Parameters @{ agentId = $AgentId }
}

function Invoke-S1KillProcess {
    <#
    .SYNOPSIS
        Kills a process on an endpoint
    .PARAMETER Platform
        Platform name (must be ConnectWiseS1)
    .PARAMETER AgentId
        SentinelOne agent ID
    .PARAMETER ProcessId
        Process ID (PID) to kill
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("BarracudaXDR", "ConnectWiseS1")]
        [string]$Platform,
        
        [Parameter(Mandatory=$true)]
        [string]$AgentId,
        
        [Parameter(Mandatory=$true)]
        [string]$ProcessId
    )
    
    return Invoke-S1Action -Platform $Platform -Action "kill-process" -Parameters @{
        agentId = $AgentId
        processId = $ProcessId
    }
}

function Invoke-S1QuarantineFile {
    <#
    .SYNOPSIS
        Quarantines a file on an endpoint
    .PARAMETER Platform
        Platform name (must be ConnectWiseS1)
    .PARAMETER AgentId
        SentinelOne agent ID
    .PARAMETER FilePath
        Path to file to quarantine
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("BarracudaXDR", "ConnectWiseS1")]
        [string]$Platform,
        
        [Parameter(Mandatory=$true)]
        [string]$AgentId,
        
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )
    
    return Invoke-S1Action -Platform $Platform -Action "quarantine" -Parameters @{
        agentId = $AgentId
        filePath = $FilePath
    }
}

function Invoke-S1InitiateScan {
    <#
    .SYNOPSIS
        Initiates a full disk scan on an endpoint
    .PARAMETER Platform
        Platform name (must be ConnectWiseS1)
    .PARAMETER AgentId
        SentinelOne agent ID
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("BarracudaXDR", "ConnectWiseS1")]
        [string]$Platform,
        
        [Parameter(Mandatory=$true)]
        [string]$AgentId
    )
    
    return Invoke-S1Action -Platform $Platform -Action "scan" -Parameters @{ agentId = $AgentId }
}

function Invoke-BulkResponse {
    <#
    .SYNOPSIS
        Executes response actions on multiple endpoints
    .DESCRIPTION
        Takes action on multiple endpoints with confirmation prompt.
        Filters to only actionable targets (ConnectWise S1 only).
    .PARAMETER Targets
        Array of hunt result objects with EndpointId and Platform properties
    .PARAMETER Action
        Action to take (isolate, quarantine, scan, etc.)
    .PARAMETER Force
        Skip confirmation prompt
    .EXAMPLE
        $actionable = $results | Where-Object { $_.CanTakeAction }
        Invoke-BulkResponse -Targets $actionable -Action "isolate"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$Targets,
        
        [Parameter(Mandatory=$true)]
        [string]$Action,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    # Filter to only actionable targets
    $actionableTargets = $Targets | Where-Object { $_.CanTakeAction }
    
    if ($actionableTargets.Count -eq 0) {
        Write-Warning "No actionable targets found. All targets are on read-only platforms."
        return
    }
    
    if (-not $Force) {
        Write-Host "`nThe following actions will be taken:" -ForegroundColor Yellow
        $actionableTargets | Format-Table Endpoint, Client, IOC -AutoSize
        
        $confirm = Read-Host "Proceed with $Action on $($actionableTargets.Count) endpoints? (yes/no)"
        if ($confirm -ne "yes") {
            Write-Host "Action cancelled" -ForegroundColor Yellow
            return
        }
    }
    
    $results = @()
    foreach ($target in $actionableTargets) {
        Write-Host "Taking action on $($target.Endpoint)..." -ForegroundColor Cyan
        
        $params = @{ agentId = $target.EndpointId }
        
        if ($Action -eq "kill-process" -and $target.ProcessId) {
            $params.processId = $target.ProcessId
        }
        elseif ($Action -eq "quarantine" -and $target.FilePath) {
            $params.filePath = $target.FilePath
        }
        
        $result = Invoke-S1Action -Platform $target.Platform -Action $Action -Parameters $params
        $results += $result
        
        if ($result.Success) {
            Write-Host "  ✓ Success" -ForegroundColor Green
        }
        else {
            Write-Host "  ✗ Failed: $($result.Error)" -ForegroundColor Red
        }
    }
    
    return $results
}

# Internal functions for actual API calls
function Invoke-S1IsolateInternal {
    param([hashtable]$Connection, [hashtable]$Parameters)
    
    $body = @{
        filter = @{
            ids = @($Parameters.agentId)
        }
    }
    
    $response = Invoke-RestMethod -Uri "$($Connection.BaseUri)/agents/actions/disconnect" `
        -Method Post -Headers $Connection.Headers `
        -Body ($body | ConvertTo-Json -Depth 10) `
        -ErrorAction Stop
    
    return $response.data
}

function Invoke-S1UnisolateInternal {
    param([hashtable]$Connection, [hashtable]$Parameters)
    
    $body = @{
        filter = @{
            ids = @($Parameters.agentId)
        }
    }
    
    $response = Invoke-RestMethod -Uri "$($Connection.BaseUri)/agents/actions/connect" `
        -Method Post -Headers $Connection.Headers `
        -Body ($body | ConvertTo-Json -Depth 10) `
        -ErrorAction Stop
    
    return $response.data
}

function Invoke-S1KillProcessInternal {
    param([hashtable]$Connection, [hashtable]$Parameters)
    
    $body = @{
        filter = @{
            ids = @($Parameters.agentId)
        }
        data = @{
            processId = $Parameters.processId
        }
    }
    
    $response = Invoke-RestMethod -Uri "$($Connection.BaseUri)/agents/actions/kill-process" `
        -Method Post -Headers $Connection.Headers `
        -Body ($body | ConvertTo-Json -Depth 10) `
        -ErrorAction Stop
    
    return $response.data
}

function Invoke-S1QuarantineFileInternal {
    param([hashtable]$Connection, [hashtable]$Parameters)
    
    $body = @{
        filter = @{
            ids = @($Parameters.agentId)
        }
        data = @{
            filePath = $Parameters.filePath
        }
    }
    
    $response = Invoke-RestMethod -Uri "$($Connection.BaseUri)/agents/actions/quarantine" `
        -Method Post -Headers $Connection.Headers `
        -Body ($body | ConvertTo-Json -Depth 10) `
        -ErrorAction Stop
    
    return $response.data
}

function Invoke-S1InitiateScanInternal {
    param([hashtable]$Connection, [hashtable]$Parameters)
    
    $body = @{
        filter = @{
            ids = @($Parameters.agentId)
        }
    }
    
    $response = Invoke-RestMethod -Uri "$($Connection.BaseUri)/agents/actions/initiate-scan" `
        -Method Post -Headers $Connection.Headers `
        -Body ($body | ConvertTo-Json -Depth 10) `
        -ErrorAction Stop
    
    return $response.data
}

Export-ModuleMember -Function Invoke-S1Action, Invoke-S1Isolate, Invoke-S1Unisolate, Invoke-S1KillProcess, Invoke-S1QuarantineFile, Invoke-S1InitiateScan, Invoke-BulkResponse

