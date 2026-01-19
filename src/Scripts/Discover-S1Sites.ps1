# Wrapper script to discover SentinelOne sites and output JSON
# This avoids runspace issues by running in a separate PowerShell process

$ErrorActionPreference = "Continue"
$WarningPreference = "Continue"

# Redirect all warnings to stderr so stdout only contains JSON
function Write-DebugToStderr {
    param([string]$Message)
    [Console]::Error.WriteLine($Message)
}

# Suppress ALL PowerShell streams - we only want JSON on stdout
$WarningPreference = "SilentlyContinue"
$InformationPreference = "SilentlyContinue"
$VerbosePreference = "SilentlyContinue"
$DebugPreference = "SilentlyContinue"

# Redirect warning stream to stderr
$PSDefaultParameterValues['*:WarningAction'] = 'SilentlyContinue'
$PSDefaultParameterValues['*:InformationAction'] = 'SilentlyContinue'
$PSDefaultParameterValues['*:Verbose'] = $false
$PSDefaultParameterValues['*:Debug'] = $false

# Get script directory - handle both direct execution and execution from GUI
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
# Try multiple paths to find modules (including going up to project root from build output)
$possibleModulePaths = @(
    (Join-Path $scriptDir "..\modules"),                    # If script is in src\Scripts or bin\Debug\...\Scripts
    (Join-Path (Split-Path $scriptDir -Parent) "modules"),  # Parent of Scripts
    (Join-Path (Split-Path (Split-Path $scriptDir -Parent) -Parent) "modules"),  # 2 levels up
    (Join-Path (Split-Path (Split-Path (Split-Path $scriptDir -Parent) -Parent) -Parent) "modules"),  # 3 levels up
    (Join-Path (Split-Path (Split-Path (Split-Path (Split-Path $scriptDir -Parent) -Parent) -Parent) -Parent) "modules"),  # 4 levels up (project root)
    (Join-Path $PSScriptRoot "..\modules"),                 # Relative to script root
    (Join-Path (Get-Location) "modules"),                   # Current working directory
    "modules"                                                # Current directory
)

$modulesPath = $null
foreach ($path in $possibleModulePaths) {
    try {
        $fullPath = [System.IO.Path]::GetFullPath($path)
        if (Test-Path $fullPath) {
            $modulesPath = $fullPath
            Write-DebugToStderr "DEBUG: Found modules at: $modulesPath"
            break
        }
    }
    catch {
        # Continue trying other paths
    }
}

if (-not $modulesPath) {
    # Fallback: try going up to project root (for build output scenarios)
    $currentPath = $scriptDir
    for ($i = 0; $i -lt 5; $i++) {
            $testPath = Join-Path $currentPath "modules"
        if (Test-Path $testPath) {
            $modulesPath = $testPath
            Write-DebugToStderr "DEBUG: Found modules using fallback (level $i): $modulesPath"
            break
        }
        $parentPath = Split-Path $currentPath -Parent
        if ($parentPath -eq $currentPath) { break }  # Reached root
        $currentPath = $parentPath
    }
    
    if (-not $modulesPath) {
        # Last resort: try project root from common build paths
        $projectRoots = @(
            (Join-Path $env:USERPROFILE "RiverRunThreatHunter"),
            "C:\git\RiverRunThreatHunter",
            (Split-Path (Split-Path (Split-Path (Split-Path $scriptDir -Parent) -Parent) -Parent) -Parent)
        )
        foreach ($root in $projectRoots) {
            $testPath = Join-Path $root "modules"
            if (Test-Path $testPath) {
                $modulesPath = $testPath
                Write-DebugToStderr "DEBUG: Found modules at project root: $modulesPath"
                break
            }
        }
    }
    
    if (-not $modulesPath) {
        Write-Error "ERROR: Could not find modules directory. Tried all paths."
        exit 1
    }
}

Write-DebugToStderr "DEBUG: Script directory: $scriptDir"
Write-DebugToStderr "DEBUG: Working directory: $(Get-Location)"
Write-DebugToStderr "DEBUG: Modules path: $modulesPath"

# Import required modules (suppress ALL output to stdout)
try {
    Import-Module (Join-Path $modulesPath "ConnectionManager.psm1") -Force -ErrorAction Stop -WarningAction SilentlyContinue 6>&1 | Out-Null
    Import-Module (Join-Path $modulesPath "ThreatHuntConfig.psm1") -Force -ErrorAction Stop -WarningAction SilentlyContinue 6>&1 | Out-Null
    Import-Module (Join-Path $modulesPath "SentinelOneHunter.psm1") -Force -ErrorAction Stop -WarningAction SilentlyContinue 6>&1 | Out-Null
}
catch {
    Write-Error "Failed to import modules: $($_.Exception.Message)" 2>&1 | Out-Null
    [Console]::Error.WriteLine("ERROR: Failed to import modules: $($_.Exception.Message)")
    exit 1
}

# Initialize config
try {
    Initialize-ThreatHuntConfig -ErrorAction SilentlyContinue 2>&1 | Out-Null
}
catch {
    # Config initialization failure is OK - connection might still work
    Write-DebugToStderr "Config initialization warning: $($_.Exception.Message)"
}

# Call function and output JSON
try {
    Write-Verbose "Getting platform connection for ConnectWiseS1..."
    $conn = Get-PlatformConnection -Platform "ConnectWiseS1" -ErrorAction Stop
    
    if (-not $conn) {
        Write-Error "Failed to get platform connection. Check your token file (.s1token_connectwise)"
        exit 1
    }
    
    if (-not $conn.BaseUri) {
        Write-Error "Connection object missing BaseUri. Check your token configuration."
        exit 1
    }
    
    Write-Verbose "Connection established. BaseUri: $($conn.BaseUri)"
    
    # Output connection info to stderr for debugging
    Write-DebugToStderr "DEBUG: BaseUri = $($conn.BaseUri)"
    if ($conn.Headers) {
        $headerKeys = $conn.Headers.Keys -join ", "
        Write-DebugToStderr "DEBUG: Headers present: $headerKeys"
    }
    else {
        Write-DebugToStderr "DEBUG: No headers in connection object"
    }
    
    Write-Verbose "Calling Get-S1Sites..."
    
    $sites = Get-S1Sites -Connection $conn -ErrorAction Stop
    
    if ($null -eq $sites) {
        Write-DebugToStderr "Get-S1Sites returned null"
        [Console]::Out.WriteLine("[]")
    }
    elseif ($sites.Count -eq 0) {
        Write-DebugToStderr "Get-S1Sites returned empty array - no sites found"
        Write-DebugToStderr "DEBUG: This could mean:"
        Write-DebugToStderr "  1. API token has no site access"
        Write-DebugToStderr "  2. Account has no sites configured"
        Write-DebugToStderr "  3. API endpoint/pagination issue"
        [Console]::Out.WriteLine("[]")
    }
    else {
        Write-DebugToStderr "Found $($sites.Count) sites"
        # ONLY output JSON to stdout - suppress everything else
        # Use explicit redirection to ensure only JSON goes to stdout
        $jsonOutput = $sites | ConvertTo-Json -Depth 10 -Compress
        # Write directly to stdout stream, bypassing PowerShell's output system
        [Console]::Out.WriteLine($jsonOutput)
    }
}
catch {
    # Output error to stderr so it doesn't interfere with JSON output
    $errorMsg = "ERROR: $($_.Exception.Message)"
    [Console]::Error.WriteLine($errorMsg)
    # Also output empty array so caller gets valid JSON
    [Console]::Out.WriteLine("[]")
    exit 1
}

