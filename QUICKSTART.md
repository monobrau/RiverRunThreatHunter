# Quick Start Guide

## Option 1: Run PowerShell Modules Directly (Recommended for Testing)

### Step 1: Configure Your Environment

1. **Open PowerShell** (as Administrator recommended)

2. **Navigate to the project directory:**
   ```powershell
   cd C:\git\RiverRunThreatHunter
   ```

3. **Set execution policy** (if needed):
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

### Step 2: Configure Client Settings

1. **Edit `config\ClientConfig.json`** with your actual:
   - SentinelOne instance URLs
   - Client names and site IDs
   - Perch team IDs (if applicable)

2. **Set API tokens:**
   ```powershell
   # Import the connection manager module
   Import-Module .\modules\ConnectionManager.psm1
   
   # Set tokens for each platform
   Set-PlatformToken -Platform "ConnectWiseS1"
   Set-PlatformToken -Platform "PerchSIEM"  # If using Perch
   ```

3. **Test connections:**
   ```powershell
   Import-Module .\modules\ConnectionManager.psm1
   Test-AllConnections
   ```

### Step 3: Run a Threat Hunt

```powershell
# Import all modules
Import-Module .\modules\ThreatHuntConfig.psm1
Import-Module .\modules\UnifiedHuntEngine.psm1

# Initialize config
Initialize-ThreatHuntConfig

# Define IOCs to hunt
$iocs = @(
    @{ Type = "hash"; Value = "abc123def456..." },
    @{ Type = "ip"; Value = "192.168.1.100" },
    @{ Type = "domain"; Value = "malicious-domain.com" }
)

# Hunt for a specific client
$results = Invoke-ClientThreatHunt -IOCs $iocs -ClientName "YourClientName" -DaysBack 14

# Or hunt across all clients
$results = Invoke-MultiClientThreatHunt -IOCs $iocs

# View summary
Get-HuntSummary -Results $results
```

### Step 4: Extract IOCs from ConnectWise Ticket

```powershell
Import-Module .\modules\ConnectWiseManage.psm1

# Configure CW credentials (set environment variables or edit module)
$env:CW_COMPANY_ID = "your-company-id"
$env:CW_PUBLIC_KEY = "your-public-key"
$env:CW_PRIVATE_KEY = "your-private-key"
$env:CW_BASE_URL = "https://api-connectwise.com"

# Get ticket and extract IOCs
$ticket = Get-CWTicket -TicketId 123456
$iocs = Extract-IOCsFromTicket -Ticket $ticket

# Hunt the IOCs
$results = Invoke-MultiClientThreatHunt -IOCs $iocs
```

---

## Option 2: Build and Run WPF GUI Application

### Prerequisites

- **.NET 6.0 SDK** or later ([Download here](https://dotnet.microsoft.com/download))
- **Visual Studio 2022** (recommended) or **Visual Studio Code** with C# extension

### Step 1: Build the Application

**Using Visual Studio:**
1. Open `RiverRunThreatHunter.sln` in Visual Studio 2022
2. Restore NuGet packages (right-click solution → Restore NuGet Packages)
3. Build solution (Build → Build Solution or Ctrl+Shift+B)
4. Run (F5 or Debug → Start Debugging)

**Using Command Line:**
```powershell
cd C:\git\RiverRunThreatHunter\src
dotnet restore
dotnet build
dotnet run
```

### Step 2: Configure Before First Run

Before running the GUI, you must:
1. Configure `config\ClientConfig.json` with your clients
2. Set API tokens using PowerShell (see Option 1, Step 2)
3. Ensure all modules are in the `modules\` folder

### Step 3: Run the GUI

**From Visual Studio:**
- Press F5 or click "Start Debugging"

**From Command Line:**
```powershell
cd C:\git\RiverRunThreatHunter\src
dotnet run
```

**Run compiled executable:**
```powershell
cd C:\git\RiverRunThreatHunter\src\bin\Debug\net6.0-windows
.\RiverRunThreatHunter.exe
```

---

## Troubleshooting

### PowerShell Execution Policy Error

If you get an execution policy error:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Module Not Found

Make sure you're running PowerShell from the project root:
```powershell
cd C:\git\RiverRunThreatHunter
```

### API Connection Errors

1. Verify tokens are set correctly:
   ```powershell
   Test-AllConnections
   ```

2. Check `config\ClientConfig.json` has correct URLs

3. Ensure API tokens have proper permissions

### WPF GUI Won't Start

1. Ensure .NET 6.0+ is installed:
   ```powershell
   dotnet --version
   ```

2. Restore packages:
   ```powershell
   cd C:\git\RiverRunThreatHunter\src
   dotnet restore
   ```

3. Check for build errors:
   ```powershell
   dotnet build
   ```

---

## Example Workflow

```powershell
# 1. Import modules
cd C:\git\RiverRunThreatHunter
Import-Module .\modules\ThreatHuntConfig.psm1
Import-Module .\modules\UnifiedHuntEngine.psm1
Import-Module .\modules\ConnectWiseManage.psm1
Import-Module .\modules\MemberberryIntegration.psm1

# 2. Initialize config
Initialize-ThreatHuntConfig

# 3. Get ticket from ConnectWise
$ticket = Get-CWTicket -TicketId 123456

# 4. Extract IOCs
$iocs = Extract-IOCsFromTicket -Ticket $ticket

# 5. Identify client (using Memberberry)
$clientName = Get-ClientFromMemberberry -TicketText $ticket

# 6. Hunt IOCs
$results = Invoke-ClientThreatHunt -IOCs $iocs -ClientName $clientName

# 7. Filter false positives
Import-Module .\modules\FalsePositiveManager.psm1
$filteredResults = Filter-FalsePositives -HuntResults $results

# 8. View summary
Get-HuntSummary -Results $filteredResults

# 9. Take action (if needed)
Import-Module .\modules\ResponseActions.psm1
$actionable = $filteredResults | Where-Object { $_.CanTakeAction }
Invoke-BulkResponse -Targets $actionable -Action "isolate"

# 10. Generate report
Import-Module .\modules\Reporting.psm1
New-ThreatHuntReport -Results $filteredResults -OutputFormat "HTML" -OutputPath "report.html"
```

