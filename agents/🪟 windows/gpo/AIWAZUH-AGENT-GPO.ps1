# =====================================================================
# WAZUH AGENT GPO STARTUP INSTALL/REINSTALL SCRIPT
# Version: 4.14.5
# Purpose: If an agent exists, fully remove it (binaries, ossec config,
#          registry) and reinstall fresh. If no agent exists, install.
# =====================================================================
 
$ServiceName = "WazuhSvc"
$InstallPath = "C:\Program Files (x86)\ossec-agent"
 
# Change this to your actual shared path
$MSIPath = "\\<HOSTNAME>\WazuhDeploy\wazuh-agent-4.14.5-1.msi"
 
$WazuhManager = "aiwazuh.socexperts.space"
$RegistrationPassword = "Viswa@12345."
$AgentName = $env:COMPUTERNAME
 
$LogFile = "C:\Windows\Temp\Wazuh-GPO-Install.log"
 
function Write-Log {
    param([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "$Timestamp - $Message"
}
 
Write-Log "================ Script Started ================"
 
# ---------------------------------------------------------------------
# Helper: find the MSI uninstall registry entry for Wazuh Agent
# ---------------------------------------------------------------------
function Get-WazuhUninstallInfo {
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($p in $paths) {
        $items = Get-ItemProperty -Path $p -ErrorAction SilentlyContinue |
                 Where-Object { $_.DisplayName -like "Wazuh Agent*" }
        if ($items) { return $items }
    }
    return $null
}
 
# ---------------------------------------------------------------------
# Helper: fully remove an existing Wazuh agent installation
# ---------------------------------------------------------------------
function Remove-WazuhAgent {
 
    Write-Log "Existing Wazuh Agent detected. Starting full removal."
 
    # Stop the service if it is running
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($svc) {
        try {
            Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
            Write-Log "Service stopped."
        } catch {
            Write-Log "WARNING: Could not stop service cleanly: $($_.Exception.Message)"
        }
    }
 
    # Uninstall via MSI using the registered product code
    $uninstallInfo = Get-WazuhUninstallInfo
    if ($uninstallInfo) {
        foreach ($entry in $uninstallInfo) {
            $productCode = $entry.PSChildName
            Write-Log "Uninstalling product code: $productCode"
 
            $uninstallArgs = @(
                "/x"
                "$productCode"
                "/qn"
                "/norestart"
            )
 
            $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList $uninstallArgs -Wait -PassThru
            Write-Log "Uninstall MSI exit code: $($proc.ExitCode)"
        }
    } else {
        Write-Log "No MSI uninstall entry found. Will rely on manual cleanup."
    }
 
    Start-Sleep -Seconds 10
 
    # Remove the service entry if it is still present
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($svc) {
        Write-Log "Service still present after uninstall. Removing service entry."
        sc.exe delete $ServiceName | Out-Null
        Start-Sleep -Seconds 3
    }
 
    # Remove leftover install directory (ossec.conf, client.keys, queue, logs, binaries)
    if (Test-Path $InstallPath) {
        try {
            Remove-Item -Path $InstallPath -Recurse -Force -ErrorAction Stop
            Write-Log "Removed install directory and config: $InstallPath"
        } catch {
            Write-Log "WARNING: Could not fully remove $InstallPath - $($_.Exception.Message)"
        }
    }
 
    # Remove leftover registry hives
    $regPaths = @(
        "HKLM:\SOFTWARE\ossec",
        "HKLM:\SOFTWARE\WOW6432Node\ossec",
        "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
    )
 
    foreach ($reg in $regPaths) {
        if (Test-Path $reg) {
            try {
                Remove-Item -Path $reg -Recurse -Force -ErrorAction Stop
                Write-Log "Removed registry key: $reg"
            } catch {
                Write-Log "WARNING: Could not remove registry key $reg - $($_.Exception.Message)"
            }
        }
    }
 
    Write-Log "Existing Wazuh Agent removed."
}
 
# ---------------------------------------------------------------------
# Detect existing installation (service, folder, or registry entry)
# ---------------------------------------------------------------------
$ExistingService   = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
$ExistingFolder    = Test-Path $InstallPath
$ExistingUninstall = Get-WazuhUninstallInfo
 
if ($ExistingService -or $ExistingFolder -or $ExistingUninstall) {
    Remove-WazuhAgent
} else {
    Write-Log "No existing Wazuh Agent found. Proceeding with fresh install."
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

# Remove Windows Registry FIM monitoring from ossec.conf

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

    Write-Log "WARNING: ossec.conf not found at $ConfigPath. Skipping registry monitoring removal."

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
}
catch {
    Write-Log "ERROR: Failed to start Wazuh service."
    exit 1
}
 
Write-Log "================ Script Completed Successfully ================"
 
exit 0
