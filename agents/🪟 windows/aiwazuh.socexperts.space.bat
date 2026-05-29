@echo off
setlocal EnableDelayedExpansion
 
:: =====================================================
:: AUTO-ELEVATION (MANDATORY)
:: =====================================================
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo Requesting Administrator privileges...
    powershell -Command "Start-Process cmd.exe -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)
 
echo Running as Administrator...
 
:: =====================================================
:: VARIABLES
:: =====================================================
set "ServiceName=WazuhSvc"
set "InstallPath=C:\Program Files (x86)\ossec-agent"
set "Version=4.14.5-1"
set "WazuhManager=aiwazuh.socexperts.space"
set "AgentName=%COMPUTERNAME%"
set "MsiPath=%TEMP%\wazuh-agent.msi"
set "LogPath=%TEMP%\wazuh-agent-install.log"
 
:: =====================================================
:: PART 1: REMOVE EXISTING AGENT
:: =====================================================
echo.
echo === Removing existing Wazuh Agent ===
 
:: Stop service
sc stop %ServiceName% >nul 2>&1
net stop %ServiceName% >nul 2>&1
 
:: Kill processes
taskkill /f /im wazuh-agent.exe >nul 2>&1
taskkill /f /im ossec-agent.exe >nul 2>&1
taskkill /f /im wazuh-modulesd.exe >nul 2>&1
taskkill /f /im wazuh-logcollector.exe >nul 2>&1
taskkill /f /im wazuh-syscheckd.exe >nul 2>&1
taskkill /f /im wazuh-remoted.exe >nul 2>&1
 
:: Uninstall via registry (32-bit and 64-bit)
for /f "tokens=*" %%G in ('powershell -Command "Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'Wazuh|OSSEC|Manage Agent' } | Select-Object -ExpandProperty UninstallString"') do (
    echo Uninstalling: %%G
    cmd /c %%G /quiet /norestart >nul 2>&1
)
 
:: Delete leftover files
if exist "%InstallPath%" (
    rmdir /s /q "%InstallPath%"
)
 
:: Remove stuck service
sc query %ServiceName% >nul 2>&1
if %errorLevel% EQU 0 (
    sc delete %ServiceName% >nul 2>&1
)
 
:: =====================================================
:: PART 2: INSTALL WAZUH AGENT
:: =====================================================
echo.
echo === Installing Wazuh Agent ===
 
powershell -Command "Invoke-WebRequest -Uri 'https://packages.wazuh.com/4.x/windows/wazuh-agent-%Version%-1.msi' -OutFile '%MsiPath%'"
 
if not exist "%MsiPath%" (
    echo ERROR: Failed to download MSI.
    exit /b 1
)
 
msiexec.exe /i "%MsiPath%" /qn /l*v "%LogPath%" WAZUH_MANAGER="%WazuhManager%" WAZUH_AGENT_NAME="%AgentName%"
 
sc query %ServiceName% >nul 2>&1
if %errorLevel% NEQ 0 (
    echo ERROR: Installation failed. Check log: %LogPath%
    exit /b 1
)
 
echo Wazuh agent installed successfully.
 
:: =====================================================
:: PART 3: OSSEC.CONF CLEANUP
:: =====================================================
set "configPath=%InstallPath%\ossec.conf"
 
if exist "%configPath%" (
    :: Backup config
    for /f "tokens=1-3 delims=/ " %%a in ("%date%") do (
        for /f "tokens=1-3 delims=:." %%x in ("%time%") do (
            set "BackupPath=%configPath%.bak.%%c%%a%%b_%%x%%y%%z"
        )
    )
    copy /y "%configPath%" "!BackupPath!" >nul
 
    :: Use PowerShell for regex cleanup (complex patterns not doable in pure BAT)
    powershell -Command ^
        "$cfg = '%configPath%'; ^
        $c = Get-Content $cfg -Raw; ^
        $c = $c -replace '(?s)\s*<!-- Default files to be monitored\. -->', ''; ^
        $c = $c -replace '(?s)\s*<directories.*?</directories>', ''; ^
        $c = $c -replace '(?s)\s*<windows_registry.*?</windows_registry>', ''; ^
        $c = $c -replace '(?s)\s*<registry_ignore.*?</registry_ignore>', ''; ^
        $c = $c -replace '\n{3,}', \"`n`n\"; ^
        Set-Content -Path $cfg -Value $c -NoNewline"
 

)
 
:: =====================================================
:: PART 4: ENABLE SCA + REMOTE COMMANDS
:: =====================================================
set "internalOptions=%InstallPath%\local_internal_options.conf"
 
if not exist "%internalOptions%" (
    type nul > "%internalOptions%"
)
 
:: Strip existing entries then re-add (PowerShell handles this cleanly)
powershell -Command ^
    "$f = '%internalOptions%'; ^
    $lines = (Get-Content $f -ErrorAction SilentlyContinue) | ^
        Where-Object { $_ -notmatch '^wazuh_command\.remote_commands=1' -and $_ -notmatch '^sca\.remote_commands=1' }; ^
    $lines += 'wazuh_command.remote_commands=1'; ^
    $lines += 'sca.remote_commands=1'; ^
    Set-Content -Path $f -Value $lines"
 

 
:: =====================================================
:: PART 5: RESTART AGENT
:: =====================================================
net stop %ServiceName% >nul 2>&1
net start %ServiceName%
sc query %ServiceName%
 
echo.
echo === Wazuh Agent removal + installation completed successfully ===
pause
