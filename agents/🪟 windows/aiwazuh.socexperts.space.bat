@echo off
setlocal

:: =====================================================
:: AUTO ELEVATION
:: =====================================================
net session >nul 2>&1
if %errorLevel% neq 0 (
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo Running as Administrator...
echo.

:: =====================================================
:: VARIABLES
:: =====================================================
set "MSI=%TEMP%\wazuh-agent-4.14.5-1.msi"
set "MANAGER=aiwazuh.socexperts.space"
set "SERVICE=WazuhSvc"

:: =====================================================
:: DOWNLOAD MSI
:: =====================================================
echo Downloading Wazuh Agent...

powershell -ExecutionPolicy Bypass -Command ^
"Invoke-WebRequest -Uri 'https://packages.wazuh.com/4.x/windows/wazuh-agent-4.14.5-1.msi' -OutFile '%MSI%'"

if not exist "%MSI%" (
    echo Download failed.
    pause
    exit /b 1
)

:: =====================================================
:: INSTALL AGENT
:: =====================================================
echo Installing Wazuh Agent...

msiexec.exe /i "%MSI%" /q ^
WAZUH_MANAGER="%MANAGER%" ^
WAZUH_AGENT_NAME="%COMPUTERNAME%"

if %errorLevel% neq 0 (
    echo Installation failed.
    pause
    exit /b 1
)

timeout /t 10 >nul

:: =====================================================
:: FORCE AGENT REGISTRATION
:: =====================================================
echo Registering agent...

"C:\Program Files (x86)\ossec-agent\agent-auth.exe" ^
-m %MANAGER% ^
-A %COMPUTERNAME%

:: =====================================================
:: RESTART SERVICE
:: =====================================================
echo Restarting Wazuh service...

net stop "%SERVICE%" >nul 2>&1
timeout /t 5 >nul
net start "%SERVICE%"

echo.
echo ============================================
echo Wazuh Agent Installed Successfully
echo ============================================

pause
