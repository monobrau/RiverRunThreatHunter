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

REM Ensure dotnet is in PATH - check common installation paths
set "DOTNET_PATH="
if exist "C:\Program Files\dotnet\dotnet.exe" (
    set "DOTNET_PATH=C:\Program Files\dotnet"
) else if exist "C:\Program Files (x86)\dotnet\dotnet.exe" (
    set "DOTNET_PATH=C:\Program Files (x86)\dotnet"
)

REM Add dotnet to PATH if found and not already there
if not "%DOTNET_PATH%"=="" (
    echo %PATH% | findstr /C:"%DOTNET_PATH%" >nul
    if %ERRORLEVEL% NEQ 0 (
        set "PATH=%DOTNET_PATH%;%PATH%"
    )
)

REM Check if dotnet is now available
where dotnet >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ========================================
    echo ERROR: .NET SDK not found!
    echo ========================================
    echo.
    echo This workstation needs .NET SDK 8.0 or later installed.
    echo.
    echo Download and install from:
    echo   https://dotnet.microsoft.com/download/dotnet/8.0
    echo.
    echo After installing:
    echo   1. Close and reopen this command prompt
    echo   2. Run this script again
    echo.
    echo Or install via winget:
    echo   winget install Microsoft.DotNet.SDK.8
    echo.
    pause
    exit /b 1
)

REM Get dotnet version and verify SDK is installed
for /f "tokens=*" %%i in ('dotnet --version 2^>nul') do set DOTNET_VERSION=%%i
if "%DOTNET_VERSION%"=="" (
    echo.
    echo ========================================
    echo ERROR: Could not determine .NET SDK version
    echo ========================================
    echo.
    echo dotnet.exe was found but SDK may not be installed.
    echo Please install .NET SDK 8.0 or later from:
    echo   https://dotnet.microsoft.com/download/dotnet/8.0
    echo.
    pause
    exit /b 1
)

REM Verify SDK is actually installed (not just runtime)
dotnet --list-sdks >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ========================================
    echo ERROR: .NET SDK not properly installed
    echo ========================================
    echo.
    echo Found dotnet version %DOTNET_VERSION% but SDK list failed.
    echo Please ensure .NET SDK (not just runtime) is installed.
    echo Download from: https://dotnet.microsoft.com/download/dotnet/8.0
    echo.
    pause
    exit /b 1
)

echo Found .NET SDK version: %DOTNET_VERSION%
echo.

cd src

echo Restoring packages...
dotnet restore
if %ERRORLEVEL% NEQ 0 (
    echo Restore failed!
    pause
    exit /b 1
)

echo.
echo Building application...
dotnet build
if %ERRORLEVEL% NEQ 0 (
    echo Build failed! Check errors above.
    pause
    exit /b 1
)

echo.
echo Launching GUI...
dotnet run

cd ..

:end
endlocal

