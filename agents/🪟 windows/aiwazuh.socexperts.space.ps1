# Auto-elevate
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Start-Process powershell.exe "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$ServiceName   = "WazuhSvc"
$InstallPath   = "C:\Program Files (x86)\ossec-agent"
$Version       = "4.14.2"
$WazuhManager  = "aiwazuh.socexperts.space"
$AgentName     = $env:COMPUTERNAME
$MsiPath       = "$env:TEMP\wazuh-agent.msi"
$LogPath       = "$env:TEMP\wazuh-agent-install.log"

Write-Host "`n=== Removing existing Wazuh Agent ===" -ForegroundColor Cyan

Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
"wazuh-agent","ossec-agent","wazuh-modulesd","wazuh-logcollector","wazuh-syscheckd","wazuh-remoted" | ForEach-Object {
    Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue
}

# Uninstall existing
$uninstallKeys = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match 'Wazuh|OSSEC|Manage Agent' } |
    ForEach-Object {
        Write-Host "Uninstalling: $($_.DisplayName)"
        Start-Process cmd.exe -ArgumentList "/c $($_.UninstallString) /quiet /norestart" -Wait -ErrorAction SilentlyContinue
    }

if (Test-Path $InstallPath) { Remove-Item $InstallPath -Recurse -Force }

$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($svc) { sc.exe delete $ServiceName | Out-Null }

Write-Host "`n=== Downloading Wazuh Agent ===" -ForegroundColor Cyan
Invoke-WebRequest -Uri "https://packages.wazuh.com/4.x/windows/wazuh-agent-$Version-1.msi" -OutFile $MsiPath

if (-not (Test-Path $MsiPath)) {
    Write-Error "ERROR: Failed to download MSI. Exiting."
    exit 1
}

Write-Host "`n=== Installing Wazuh Agent ===" -ForegroundColor Cyan
Start-Process msiexec.exe -ArgumentList "/i `"$MsiPath`" /qn /l*v `"$LogPath`" WAZUH_MANAGER=`"$WazuhManager`" WAZUH_AGENT_NAME=`"$AgentName`"" -Wait

$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Error "ERROR: Installation failed. Check log: $LogPath"
    exit 1
}
Write-Host "Wazuh agent installed successfully." -ForegroundColor Green

# OSSEC.CONF cleanup
$configPath = "$InstallPath\ossec.conf"
if (Test-Path $configPath) {
    Copy-Item $configPath "$configPath.bak" -Force
    $c = Get-Content $configPath -Raw
    $c = $c -replace '(?s)\s*<!-- Default files to be monitored\. -->', ''
    $c = $c -replace '(?s)\s*<directories.*?</directories>', ''
    $c = $c -replace '(?s)\s*<windows_registry.*?</windows_registry>', ''
    $c = $c -replace '(?s)\s*<registry_ignore.*?</registry_ignore>', ''
    $c = $c -replace '\n{3,}', "`n`n"
    Set-Content -Path $configPath -Value $c -NoNewline

}

# Enable SCA + remote commands
$internalOptions = "$InstallPath\local_internal_options.conf"
if (-not (Test-Path $internalOptions)) { New-Item $internalOptions -Force | Out-Null }
$lines = (Get-Content $internalOptions -ErrorAction SilentlyContinue) |
    Where-Object { $_ -notmatch '^wazuh_command\.remote_commands=1' -and $_ -notmatch '^sca\.remote_commands=1' }
$lines += 'wazuh_command.remote_commands=1'
$lines += 'sca.remote_commands=1'
Set-Content -Path $internalOptions -Value $lines


# Restart service
Restart-Service -Name $ServiceName -Force
Get-Service -Name $ServiceName | Select-Object Name, Status | Format-Table -AutoSize

Write-Host "`n=== Wazuh Agent deployment completed successfully ===" -ForegroundColor Green
Read-Host "Press Enter to exit"
