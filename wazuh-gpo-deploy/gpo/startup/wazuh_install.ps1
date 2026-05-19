# =====================================================
# WAZUH AGENT INSTALL SCRIPT
# =====================================================
Set-ExecutionPolicy Bypass -Scope Process -Force

# =====================================================
# VARIABLES
# =====================================================
$ServiceName          = "WazuhSvc"
$InstallPath          = "C:\Program Files (x86)\ossec-agent"
$Version              = "4.14.4"
$WazuhManager         = "wazuh.isstechnologies.in"
$RegistrationPassword = "Viswa@12345."
$AgentName            = $env:COMPUTERNAME
$MsiPath              = "$env:TEMP\wazuh-agent.msi"
$LogPath              = "$env:TEMP\wazuh-agent-install.log"

# =====================================================
# PART 1: REMOVE EXISTING AGENT
# =====================================================
Write-Host "`n=== Removing existing Wazuh Agent ===" -ForegroundColor Cyan

Get-Service $ServiceName -ErrorAction SilentlyContinue | Stop-Service -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

@("wazuh-agent","ossec-agent","wazuh-modulesd","wazuh-logcollector",
  "wazuh-syscheckd","wazuh-remoted","wazuh-agentd") | ForEach-Object {
    Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue
}

$regKeys = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
Get-ItemProperty $regKeys -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match "Wazuh|OSSEC|Manage Agent" } |
    ForEach-Object {
        Write-Host "Uninstalling: $($_.DisplayName)"
        $u = $_.UninstallString
        if ($u -match "msiexec") {
            $p = $u -replace "/I","/X" -replace "/i","/X"
            Start-Process "msiexec.exe" -ArgumentList "$p /qn /norestart" -Wait
        } else {
            Start-Process "cmd.exe" -ArgumentList "/c $u /quiet /norestart" -Wait
        }
    }

Start-Sleep -Seconds 5

if (Test-Path $InstallPath) {
    Remove-Item $InstallPath -Recurse -Force
    Write-Host "Removed leftover directory."
}

if (Get-Service $ServiceName -ErrorAction SilentlyContinue) {
    sc.exe delete $ServiceName | Out-Null
    Write-Host "Removed stuck service."
}

# =====================================================
# PART 2: DOWNLOAD MSI
# =====================================================
Write-Host "`n=== Downloading Wazuh Agent v$Version ===" -ForegroundColor Cyan

if (Test-Path $MsiPath) { Remove-Item $MsiPath -Force }

Invoke-WebRequest `
    -Uri "https://packages.wazuh.com/4.x/windows/wazuh-agent-$Version-1.msi" `
    -OutFile $MsiPath `
    -UseBasicParsing

if (-not (Test-Path $MsiPath)) {
    Write-Error "Download failed. Check internet connection."
    exit 1
}
Write-Host "Download complete."

# =====================================================
# PART 3: INSTALL MSI
# =====================================================
Write-Host "`n=== Installing Wazuh Agent ===" -ForegroundColor Cyan

$msiArgs = @(
    "/i", "`"$MsiPath`"",
    "/qn",
    "/norestart",
    "/l*v", "`"$LogPath`"",
    "WAZUH_MANAGER=`"$WazuhManager`"",
    "WAZUH_MANAGER_PORT=`"1514`"",
    "WAZUH_REGISTRATION_SERVER=`"$WazuhManager`"",
    "WAZUH_REGISTRATION_PORT=`"1515`"",
    "WAZUH_REGISTRATION_PASSWORD=`"$RegistrationPassword`"",
    "WAZUH_AGENT_NAME=`"$AgentName`""
)

Start-Process "msiexec.exe" -ArgumentList $msiArgs -Wait
Write-Host "Waiting for service registration..."
Start-Sleep -Seconds 15

if (-not (Get-Service $ServiceName -ErrorAction SilentlyContinue)) {
    Write-Error "Installation failed. Check log: $LogPath"
    exit 1
}
Write-Host "Wazuh agent installed successfully."

# =====================================================
# PART 4: PATCH ossec.conf (ensure Manager IP is set)
# =====================================================
Write-Host "`n=== Verifying ossec.conf ===" -ForegroundColor Cyan

$cfg = "$InstallPath\ossec.conf"
if (Test-Path $cfg) {
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    Copy-Item $cfg "$cfg.bak.$ts" -Force

    $c = Get-Content $cfg -Raw

    # Force correct manager address
    if ($c -match "<address>0\.0\.0\.0</address>" -or $c -notmatch [regex]::Escape($WazuhManager)) {
        Write-Host "Patching Manager IP in ossec.conf..."
        $c = $c -replace "<address>.*?</address>", "<address>$WazuhManager</address>"
    }

    # Cleanup unused blocks
    $c = $c -replace "(?s)\s*<!--\s*Default files to be monitored\.\s*-->", ""
    $c = $c -replace "(?s)\s*<directories.*?</directories>", ""
    $c = $c -replace "(?s)\s*<windows_registry.*?</windows_registry>", ""
    $c = $c -replace "(?s)\s*<registry_ignore.*?</registry_ignore>", ""
    $c = $c -replace "\n{3,}", "`n`n"

    Set-Content -Path $cfg -Value $c -NoNewline
    Write-Host "ossec.conf updated."
}

# =====================================================
# PART 5: LOCAL INTERNAL OPTIONS
# =====================================================
Write-Host "`n=== Enabling SCA + remote commands ===" -ForegroundColor Cyan

$intOpt = "$InstallPath\local_internal_options.conf"
if (-not (Test-Path $intOpt)) { New-Item $intOpt -ItemType File -Force | Out-Null }

$lines = (Get-Content $intOpt -ErrorAction SilentlyContinue) |
    Where-Object { $_ -notmatch "^wazuh_command\.remote_commands=1" -and $_ -notmatch "^sca\.remote_commands=1" }
$lines += "wazuh_command.remote_commands=1"
$lines += "sca.remote_commands=1"
Set-Content -Path $intOpt -Value $lines
Write-Host "SCA and remote commands enabled."

# =====================================================
# PART 6: REGISTER AGENT (agent-auth)
# =====================================================
Write-Host "`n=== Registering agent ===" -ForegroundColor Cyan

$agentAuth = "$InstallPath\agent-auth.exe"
if (Test-Path $agentAuth) {
    Start-Process $agentAuth `
        -ArgumentList "-m `"$WazuhManager`" -P `"$RegistrationPassword`" -A `"$AgentName`"" `
        -Wait -NoNewWindow
    Write-Host "Agent registration complete."
} else {
    Write-Host "agent-auth.exe not found, skipping manual registration."
}

# =====================================================
# PART 7: START SERVICE
# =====================================================
Write-Host "`n=== Starting Wazuh Agent service ===" -ForegroundColor Cyan

Stop-Service $ServiceName -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
Start-Service $ServiceName
Start-Sleep -Seconds 5

$svc = Get-Service $ServiceName -ErrorAction SilentlyContinue
if ($svc) {
    Write-Host "Service Status: $($svc.Status)" -ForegroundColor Green
} else {
    Write-Host "WARNING: Service not found after start." -ForegroundColor Yellow
}

Write-Host "`n=== Completed ===" -ForegroundColor Green
Write-Host "Manager : $WazuhManager"
Write-Host "Agent   : $AgentName"
