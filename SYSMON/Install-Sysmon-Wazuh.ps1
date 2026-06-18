# Install-Sysmon-Wazuh.ps1
# Run as Administrator

# Check Administrator
$admin = ([Security.Principal.WindowsPrincipal] `
[Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $admin) {
    Write-Host "Please run PowerShell as Administrator" -ForegroundColor Red
    exit
}

Write-Host "Starting Sysmon Installation..." -ForegroundColor Green

# Variables
$DownloadPath = "C:\Users\Administrator\Downloads"
$SysmonFolder = "$DownloadPath\Sysmon"

$SysmonZip = "$SysmonFolder\Sysmon.zip"
$SysmonURL = "https://download.sysinternals.com/files/Sysmon.zip"

$ConfigURL = "https://wazuh.com/resources/blog/emulation-of-attack-techniques-and-detection-with-wazuh/sysmonconfig.xml"
$ConfigFile = "$SysmonFolder\sysmonconfig.xml"


# Create folder
if (!(Test-Path $SysmonFolder)) {
    New-Item -Path $SysmonFolder -ItemType Directory | Out-Null
}


# Download Sysmon
Write-Host "Downloading Sysmon..."

Invoke-WebRequest `
-Uri $SysmonURL `
-OutFile $SysmonZip


# Extract Sysmon
Write-Host "Extracting Sysmon..."

Expand-Archive `
-Path $SysmonZip `
-DestinationPath $SysmonFolder `
-Force


# Download Sysmon Config
Write-Host "Downloading Wazuh Sysmon Config..."

Invoke-WebRequest `
-Uri $ConfigURL `
-OutFile $ConfigFile


# Install Sysmon
Write-Host "Installing Sysmon..."

Set-Location $SysmonFolder

.\Sysmon64.exe -accepteula -i .\sysmonconfig.xml


# Verify Service
Write-Host "Checking Sysmon Service..."

Get-Service Sysmon64


# Show Config
Write-Host "Current Sysmon Configuration:"
.\Sysmon64.exe -c


Write-Host ""
Write-Host "===================================="
Write-Host " Sysmon Installation Completed "
Write-Host "===================================="
