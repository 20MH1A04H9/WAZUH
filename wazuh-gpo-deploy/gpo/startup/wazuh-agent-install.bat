@echo off
setlocal

:: =====================================================
:: AUTO ELEVATION
:: =====================================================
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Requesting Administrator privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo Running as Administrator...
echo.

:: =====================================================
:: VARIABLES
:: =====================================================
set "MSI=%TEMP%\wazuh-agent-4.14.4-1.msi"
set "MANAGER=wazuh.isstechnologies.in"
set "PASSWORD=Viswa@12345."

:: =====================================================
:: STOP OLD WAZUH SERVICE
:: =====================================================
echo Stopping old Wazuh service...

net stop WazuhSvc >nul 2>&1
sc stop WazuhSvc >nul 2>&1

timeout /t 3 >nul

:: =====================================================
:: DOWNLOAD MSI
:: =====================================================
echo Downloading Wazuh Agent 4.14.4...

powershell -ExecutionPolicy Bypass -Command ^
"Invoke-WebRequest -Uri 'https://packages.wazuh.com/4.x/windows/wazuh-agent-4.14.4-1.msi' -OutFile '%MSI%'"

if not exist "%MSI%" (
    echo.
    echo ERROR: Failed to download MSI.
    pause
    exit /b 1
)

:: =====================================================
:: INSTALL WAZUH AGENT
:: =====================================================
echo.
echo Installing Wazuh Agent...

msiexec.exe /i "%MSI%" /q ^
WAZUH_MANAGER="%MANAGER%" ^
WAZUH_REGISTRATION_PASSWORD="%PASSWORD%"

if %errorLevel% neq 0 (
    echo.
    echo ERROR: Installation failed.
    pause
    exit /b 1
)

:: =====================================================
:: START SERVICE
:: =====================================================
echo.
echo Starting Wazuh service...

net start WazuhSvc

echo.
echo ============================================
echo Wazuh Agent Installed Successfully
echo ============================================

pause
