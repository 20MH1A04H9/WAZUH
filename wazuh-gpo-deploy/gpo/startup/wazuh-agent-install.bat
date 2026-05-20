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
set "PASSWORD=Viswa@34234."
set "ServiceName=WazuhSvc"
set "InstallPath=C:\Program Files (x86)\ossec-agent"
set "InternalOptions=%InstallPath%\local_internal_options.conf"

:: =====================================================
:: STOP OLD WAZUH SERVICE
:: =====================================================
echo Stopping old Wazuh service...

net stop %ServiceName% >nul 2>&1
sc stop %ServiceName% >nul 2>&1

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

echo Installation completed successfully.

:: =====================================================
:: ENABLE REMOTE COMMANDS
:: =====================================================
echo.
:: echo Enabling remote commands...

if not exist "%InternalOptions%" (
    type nul > "%InternalOptions%"
)

findstr /v /c:"wazuh_command.remote_commands=1" "%InternalOptions%" > "%TEMP%\wtmp.txt"
move /y "%TEMP%\wtmp.txt" "%InternalOptions%" >nul

echo wazuh_command.remote_commands=1>> "%InternalOptions%"
echo sca.remote_commands=1>> "%InternalOptions%"

:: echo Remote commands enabled.

:: =====================================================
:: RESTART SERVICE
:: =====================================================
echo.
echo Restarting Wazuh service...

net stop "%ServiceName%" >nul 2>&1
timeout /t 3 >nul
net start "%ServiceName%"

echo.
echo ============================================
echo Wazuh Agent Installed Successfully
echo ============================================

pause
