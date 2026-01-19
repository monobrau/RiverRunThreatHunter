@echo off
REM RiverRunThreatHunter Launcher
REM Launches WPF GUI or PowerShell with modules loaded

setlocal

REM Get script directory
set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%"

REM Check for mode parameter (default to GUI)
set "MODE=%1"
if "%MODE%"=="" set "MODE=GUI"
if /i "%MODE%"=="ps" set "MODE=PowerShell"
if /i "%MODE%"=="powershell" set "MODE=PowerShell"

if /i "%MODE%"=="PowerShell" goto :PowerShellMode
goto :GUIMode

:PowerShellMode
echo Loading PowerShell modules...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& {Get-ChildItem -Path 'modules\*.psm1' | ForEach-Object {Write-Host ('  - ' + $_.BaseName) -ForegroundColor Gray; Import-Module $_.FullName -ErrorAction SilentlyContinue}; Write-Host ''; Write-Host 'Modules loaded! Try:' -ForegroundColor Green; Write-Host '  Initialize-ThreatHuntConfig' -ForegroundColor Yellow; Write-Host '  Test-AllConnections' -ForegroundColor Yellow; Write-Host '  Get-AllClients' -ForegroundColor Yellow; Write-Host ''; Write-Host 'Starting PowerShell...' -ForegroundColor Cyan}"
powershell.exe -NoProfile -ExecutionPolicy Bypass
goto :end

:GUIMode
echo Building and launching WPF GUI...
echo.

REM Check if dotnet is available
where dotnet >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: .NET SDK not found. Please install .NET 6.0 or later.
    echo Download from: https://dotnet.microsoft.com/download
    pause
    exit /b 1
)

REM Get dotnet version
for /f "tokens=*" %%i in ('dotnet --version 2^>nul') do set DOTNET_VERSION=%%i
echo Found .NET SDK version: %DOTNET_VERSION%
echo.

cd src

echo Restoring packages...
call dotnet restore
if %ERRORLEVEL% NEQ 0 (
    echo Restore failed!
    pause
    exit /b 1
)

echo.
echo Building application...
call dotnet build
if %ERRORLEVEL% NEQ 0 (
    echo Build failed! Check errors above.
    pause
    exit /b 1
)

echo.
echo Launching GUI...
call dotnet run

cd ..

:end
endlocal

