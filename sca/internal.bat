@echo off
REM ==========================================================
REM Enable Wazuh Remote Commands in local_internal_options.conf
REM ==========================================================

SET CONFIG_FILE="C:\Program Files (x86)\ossec-agent\local_internal_options.conf"

REM Backup original
IF EXIST %CONFIG_FILE% (
    copy %CONFIG_FILE% %CONFIG_FILE%.bak >nul
    echo [INFO] Backup created: %CONFIG_FILE%.bak
)

REM Remove any existing lines (to avoid duplicates / blank lines)
findstr /V /C:"wazuh_command.remote_commands=1" %CONFIG_FILE% > %CONFIG_FILE%.tmp
findstr /V /C:"sca.remote_commands=1" %CONFIG_FILE%.tmp > %CONFIG_FILE%.tmp2
del %CONFIG_FILE%.tmp
move /Y %CONFIG_FILE%.tmp2 %CONFIG_FILE% >nul

REM Add both lines cleanly at the end
>> %CONFIG_FILE% echo wazuh_command.remote_commands=1
>> %CONFIG_FILE% echo sca.remote_commands=1

REM Restart Wazuh Agent
echo [INFO] Restarting Wazuh agent service...
net stop "Wazuh" >nul 2>&1
net start "Wazuh" >nul 2>&1

echo [INFO] Done. Both remote command options enabled without blank lines.
pause
