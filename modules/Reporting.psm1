<#
.SYNOPSIS
    Threat Hunt Reporting Module
.DESCRIPTION
    Generates reports in various formats (HTML, CSV, JSON) and updates
    ConnectWise tickets with hunt results.
.NOTES
    Author: River Run Security Team
    Version: 1.0
#>

function New-ThreatHuntReport {
    <#
    .SYNOPSIS
        Generates threat hunt report in specified format
    .DESCRIPTION
        Creates comprehensive report with summary, IOC details, hits, and recommendations.
    .PARAMETER Results
        Array of hunt result objects
    .PARAMETER OutputFormat
        Report format: HTML, CSV, or JSON
    .PARAMETER OutputPath
        Path to save report file
    .PARAMETER TicketId
        Optional ConnectWise ticket ID for reference
    .EXAMPLE
        New-ThreatHuntReport -Results $huntResults -OutputFormat "HTML" -OutputPath "report.html"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$Results,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("HTML", "CSV", "JSON")]
        [string]$OutputFormat = "HTML",
        
        [Parameter(Mandatory=$false)]
        [string]$OutputPath,
        
        [Parameter(Mandatory=$false)]
        [string]$TicketId
    )
    
    $summary = Get-HuntSummary -Results $Results -ErrorAction SilentlyContinue
    
    switch ($OutputFormat) {
        "HTML" {
            $html = New-HTMLReport -Results $Results -Summary $summary -TicketId $TicketId
            if ($OutputPath) {
                $html | Out-File -FilePath $OutputPath -Encoding UTF8
                Write-Host "HTML report saved to $OutputPath" -ForegroundColor Green
            }
            return $html
        }
        "CSV" {
            $csv = $Results | ConvertTo-Csv -NoTypeInformation
            if ($OutputPath) {
                $csv | Out-File -FilePath $OutputPath -Encoding UTF8
                Write-Host "CSV report saved to $OutputPath" -ForegroundColor Green
            }
            return $csv
        }
        "JSON" {
            $json = @{
                Summary = $summary
                Results = $Results
                Generated = (Get-Date).ToString("o")
                TicketId = $TicketId
            } | ConvertTo-Json -Depth 10
            if ($OutputPath) {
                $json | Out-File -FilePath $OutputPath -Encoding UTF8
                Write-Host "JSON report saved to $OutputPath" -ForegroundColor Green
            }
            return $json
        }
    }
}

function New-HTMLReport {
    <#
    .SYNOPSIS
        Generates HTML report
    #>
    [CmdletBinding()]
    param(
        [array]$Results,
        [object]$Summary,
        [string]$TicketId
    )
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Threat Hunt Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #2c3e50; }
        h2 { color: #34495e; border-bottom: 2px solid #3498db; padding-bottom: 5px; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #3498db; color: white; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .summary { background-color: #ecf0f1; padding: 15px; border-radius: 5px; margin: 20px 0; }
        .hit { color: #e74c3c; font-weight: bold; }
        .no-hit { color: #27ae60; }
        .actionable { background-color: #fff3cd; }
    </style>
</head>
<body>
    <h1>Threat Hunt Report</h1>
    <p><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
"@
    
    if ($TicketId) {
        $html += "<p><strong>ConnectWise Ticket:</strong> $TicketId</p>"
    }
    
    if ($Summary) {
        $html += @"
    <div class="summary">
        <h2>Executive Summary</h2>
        <ul>
            <li><strong>Total Hits:</strong> $($Summary.TotalHits)</li>
            <li><strong>Clients Affected:</strong> $($Summary.ClientsAffected)</li>
            <li><strong>Actionable Hits:</strong> $($Summary.ActionableHits)</li>
            <li><strong>Read-Only Hits:</strong> $($Summary.ReadOnlyHits)</li>
            <li><strong>Correlated IOCs:</strong> $($Summary.CorrelatedIOCs)</li>
            <li><strong>Unique Endpoints:</strong> $($Summary.UniqueEndpoints)</li>
        </ul>
    </div>
"@
    }
    
    # Hits by Client
    $html += @"
    <h2>Hits by Client</h2>
    <table>
        <tr>
            <th>Client</th>
            <th>Hits</th>
            <th>Platform</th>
            <th>Actionable</th>
        </tr>
"@
    
    $Results | Group-Object Client | ForEach-Object {
        $client = $_.Name
        $hits = $_.Count
        $platform = ($_.Group | Select-Object -First 1).Platform
        $actionable = ($_.Group | Where-Object { $_.CanTakeAction }).Count -gt 0
        $actionableText = if ($actionable) { "Yes" } else { "No" }
        $rowClass = if ($actionable) { "class='actionable'" } else { "" }
        
        $html += "<tr $rowClass><td>$client</td><td>$hits</td><td>$platform</td><td>$actionableText</td></tr>"
    }
    
    $html += "</table>"
    
    # Detailed Results
    $html += @"
    <h2>Detailed Results</h2>
    <table>
        <tr>
            <th>Timestamp</th>
            <th>Client</th>
            <th>Source</th>
            <th>IOC</th>
            <th>IOC Type</th>
            <th>Endpoint</th>
            <th>User</th>
            <th>Process</th>
            <th>Event Type</th>
        </tr>
"@
    
    $Results | Sort-Object Timestamp -Descending | ForEach-Object {
        $html += "<tr>"
        $html += "<td>$($_.Timestamp)</td>"
        $html += "<td>$($_.Client)</td>"
        $html += "<td>$($_.Source)</td>"
        $html += "<td>$($_.IOC)</td>"
        $html += "<td>$($_.IOCType)</td>"
        $html += "<td>$($_.Endpoint)</td>"
        $html += "<td>$($_.User)</td>"
        $html += "<td>$($_.ProcessName)</td>"
        $html += "<td>$($_.EventType)</td>"
        $html += "</tr>"
    }
    
    $html += "</table>"
    
    # Recommendations
    $html += @"
    <h2>Recommendations</h2>
    <ul>
"@
    
    $actionableResults = $Results | Where-Object { $_.CanTakeAction }
    if ($actionableResults) {
        $html += "<li><strong>Immediate Actions:</strong> $($actionableResults.Count) endpoints require response actions (isolate, quarantine, etc.)</li>"
    }
    
    $correlated = $Results | Group-Object IOC | Where-Object {
        $types = $_.Group.SourceType | Select-Object -Unique
        ($types -contains "Endpoint") -and ($types -contains "Network")
    }
    
    if ($correlated) {
        $html += "<li><strong>Correlated Threats:</strong> $($correlated.Count) IOCs detected on both endpoint and network - high confidence indicators</li>"
    }
    
    $html += "</ul>"
    
    $html += @"
    <hr>
    <p><em>Report generated by RiverRunThreatHunter</em></p>
</body>
</html>
"@
    
    return $html
}

function Export-HuntResults {
    <#
    .SYNOPSIS
        Exports hunt results to file
    .DESCRIPTION
        Convenience function to export results in various formats.
    .PARAMETER Results
        Array of hunt result objects
    .PARAMETER Format
        Export format (CSV, JSON, HTML)
    .PARAMETER Path
        Output file path
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [array]$Results,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("CSV", "JSON", "HTML")]
        [string]$Format = "CSV",
        
        [Parameter(Mandatory=$true)]
        [string]$Path
    )
    
    switch ($Format) {
        "CSV" {
            $Results | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
        }
        "JSON" {
            $Results | ConvertTo-Json -Depth 10 | Out-File -FilePath $Path -Encoding UTF8
        }
        "HTML" {
            New-ThreatHuntReport -Results $Results -OutputFormat "HTML" -OutputPath $Path
        }
    }
    
    Write-Host "Results exported to $Path" -ForegroundColor Green
}

Export-ModuleMember -Function New-ThreatHuntReport, Export-HuntResults

