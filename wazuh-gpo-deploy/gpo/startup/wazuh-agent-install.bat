@echo off
setlocal EnableDelayedExpansion

:: =====================================================
:: AUTO-ELEVATION (MANDATORY)
:: =====================================================
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process cmd.exe -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

echo Running as Administrator...

:: =====================================================
:: VARIABLES
:: =====================================================
set "ServiceName=WazuhSvc"
set "InstallPath=C:\Program Files (x86)\ossec-agent"
set "Version=4.14.4"
set "WazuhManager=wazuh.isstechnologies.in"
set "RegistrationPassword=Viswa@12345."
set "AgentName=%COMPUTERNAME%"
set "MsiPath=%TEMP%\wazuh-agent.msi"
set "LogPath=%TEMP%\wazuh-agent-install.log"

:: =====================================================
:: PART 1: REMOVE EXISTING AGENT
:: =====================================================
echo.
echo === Removing existing Wazuh Agent ===

:: Stop service
sc query "%ServiceName%" >nul 2>&1
if %errorlevel% equ 0 (
    net stop "%ServiceName%" /y >nul 2>&1
    sc stop "%ServiceName%" >nul 2>&1
)

:: Kill processes
taskkill /F /IM wazuh-agent.exe >nul 2>&1
taskkill /F /IM ossec-agent.exe >nul 2>&1
taskkill /F /IM wazuh-modulesd.exe >nul 2>&1
taskkill /F /IM wazuh-logcollector.exe >nul 2>&1
taskkill /F /IM wazuh-syscheckd.exe >nul 2>&1
taskkill /F /IM wazuh-agentd.exe >nul 2>&1

:: Uninstall via registry (32-bit)
for /f "tokens=*" %%A in ('reg query "HKLM\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" /s /f "Wazuh" /k 2^>nul ^| findstr "HKEY"') do (
    for /f "tokens=2*" %%B in ('reg query "%%A" /v UninstallString 2^>nul ^| findstr "UninstallString"') do (
        echo Uninstalling: %%C
        %%C /quiet /norestart >nul 2>&1
    )
)

:: Uninstall via registry (64-bit)
for /f "tokens=*" %%A in ('reg query "HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall" /s /f "Wazuh" /k 2^>nul ^| findstr "HKEY"') do (
    for /f "tokens=2*" %%B in ('reg query "%%A" /v UninstallString 2^>nul ^| findstr "UninstallString"') do (
        echo Uninstalling: %%C
        %%C /quiet /norestart >nul 2>&1
    )
)

:: Wait for uninstall to finish
timeout /t 5 /nobreak >nul

:: Delete leftover install directory
if exist "%InstallPath%" (
    rd /s /q "%InstallPath%"
    echo Removed leftover directory: %InstallPath%
)

:: Delete stuck service
sc query "%ServiceName%" >nul 2>&1
if %errorlevel% equ 0 (
    sc delete "%ServiceName%" >nul 2>&1
    echo Removed stuck service: %ServiceName%
)

:: =====================================================
:: PART 2: INSTALL WAZUH AGENT
:: =====================================================
echo.
echo === Installing Wazuh Agent v%Version% ===

powershell -Command "Invoke-WebRequest -Uri 'https://packages.wazuh.com/4.x/windows/wazuh-agent-%Version%-1.msi' -OutFile '%MsiPath%'"

if not exist "%MsiPath%" (
    echo ERROR: Failed to download Wazuh MSI. Check your internet connection.
    exit /b 1
)

msiexec.exe /i "%MsiPath%" /q /l*v "%LogPath%" ^
    WAZUH_MANAGER="%WazuhManager%" ^
    WAZUH_REGISTRATION_PASSWORD="%RegistrationPassword%" ^
    WAZUH_AGENT_NAME="%AgentName%"

:: Verify installation
sc query "%ServiceName%" >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: Installation failed. Check log: %LogPath%
    exit /b 1
)

echo Wazuh agent installed successfully.

:: =====================================================
:: PART 3: OSSEC.CONF CLEANUP
:: =====================================================
set "ConfigPath=%InstallPath%\ossec.conf"

if exist "%ConfigPath%" (
    echo.
    echo === Cleaning OSSEC configuration ===

    :: Backup config
    for /f "tokens=2 delims==" %%D in ('wmic os get localdatetime /value') do set "dt=%%D"
    set "Timestamp=!dt:~0,8!_!dt:~8,6!"
    copy /y "%ConfigPath%" "%ConfigPath%.bak.!Timestamp!" >nul
    echo Backup created: %ConfigPath%.bak.!Timestamp!

    :: Use PowerShell to do the regex cleanup (batch cannot do multiline regex)
    powershell -Command ^
        "$c = Get-Content '%ConfigPath%' -Raw;" ^
        "$c = $c -replace '(?s)\s*<!--\s*Default files to be monitored\.\s*-->', '';" ^
        "$c = $c -replace '(?s)\s*<directories.*?</directories>', '';" ^
        "$c = $c -replace '(?s)\s*<windows_registry.*?</windows_registry>', '';" ^
        "$c = $c -replace '(?s)\s*<registry_ignore.*?</registry_ignore>', '';" ^
        "$c = $c -replace '\n{3,}', \"`n`n\";" ^
        "Set-Content -Path '%ConfigPath%' -Value $c -NoNewline"

    echo OSSEC configuration cleaned.
)

:: =====================================================
:: PART 4: ENABLE SCA + REMOTE COMMANDS
:: =====================================================
echo.
echo === Enabling SCA and remote commands ===

set "InternalOptions=%InstallPath%\local_internal_options.conf"

if not exist "%InternalOptions%" (
    type nul > "%InternalOptions%"
)

:: Remove existing entries then re-add cleanly via PowerShell
powershell -Command ^
    "$lines = Get-Content '%InternalOptions%' -ErrorAction SilentlyContinue |" ^
    "Where-Object { $_ -notmatch '^wazuh_command\.remote_commands=1' -and $_ -notmatch '^sca\.remote_commands=1' };" ^
    "$lines += 'wazuh_command.remote_commands=1';" ^
    "$lines += 'sca.remote_commands=1';" ^
    "Set-Content -Path '%InternalOptions%' -Value $lines"

echo SCA and remote commands enabled.

:: =====================================================
:: PART 5: RESTART AGENT
:: =====================================================
echo.
echo === Starting Wazuh Agent service ===

net start "%ServiceName%"
sc query "%ServiceName%"

echo.
echo === Wazuh Agent removal + installation completed successfully ===
pause
