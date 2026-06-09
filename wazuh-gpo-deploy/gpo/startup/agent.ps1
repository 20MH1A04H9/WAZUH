# Auto-elevate to Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Start-Process powershell.exe "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# ── Configuration ─────────────────────────
$ServiceName               = "WazuhSvc"
$InstallPath               = "C:\Program Files (x86)\ossec-agent"
$Version                   = "4.14.5"
$WazuhManager              = "aiwazuh.socexperts.space"
$WazuhRegistrationPassword = "Viswa@12345."
$AgentName                 = $env:COMPUTERNAME
$MsiPath                   = "$env:TEMP\wazuh-agent.msi"   # Pre-copied from SYSVOL by BAT launcher
$LogPath                   = "$env:TEMP\wazuh-agent-install.log"



# ── Step 1: Remove existing Wazuh Agent ──
Write-Host "`n[1/4] Removing existing Wazuh Agent (if any)..." -ForegroundColor Yellow

Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue

"wazuh-agent","ossec-agent","wazuh-modulesd","wazuh-logcollector","wazuh-syscheckd","wazuh-remoted" | ForEach-Object {
    Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue
}

$uninstallKeys = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match 'Wazuh|OSSEC|Manage Agent' } |
    ForEach-Object {
        Write-Host "  Uninstalling: $($_.DisplayName)" -ForegroundColor Gray
        Start-Process cmd.exe -ArgumentList "/c $($_.UninstallString) /quiet /norestart" -Wait -ErrorAction SilentlyContinue
    }

if (Test-Path $InstallPath) { Remove-Item $InstallPath -Recurse -Force -ErrorAction SilentlyContinue }

$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($svc) { sc.exe delete $ServiceName | Out-Null }

Write-Host "  Done." -ForegroundColor Green

# ── Step 2: Verify MSI (pre-copied from SYSVOL by BAT) ────────
Write-Host "`n[2/4] Verifying Wazuh Agent MSI..." -ForegroundColor Yellow

if (-not (Test-Path $MsiPath)) {
    Write-Host "ERROR: MSI not found at $MsiPath - not copied from SYSVOL?" -ForegroundColor Red
    exit 1
}
Write-Host "  MSI found: $MsiPath" -ForegroundColor Green
# ── Step 3: Install MSI (with registration password) ──
Write-Host "`n[3/4] Installing Wazuh Agent..." -ForegroundColor Yellow

Start-Process msiexec.exe -ArgumentList @(
    "/i", "`"$MsiPath`"",
    "/qn",
    "/l*v", "`"$LogPath`"",
    "WAZUH_MANAGER=`"$WazuhManager`"",
    "WAZUH_AGENT_NAME=`"$AgentName`"",
    "WAZUH_REGISTRATION_PASSWORD=`"$WazuhRegistrationPassword`"",
    "WAZUH_REGISTRATION_SERVER=`"$WazuhManager`""
) -Wait

$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Host "ERROR: Installation failed. Check log: $LogPath" -ForegroundColor Red
    exit 1
}
Write-Host "  Agent installed successfully." -ForegroundColor Green

# ── Step 4: Clean ossec.conf ──────────────


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

# ── Step 5: Enable SCA + remote commands ──


$internalOptions = "$InstallPath\local_internal_options.conf"
if (-not (Test-Path $internalOptions)) { New-Item $internalOptions -Force | Out-Null }

$lines = (Get-Content $internalOptions -ErrorAction SilentlyContinue) |
    Where-Object { $_ -notmatch '^wazuh_command\.remote_commands=1' -and $_ -notmatch '^sca\.remote_commands=1' }
$lines += 'wazuh_command.remote_commands=1'
$lines += 'sca.remote_commands=1'
Set-Content -Path $internalOptions -Value $lines


# ── Step 6: Start service ─────────────────
Write-Host "`n[4/4] Starting WazuhAgent service..." -ForegroundColor Yellow

Set-Service -Name $ServiceName -StartupType Automatic
Restart-Service -Name $ServiceName -Force
Start-Sleep -Seconds 3

$svc = Get-Service -Name $ServiceName
Write-Host ""
$svc | Select-Object Name, Status, StartType | Format-Table -AutoSize


