# Wrapper script to validate Perch API connection
# Perch API v1 does not support team discovery - this validates connectivity only
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
    $fullPath = [System.IO.Path]::GetFullPath($path)
    if (Test-Path $fullPath) {
        $modulesPath = $fullPath
        break
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

# Import required modules (suppress warnings about unapproved verbs)
try {
    Import-Module (Join-Path $modulesPath "ConnectionManager.psm1") -Force -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
    Import-Module (Join-Path $modulesPath "ThreatHuntConfig.psm1") -Force -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
    Import-Module (Join-Path $modulesPath "PerchHunter.psm1") -Force -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
}
catch {
    Write-Error "Failed to import modules: $($_.Exception.Message)"
    exit 1
}

# Initialize config
try {
    Initialize-ThreatHuntConfig -ErrorAction SilentlyContinue
}
catch {
    # Config initialization failure is OK - connection might still work
    Write-DebugToStderr "Config initialization warning: $($_.Exception.Message)"
}

# Call function and output JSON
try {
    Write-Verbose "Getting platform connection for PerchSIEM..."
    $conn = Get-PlatformConnection -Platform "PerchSIEM" -ErrorAction Stop
    
    if (-not $conn) {
        Write-Error "Failed to get platform connection. Check your Perch token files (.perch_token, .perch_apikey, etc.)"
        exit 1
    }
    
    if (-not $conn.BaseUri) {
        Write-Error "Connection object missing BaseUri. Check your Perch token configuration."
        exit 1
    }
    
    Write-Verbose "Connection established. BaseUri: $($conn.BaseUri)"
    
    # Output connection info to stderr for debugging
    Write-DebugToStderr "DEBUG: BaseUri = $($conn.BaseUri)"
    if ($conn.Headers) {
        $headerKeys = $conn.Headers.Keys -join ", "
        Write-DebugToStderr "DEBUG: Headers present: $headerKeys"
        if ($conn.Headers.ContainsKey("Authorization")) {
            $authPreview = $conn.Headers["Authorization"].Substring(0, [Math]::Min(30, $conn.Headers["Authorization"].Length)) + "..."
            Write-DebugToStderr "DEBUG: Authorization header: $authPreview"
        }
        if ($conn.Headers.ContainsKey("x-api-key")) {
            $keyPreview = $conn.Headers["x-api-key"].Substring(0, [Math]::Min(20, $conn.Headers["x-api-key"].Length)) + "..."
            Write-DebugToStderr "DEBUG: x-api-key header: $keyPreview"
        }
    }
    else {
        Write-DebugToStderr "DEBUG: No headers in connection object"
    }
    
    Write-Verbose "Testing Perch API connection..."
    
    # Perch API v1 connectivity validation
    $result = Test-PerchConnection -Connection $conn -ErrorAction Stop
    
    if ($result.Success) {
        Write-Verbose "Perch API connection successful"
        Write-DebugToStderr "DEBUG: Connection validated successfully"
        Write-DebugToStderr "DEBUG: BaseUri = $($result.BaseUri)"
        Write-DebugToStderr "DEBUG: StatusCode = $($result.StatusCode)"
        # Return empty array - Perch API v1 does not support team discovery
        # Site discovery is handled by SentinelOne (XDR), not Perch (SIEM)
        # Write directly to stdout to avoid PowerShell output system
        [Console]::Out.WriteLine("[]")
    }
    else {
        Write-DebugToStderr "Perch API connection validation failed"
        Write-DebugToStderr "DEBUG: StatusCode = $($result.StatusCode)"
        Write-DebugToStderr "DEBUG: Error = $($result.Error)"
        # Write directly to stdout to avoid PowerShell output system
        [Console]::Out.WriteLine("[]")
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

