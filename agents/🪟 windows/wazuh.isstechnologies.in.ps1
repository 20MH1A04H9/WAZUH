$IsAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Start-Process powershell.exe `
        -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
        -Verb RunAs
    exit
}

Set-ExecutionPolicy Bypass -Scope Process -Force
Write-Host "Running as Administrator..."


$ServiceName          = "WazuhSvc"
$InstallPath          = "C:\Program Files (x86)\ossec-agent"
$Version              = "4.14.4"                            # <<< UPDATED
$WazuhManager         = "wazuh.isstechnologies.in"
$RegistrationPassword = "Viswa@12345."                      # <<< ADDED
$AgentName            = $env:COMPUTERNAME
$MsiPath              = "$env:TEMP\wazuh-agent.msi"
$LogPath              = "$env:TEMP\wazuh-agent-install.log"


Write-Host "`n=== Removing existing Wazuh Agent ==="

Get-Service -Name $ServiceName -ErrorAction SilentlyContinue | Stop-Service -Force

Get-Process -ErrorAction SilentlyContinue | Where-Object {
    $_.ProcessName -like "*wazuh*" -or $_.ProcessName -like "*ossec*"
} | Stop-Process -Force

$UninstallKeys = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

foreach ($Key in $UninstallKeys) {
    Get-ItemProperty $Key -ErrorAction SilentlyContinue | Where-Object {
        $_.DisplayName -match "Wazuh|OSSEC|Manage Agent"
    } | ForEach-Object {
        Write-Host "Uninstalling $($_.DisplayName)"
        Start-Process "cmd.exe" "/c $($_.UninstallString) /quiet /norestart" -Wait
    }
}

if (Test-Path $InstallPath) {
    Remove-Item $InstallPath -Recurse -Force
}

if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
    sc.exe delete $ServiceName | Out-Null
}


Write-Host "`n=== Installing Wazuh Agent v$Version ==="

Invoke-WebRequest `
    -Uri "https://packages.wazuh.com/4.x/windows/wazuh-agent-$Version-1.msi" `
    -OutFile $MsiPath

Start-Process msiexec.exe `
    -ArgumentList "/i `"$MsiPath`" /q /l*v `"$LogPath`" WAZUH_MANAGER=`"$WazuhManager`" WAZUH_REGISTRATION_PASSWORD=`"$RegistrationPassword`" WAZUH_AGENT_NAME=`"$AgentName`"" `
    -Wait

if (-not (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue)) {
    Write-Error "Installation failed. Check log: $LogPath"
    exit 1
}

Write-Host "Wazuh agent installed successfully"


$configPath = "$InstallPath\ossec.conf"

if (Test-Path $configPath) {

    $backupPath = "$configPath.bak.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item $configPath $backupPath -Force

    $content = Get-Content $configPath -Raw

    $content = $content -replace '(?s)\s*<!-- Default files to be monitored\. -->', ''
    $content = $content -replace '(?s)\s*<directories.*?</directories>', ''
    $content = $content -replace '(?s)\s*<windows_registry.*?</windows_registry>', ''
    $content = $content -replace '(?s)\s*<registry_ignore.*?</registry_ignore>', ''

    $content = $content -replace '\n{3,}', "`n`n"
    Set-Content -Path $configPath -Value $content -NoNewline

    Write-Host "OSSEC configuration cleaned"
}


$internalOptions = "$InstallPath\local_internal_options.conf"

if (-not (Test-Path $internalOptions)) {
    New-Item -Path $internalOptions -ItemType File -Force | Out-Null
}

$lines = Get-Content $internalOptions -ErrorAction SilentlyContinue |
    Where-Object {
        $_ -notmatch '^wazuh_command\.remote_commands=1' -and
        $_ -notmatch '^sca\.remote_commands=1'
    }

$lines += 'wazuh_command.remote_commands=1'
$lines += 'sca.remote_commands=1'

Set-Content -Path $internalOptions -Value $lines
Write-Host "SCA and remote commands enabled"

Restart-Service $ServiceName -Force
Get-Service $ServiceName

