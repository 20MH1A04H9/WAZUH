# =====================================================================
# WAZUH AGENT INSTALL SCRIPT
# Purpose: Install Wazuh Agent only if WazuhSvc is NOT already running.
#          After install: strips registry FIM from ossec.conf,
#          enables Remote Commands and SCA.
# =====================================================================

$ServiceName         = "WazuhSvc"
$InstallPath         = "C:\Program Files (x86)\ossec-agent"
$MSIPath             = "\\<domain_name>\WazuhDeploy\wazuh-agent-4.14.5-1.msi"
$WazuhManager        = "<wazuh_domain_name>"
$RegistrationPassword = "<wazuh_agent_password>"
$AgentName           = $env:COMPUTERNAME
$LogFile             = "C:\Windows\Temp\Wazuh-Install.log"

function Write-Log {
    param([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "$Timestamp - $Message"
}

Write-Log "================ Install Script Started ================"

# ---------------------------------------------------------------------
# Skip if WazuhSvc is already running
# ---------------------------------------------------------------------
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

if ($svc -and $svc.Status -eq "Running") {
    Write-Log "WazuhSvc is already running. Skipping installation."
    exit 0
}

# ---------------------------------------------------------------------
# Verify MSI is accessible
# ---------------------------------------------------------------------
if (!(Test-Path $MSIPath)) {
    Write-Log "ERROR: MSI not found: $MSIPath"
    exit 1
}

# ---------------------------------------------------------------------
# Install Wazuh Agent
# ---------------------------------------------------------------------
$Arguments = @(
    "/i"
    "`"$MSIPath`""
    "/qn"
    "/norestart"
    "WAZUH_MANAGER=$WazuhManager"
    "WAZUH_REGISTRATION_SERVER=$WazuhManager"
    "WAZUH_REGISTRATION_PASSWORD=$RegistrationPassword"
    "WAZUH_AGENT_NAME=$AgentName"
)

Write-Log "Launching MSI installation."

$Process = Start-Process `
    -FilePath "msiexec.exe" `
    -ArgumentList $Arguments `
    -Wait `
    -PassThru

Write-Log "MSI Exit Code: $($Process.ExitCode)"

Start-Sleep -Seconds 15

# ---------------------------------------------------------------------
# Verify installation
# ---------------------------------------------------------------------
$InstalledService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

if (!$InstalledService) {
    Write-Log "ERROR: Wazuh service not found after installation."
    exit 1
}

Write-Log "Wazuh Agent installed successfully."

# ---------------------------------------------------------------------
# Strip Windows Registry FIM monitoring from ossec.conf
# ---------------------------------------------------------------------
$ConfigPath = "$InstallPath\ossec.conf"

if (Test-Path $ConfigPath) {
    try {
        Copy-Item $ConfigPath "$ConfigPath.bak" -Force

        $c = Get-Content $ConfigPath -Raw
        $c = $c -replace '(?s)\s*<!-- Windows registry entries to monitor\. -->', ''
        $c = $c -replace '(?s)\s*<windows_registry.*?</windows_registry>', ''
        $c = $c -replace '(?s)\s*<!-- Windows registry entries to ignore\. -->', ''
        $c = $c -replace '(?s)\s*<registry_ignore.*?</registry_ignore>', ''
        $c = $c -replace '\r?\n{3,}', "`r`n`r`n"

        Set-Content -Path $ConfigPath -Value $c -NoNewline -Encoding UTF8
        Write-Log "Removed windows_registry and registry_ignore blocks from ossec.conf."
    } catch {
        Write-Log "WARNING: Failed to edit ossec.conf - $($_.Exception.Message)"
    }
} else {
    Write-Log "WARNING: ossec.conf not found. Skipping registry monitoring removal."
}

# ---------------------------------------------------------------------
# Enable Remote Commands + SCA
# ---------------------------------------------------------------------
$InternalOptions = "$InstallPath\local_internal_options.conf"

if (!(Test-Path $InternalOptions)) {
    New-Item -Path $InternalOptions -ItemType File -Force | Out-Null
}

$Content = Get-Content $InternalOptions -ErrorAction SilentlyContinue

if ($Content -notcontains "wazuh_command.remote_commands=1") {
    Add-Content $InternalOptions "wazuh_command.remote_commands=1"
}

if ($Content -notcontains "sca.remote_commands=1") {
    Add-Content $InternalOptions "sca.remote_commands=1"
}

Write-Log "Remote Commands and SCA enabled."

# ---------------------------------------------------------------------
# Start Wazuh Service
# ---------------------------------------------------------------------
try {
    Set-Service -Name $ServiceName -StartupType Automatic
    Start-Service -Name $ServiceName
    Start-Sleep -Seconds 5
    $Status = (Get-Service $ServiceName).Status
    Write-Log "Service Status: $Status"
} catch {
    Write-Log "ERROR: Failed to start Wazuh service."
    exit 1
}

Write-Log "================ Install Script Completed Successfully ================"
exit 0
