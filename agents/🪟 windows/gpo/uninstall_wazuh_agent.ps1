# =====================================================================
# WAZUH AGENT UNINSTALL SCRIPT
# Purpose: Fully remove Wazuh Agent, ossec files, and registry remnants
# =====================================================================

$ServiceName = "WazuhSvc"
$InstallPath = "C:\Program Files (x86)\ossec-agent"
$LogFile     = "C:\Windows\Temp\Wazuh-Uninstall.log"

function Write-Log {
    param([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "$Timestamp - $Message"
}

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

Write-Log "================ Uninstall Script Started ================"

# ---------------------------------------------------------------------
# Check if anything to uninstall
# ---------------------------------------------------------------------
$ExistingService   = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
$ExistingFolder    = Test-Path $InstallPath
$ExistingUninstall = Get-WazuhUninstallInfo

if (-not $ExistingService -and -not $ExistingFolder -and -not $ExistingUninstall) {
    Write-Log "No Wazuh Agent found. Nothing to remove."
    exit 0
}

# ---------------------------------------------------------------------
# Stop the service
# ---------------------------------------------------------------------
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($svc) {
    try {
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        Write-Log "Service stopped."
    } catch {
        Write-Log "WARNING: Could not stop service cleanly: $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------
# Uninstall via MSI product code
# ---------------------------------------------------------------------
$uninstallInfo = Get-WazuhUninstallInfo
if ($uninstallInfo) {
    foreach ($entry in $uninstallInfo) {
        $productCode = $entry.PSChildName
        Write-Log "Uninstalling product code: $productCode"
        $proc = Start-Process -FilePath "msiexec.exe" `
            -ArgumentList "/x", "$productCode", "/qn", "/norestart" `
            -Wait -PassThru
        Write-Log "Uninstall MSI exit code: $($proc.ExitCode)"
    }
} else {
    Write-Log "No MSI uninstall entry found. Relying on manual cleanup."
}

Start-Sleep -Seconds 10

# ---------------------------------------------------------------------
# Remove service entry if still present
# ---------------------------------------------------------------------
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($svc) {
    Write-Log "Service still present. Removing via sc.exe."
    sc.exe delete $ServiceName | Out-Null
    Start-Sleep -Seconds 3
}

# ---------------------------------------------------------------------
# Remove install directory (ossec.conf, client.keys, queue, logs, etc.)
# ---------------------------------------------------------------------
if (Test-Path $InstallPath) {
    try {
        Remove-Item -Path $InstallPath -Recurse -Force -ErrorAction Stop
        Write-Log "Removed install directory: $InstallPath"
    } catch {
        Write-Log "WARNING: Could not fully remove $InstallPath - $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------
# Remove leftover registry keys
# ---------------------------------------------------------------------
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
            Write-Log "WARNING: Could not remove $reg - $($_.Exception.Message)"
        }
    }
}

Write-Log "================ Uninstall Completed ================"
exit 0
