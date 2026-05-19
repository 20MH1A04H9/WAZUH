@echo off
setlocal EnableDelayedExpansion

:: =====================================================
:: AUTO ELEVATION
:: =====================================================
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process cmd.exe -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

:: =====================================================
:: VARIABLES
:: =====================================================
set "ServiceName=WazuhSvc"
set "InstallPath=C:\Program Files (x86)\ossec-agent"
set "Version=4.14.4"
set "WazuhManager=wazuh.isstechnologies.in"
set "AgentName=%COMPUTERNAME%"
set "MsiPath=%TEMP%\wazuh-agent.msi"
set "RegistrationPassword=Viswa@31232."
set "LogPath=%TEMP%\wazuh-agent-install.log"
set "ConfigPath=%InstallPath%\ossec.conf"
set "InternalOptions=%InstallPath%\local_internal_options.conf"

echo Running as Administrator...

:: =====================================================
:: REMOVE OLD AGENT
:: =====================================================
echo.
echo Removing old Wazuh agent...

net stop %ServiceName% >nul 2>&1

taskkill /f /im wazuh-agent.exe >nul 2>&1
taskkill /f /im ossec-agent.exe >nul 2>&1
taskkill /f /im wazuh-modulesd.exe >nul 2>&1

for /f "tokens=*" %%G in ('powershell -Command "Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'Wazuh|OSSEC' } | Select-Object -ExpandProperty UninstallString"') do (
    cmd /c %%G /quiet /norestart >nul 2>&1
)

timeout /t 5 >nul

if exist "%InstallPath%" (
    rmdir /s /q "%InstallPath%"
)

sc delete %ServiceName% >nul 2>&1

:: =====================================================
:: DOWNLOAD AGENT
:: =====================================================
echo.
echo Downloading Wazuh agent...

powershell -Command "Invoke-WebRequest -Uri 'https://packages.wazuh.com/4.x/windows/wazuh-agent-%Version%-1.msi' -OutFile '%MsiPath%'"

if not exist "%MsiPath%" (
    echo MSI download failed.
    exit /b 1
)

:: =====================================================
:: INSTALL AGENT
:: =====================================================
echo.
echo Installing Wazuh agent...

msiexec.exe /i "%MsiPath%" /qn /l*v "%LogPath%" WAZUH_MANAGER="%WazuhManager%" WAZUH_AGENT_NAME="%AgentName%" WAZUH_REGISTRATION_PASSWORD="%RegistrationPassword%"

timeout /t 10 >nul

sc query %ServiceName% >nul 2>&1
if %errorlevel% neq 0 (
    echo Installation failed.
    exit /b 1
)

echo Wazuh installed successfully.

:: =====================================================
:: REPLACE ENTIRE SYSCHECK BLOCK
:: =====================================================
echo.
echo Cleaning default syscheck config...

powershell -ExecutionPolicy Bypass -Command "$cfg='%ConfigPath%'; $c=Get-Content $cfg -Raw; $replacement='<syscheck><disabled>no</disabled><frequency>43200</frequency></syscheck>'; $c=[regex]::Replace($c,'(?s)<syscheck>.*?</syscheck>',$replacement); Set-Content -Path $cfg -Value $c"

echo Syscheck cleaned.

:: =====================================================
:: ENABLE REMOTE COMMANDS + SCA
:: =====================================================

echo.
echo Enabling remote commands...

if not exist "%InternalOptions%" (
    type nul > "%InternalOptions%"
)

powershell -ExecutionPolicy Bypass -Command "$f='%InternalOptions%'; $lines=Get-Content $f -ErrorAction SilentlyContinue; $lines=$lines | Where-Object { $_ -notmatch '^wazuh_command\.remote_commands=1' -and $_ -notmatch '^sca\.remote_commands=1' }; $lines += 'wazuh_command.remote_commands=1'; $lines += 'sca.remote_commands=1'; Set-Content -Path $f -Value $lines"

:: =====================================================
:: RESTART SERVICE
:: =====================================================
echo.
echo Restarting Wazuh service...

net stop %ServiceName% >nul 2>&1
net start %ServiceName%

:: =====================================================
:: DONE
:: =====================================================
echo.
echo Wazuh deployment completed successfully.
pause
