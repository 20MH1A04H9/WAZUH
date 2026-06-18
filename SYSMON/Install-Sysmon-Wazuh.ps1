# ============================================
# Sysmon Installation Script for Wazuh
# ============================================

$ErrorActionPreference = "Stop"

# Check Administrator
$AdminCheck = ([Security.Principal.WindowsPrincipal] `
([Security.Principal.WindowsIdentity]::GetCurrent())
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $AdminCheck) {
    Write-Host "ERROR: Run PowerShell as Administrator" -ForegroundColor Red
    exit
}


# Current User Downloads Folder
$DownloadPath = "$env:USERPROFILE\Downloads"
$SysmonPath = "$DownloadPath\Sysmon"


$SysmonZip = "$SysmonPath\Sysmon.zip"

$SysmonConfig = "$SysmonPath\sysmonconfig.xml"


$SysmonURL = "https://download.sysinternals.com/files/Sysmon.zip"

$ConfigURL = "https://wazuh.com/resources/blog/emulation-of-attack-techniques-and-detection-with-wazuh/sysmonconfig.xml"


Write-Host "====================================="
Write-Host " Sysmon + Wazuh Configuration Setup "
Write-Host "====================================="


# Create folder
if (!(Test-Path $SysmonPath)) {

    Write-Host "Creating Sysmon folder..."

    New-Item `
    -Path $SysmonPath `
    -ItemType Directory | Out-Null
}


Set-Location $SysmonPath


# Remove previous Sysmon if exists
$Existing = Get-Service Sysmon64 -ErrorAction SilentlyContinue

if ($Existing) {

    Write-Host "Old Sysmon detected. Removing..."

    .\Sysmon64.exe -u

    Start-Sleep 5
}



# Download Sysmon
Write-Host "Downloading Sysmon..."

Invoke-WebRequest `
-Uri $SysmonURL `
-OutFile $SysmonZip



# Extract
Write-Host "Extracting Sysmon..."

Expand-Archive `
-Path $SysmonZip `
-DestinationPath $SysmonPath `
-Force



# Download Config
Write-Host "Downloading Wazuh Sysmon config..."

Invoke-WebRequest `
-Uri $ConfigURL `
-OutFile $SysmonConfig



# Install Sysmon
Write-Host "Installing Sysmon..."

Start-Process `
-FilePath ".\Sysmon64.exe" `
-ArgumentList "-accepteula -i `"$SysmonConfig`"" `
-Wait



Start-Sleep -Seconds 5



# Verify service
Write-Host ""
Write-Host "Checking Sysmon Service..."

$Service = Get-Service Sysmon64 -ErrorAction SilentlyContinue


if ($Service -and $Service.Status -eq "Running") {

    Write-Host ""
    Write-Host "====================================="
    Write-Host " Sysmon Installed Successfully "
    Write-Host "=====================================" -ForegroundColor Green

}
else {

    Write-Host ""
    Write-Host "Sysmon Installation Failed" -ForegroundColor Red
    exit 1
}



# Show configuration

Write-Host ""
Write-Host "Current Sysmon Configuration:"
.\Sysmon64.exe -c


Write-Host ""
Write-Host "Installation Location:"
Write-Host $SysmonPath
