# RiverRunThreatHunter

Multi-platform threat hunting tool for MSP with integration for SentinelOne (ConnectWise S1), Perch SIEM, ConnectWise Manage, and Memberberry.

## Features

- **Multi-Platform Threat Hunting**: Query SentinelOne Deep Visibility and Perch SIEM across multiple clients
- **MSP Multi-Tenant Support**: Hunt across all clients or filter by platform
- **False Positive Management**: Track and filter known false positives with Memberberry integration
- **S1 Exclusions**: Create and manage SentinelOne exclusions (ConnectWise S1 only)
- **Response Actions**: Isolate, quarantine, and kill processes on ConnectWise S1 endpoints
- **ConnectWise Integration**: Extract IOCs from tickets and update with hunt results
- **Memberberry Integration**: Use client context and false positive patterns from Memberberry
- **WPF GUI**: Desktop application for SOC analysts

## Project Structure

```
RiverRunThreatHunter/
├── modules/              # PowerShell modules (backend)
├── config/              # Configuration files
├── src/                 # WPF GUI application
└── README.md
```

## Setup

1. Configure `config/ClientConfig.json` with your platforms and clients
2. Set API tokens using `Set-PlatformToken` cmdlet:
   ```powershell
   Import-Module .\modules\ConnectionManager.psm1
   Set-PlatformToken -Platform "ConnectWiseS1"
   ```
3. Test connections:
   ```powershell
   Test-AllConnections
   ```

## Usage

### PowerShell Modules

```powershell
# Import modules
Import-Module .\modules\UnifiedHuntEngine.psm1

# Hunt IOCs for a client
$iocs = @(@{ Type = "hash"; Value = "abc123..." })
$results = Invoke-ClientThreatHunt -IOCs $iocs -ClientName "AcmeCorp"

# Hunt across all clients
$results = Invoke-MultiClientThreatHunt -IOCs $iocs
```

### WPF GUI

Launch the application:
```
RiverRunThreatHunter.exe
```

## Configuration

Edit `config/ClientConfig.json` to add clients and configure platform mappings.

## Requirements

- PowerShell 5.1+
- .NET 6.0+ (for WPF GUI)
- SentinelOne API access
- Perch API access (optional)
- ConnectWise Manage API access (optional)
- Memberberry installation at C:\git\memberberry (optional)

## License

Internal use only - River Run Security Team

