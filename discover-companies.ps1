<#
.SYNOPSIS
    Discovers companies/sites from SentinelOne and Perch platforms
.DESCRIPTION
    Pulls all sites from SentinelOne and teams from Perch to help populate ClientConfig.json
.PARAMETER Platform
    Platform to discover from: "ConnectWiseS1" or "PerchSIEM" (default: both)
.PARAMETER ExportToJson
    Export results to JSON file for easy import
.PARAMETER UpdateConfig
    Automatically update ClientConfig.json with discovered companies (interactive)
.EXAMPLE
    .\discover-companies.ps1
    # Lists all sites from S1 and teams from Perch
    
.EXAMPLE
    .\discover-companies.ps1 -Platform "ConnectWiseS1" -ExportToJson
    # Only discover from S1 and export to JSON
    
.EXAMPLE
    .\discover-companies.ps1 -UpdateConfig
    # Discover and interactively update ClientConfig.json
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("ConnectWiseS1", "PerchSIEM", "All")]
    [string]$Platform = "All",
    
    [Parameter(Mandatory=$false)]
    [switch]$ExportToJson,
    
    [Parameter(Mandatory=$false)]
    [switch]$UpdateConfig
)

Write-Host "=== Company Discovery Tool ===" -ForegroundColor Cyan
Write-Host ""

# Import modules
try {
    Import-Module .\modules\ConnectionManager.psm1 -Force -ErrorAction Stop
    Import-Module .\modules\ThreatHuntConfig.psm1 -Force -ErrorAction Stop
    Import-Module .\modules\SentinelOneHunter.psm1 -Force -ErrorAction Stop
    Import-Module .\modules\PerchHunter.psm1 -Force -ErrorAction Stop
    
    # Clear connection cache to ensure fresh connections
    Clear-ConnectionCache -ErrorAction SilentlyContinue
}
catch {
    Write-Host "ERROR: Failed to import modules: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$discoveredSites = @()
$discoveredTeams = @()

# Discover SentinelOne sites
if ($Platform -eq "All" -or $Platform -eq "ConnectWiseS1") {
    Write-Host "Discovering SentinelOne sites..." -ForegroundColor Yellow
    try {
        $s1Conn = Get-PlatformConnection -Platform "ConnectWiseS1"
        $sites = Get-S1Sites -Connection $s1Conn
        
        Write-Host "Found $($sites.Count) SentinelOne sites" -ForegroundColor Green
        Write-Host ""
        
        if ($sites.Count -gt 0) {
            $sites | Format-Table SiteId, SiteName, TotalAgents, ActiveAgents, HealthStatus -AutoSize
            $discoveredSites = $sites
        }
    }
    catch {
        Write-Host "✗ Failed to discover SentinelOne sites: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Make sure you have API access to ConnectWise S1" -ForegroundColor Yellow
    }
    Write-Host ""
}

# Discover Perch teams
if ($Platform -eq "All" -or $Platform -eq "PerchSIEM") {
    Write-Host "Discovering Perch teams..." -ForegroundColor Yellow
    try {
        $perchConn = Get-PlatformConnection -Platform "PerchSIEM"
        $teams = Get-PerchTeams -Connection $perchConn
        
        Write-Host "Found $($teams.Count) Perch teams" -ForegroundColor Green
        Write-Host ""
        
        if ($teams.Count -gt 0) {
            $teams | Format-Table TeamId, TeamName, Status, MemberCount -AutoSize
            $discoveredTeams = $teams
        }
    }
    catch {
        Write-Host "✗ Failed to discover Perch teams: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Make sure you have API access to Perch SIEM" -ForegroundColor Yellow
    }
    Write-Host ""
}

# Export to JSON if requested
if ($ExportToJson) {
    $exportData = @{
        SentinelOneSites = $discoveredSites
        PerchTeams = $discoveredTeams
        DiscoveredAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    
    $exportPath = "discovered-companies-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $exportData | ConvertTo-Json -Depth 10 | Out-File $exportPath
    
    Write-Host "✓ Exported discovery results to: $exportPath" -ForegroundColor Green
    Write-Host ""
}

# Update config if requested
if ($UpdateConfig) {
    Write-Host "=== Update ClientConfig.json ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "This will help you add discovered companies to ClientConfig.json" -ForegroundColor Yellow
    Write-Host ""
    
    Initialize-ThreatHuntConfig
    
    # Match S1 sites with Perch teams by name
    foreach ($site in $discoveredSites) {
        Write-Host "Site: $($site.SiteName) (ID: $($site.SiteId))" -ForegroundColor Cyan
        
        # Find matching Perch team
        $matchingTeam = $discoveredTeams | Where-Object { 
            $_.TeamName -like "*$($site.SiteName)*" -or 
            $site.SiteName -like "*$($_.TeamName)*"
        } | Select-Object -First 1
        
        if ($matchingTeam) {
            Write-Host "  → Matched Perch Team: $($matchingTeam.TeamName) (ID: $($matchingTeam.TeamId))" -ForegroundColor Green
        }
        else {
            Write-Host "  → No matching Perch team found" -ForegroundColor Gray
        }
        
        $add = Read-Host "  Add to ClientConfig.json? (y/n)"
        if ($add -eq "y" -or $add -eq "Y") {
            Write-Host "  Note: You'll need to manually add this to ClientConfig.json with:" -ForegroundColor Yellow
            Write-Host "    - CWCompanyId (from ConnectWise)" -ForegroundColor Gray
            Write-Host "    - S1SiteId: $($site.SiteId)" -ForegroundColor Gray
            if ($matchingTeam) {
                Write-Host "    - PerchTeamId: $($matchingTeam.TeamId)" -ForegroundColor Gray
                Write-Host "    - HasPerch: true" -ForegroundColor Gray
            }
            Write-Host ""
        }
    }
}

Write-Host ""
Write-Host "=== Discovery Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Use this information to populate ClientConfig.json with your clients." -ForegroundColor Cyan
Write-Host ""

