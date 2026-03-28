@echo off
:: Zapret2agent Windows — Double-click installer
:: Launches install.ps1 with proper execution policy

echo.
echo  Zapret2agent Windows Installer
echo  ================================
echo.

:: Check if running as admin (needed for skill symlinks)
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo  [!!] Not running as Administrator.
    echo  [!!] Right-click this file and choose "Run as administrator"
    echo.
    pause
    exit /b 1
)

:: Run the PowerShell installer
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*

if %errorLevel% neq 0 (
    echo.
    echo  [!!] Installation failed. See errors above.
    pause
    exit /b 1
)

echo.
pause
