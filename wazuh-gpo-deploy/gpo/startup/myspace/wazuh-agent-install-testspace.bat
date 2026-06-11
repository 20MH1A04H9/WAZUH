@echo off
:: ============================================================
::  Wazuh Agent - GPO Startup Script
::  Domain  : test.space
::  DC      : WIN-RGKMR97T
::  Wazuh   : 127.0.0.1
::  Purpose : Install Wazuh Agent on domain endpoints
:: ============================================================

SET SYSVOL_SHARE=\\WIN-BOTSCU9I97T\SYSVOL\test.space\scripts
SET LOG_FILE=C:\wazuh-gpo-install.log

echo [%DATE% %TIME%] Starting Wazuh Agent GPO deployment on %COMPUTERNAME% >> "%LOG_FILE%"

:: ------------------------------------------------------------
:: 1. Skip if Wazuh already installed and running
:: ------------------------------------------------------------
sc query WazuhSvc >nul 2>&1
if %errorlevel% == 0 (
    echo [%DATE% %TIME%] WazuhSvc already running, skipping >> "%LOG_FILE%"
    exit /b 0
)

:: ------------------------------------------------------------
:: 2. Copy PS1 and MSI from SYSVOL to local temp
:: ------------------------------------------------------------
echo [%DATE% %TIME%] Copying files from SYSVOL... >> "%LOG_FILE%"

copy /Y "%SYSVOL_SHARE%\agent-testspace.ps1" "%TEMP%\agent.ps1"
if %errorlevel% neq 0 (
    echo [%DATE% %TIME%] ERROR: Failed to copy agent.ps1 >> "%LOG_FILE%"
    exit /b 1
)

copy /Y "%SYSVOL_SHARE%\wazuh-agent-4.14.5-1.msi" "%TEMP%\wazuh-agent.msi"
if %errorlevel% neq 0 (
    echo [%DATE% %TIME%] ERROR: Failed to copy MSI >> "%LOG_FILE%"
    exit /b 1
)

echo [%DATE% %TIME%] Files copied successfully >> "%LOG_FILE%"

:: ------------------------------------------------------------
:: 3. Run PS1 as SYSTEM (GPO context) with execution bypass
:: ------------------------------------------------------------
echo [%DATE% %TIME%] Running agent.ps1... >> "%LOG_FILE%"

powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%TEMP%\agent.ps1"

if %errorlevel% neq 0 (
    echo [%DATE% %TIME%] ERROR: PS1 script failed with code %errorlevel% >> "%LOG_FILE%"
    exit /b 1
)

echo [%DATE% %TIME%] Wazuh Agent installed successfully on %COMPUTERNAME% >> "%LOG_FILE%"
exit /b 0
