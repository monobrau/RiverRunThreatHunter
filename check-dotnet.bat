@echo off
REM Quick check script to verify .NET SDK installation
echo Checking .NET SDK installation...
echo.

REM Check common installation paths
set "DOTNET_FOUND=0"
if exist "C:\Program Files\dotnet\dotnet.exe" (
    set "DOTNET_PATH=C:\Program Files\dotnet"
    set "DOTNET_FOUND=1"
) else if exist "C:\Program Files (x86)\dotnet\dotnet.exe" (
    set "DOTNET_PATH=C:\Program Files (x86)\dotnet"
    set "DOTNET_FOUND=1"
)

if %DOTNET_FOUND%==1 (
    echo [OK] Found dotnet.exe at: %DOTNET_PATH%
    set "PATH=%DOTNET_PATH%;%PATH%"
) else (
    echo [ERROR] dotnet.exe not found in common installation paths
    echo.
    echo Please install .NET SDK 8.0 from:
    echo   https://dotnet.microsoft.com/download/dotnet/8.0
    echo.
    pause
    exit /b 1
)

REM Check if dotnet is accessible
where dotnet >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [WARNING] dotnet.exe found but not in PATH
    echo Adding to PATH for this session...
    set "PATH=%DOTNET_PATH%;%PATH%"
)

REM Get version
for /f "tokens=*" %%i in ('dotnet --version 2^>nul') do set DOTNET_VERSION=%%i
if "%DOTNET_VERSION%"=="" (
    echo [ERROR] Could not get dotnet version
    pause
    exit /b 1
)

echo [OK] .NET SDK Version: %DOTNET_VERSION%

REM Check SDKs installed
echo.
echo Installed SDKs:
dotnet --list-sdks
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Could not list SDKs - SDK may not be installed
    echo Please install .NET SDK (not just runtime) from:
    echo   https://dotnet.microsoft.com/download/dotnet/8.0
    pause
    exit /b 1
)

echo.
echo [SUCCESS] .NET SDK is properly installed!
echo You can now run run-gui.bat
echo.
pause

