# Wrapper script to call Get-AllClients and output JSON
# This avoids runspace issues by running in a separate PowerShell process

$ErrorActionPreference = "Stop"

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
            Write-Warning "DEBUG: Found modules using fallback (level $i): $modulesPath"
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
                Write-Warning "DEBUG: Found modules at project root: $modulesPath"
                break
            }
        }
    }
    
    if (-not $modulesPath) {
        Write-Error "ERROR: Could not find modules directory. Tried all paths."
        exit 1
    }
}

# Import required modules
Import-Module (Join-Path $modulesPath "ThreatHuntConfig.psm1") -Force -ErrorAction Stop

# Initialize config
Initialize-ThreatHuntConfig -ErrorAction SilentlyContinue

# Call function and output JSON
try {
    $clients = Get-AllClients
    $clients | ConvertTo-Json -Depth 10
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}

