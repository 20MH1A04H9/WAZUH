# Deploy-WazuhAR.ps1
# Automates: Python install, PyInstaller, software-remediation.py download,
# exe build, deploy to Wazuh AR bin, restart Wazuh agent.
# Run as Administrator.

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

$PYTHON_URL      = "https://www.python.org/ftp/python/3.12.2/python-3.12.2-amd64.exe"
$PYTHON_INSTALLER= "$env:TEMP\python-3.12.2-amd64.exe"
$PYTHON_BASE     = "$env:LOCALAPPDATA\Programs\Python\Python312"
$PYTHON_EXE      = "$PYTHON_BASE\python.exe"
$PIP_EXE         = "$PYTHON_BASE\Scripts\pip.exe"
$PYINSTALLER_EXE = "$PYTHON_BASE\Scripts\pyinstaller.exe"

$SCRIPT_URL      = "https://raw.githubusercontent.com/20MH1A04H9/WAZUH/2eeab943383ca4980379633e57c814be6207f827/Active%20Response/software-remediation.py"
$WORK_DIR        = "C:\WazuhAR"
$SCRIPT_PATH     = "$WORK_DIR\software-remediation.py"
$DIST_EXE        = "$WORK_DIR\dist\software-remediation.exe"
$AR_BIN_DIR      = "C:\Program Files (x86)\ossec-agent\active-response\bin"

function Write-Step {
    param([string]$msg)
    Write-Host "`n[*] $msg" -ForegroundColor Cyan
}

function Write-OK {
    param([string]$msg)
    Write-Host "[+] $msg" -ForegroundColor Green
}

function Write-Fail {
    param([string]$msg)
    Write-Host "[-] $msg" -ForegroundColor Red
    exit 1
}

# 1. Create working directory
Write-Step "Creating working directory: $WORK_DIR"
if (-not (Test-Path $WORK_DIR)) {
    New-Item -ItemType Directory -Path $WORK_DIR | Out-Null
}
Write-OK "Working directory ready"

# 2. Install Python if not present
Write-Step "Checking Python installation"
if (Test-Path $PYTHON_EXE) {
    Write-OK "Python already installed at $PYTHON_EXE"
} else {
    Write-Step "Downloading Python 3.12.2..."
    try {
        Invoke-WebRequest -Uri $PYTHON_URL -OutFile $PYTHON_INSTALLER -UseBasicParsing
    } catch {
        Write-Fail "Failed to download Python: $_"
    }
    Write-OK "Download complete"

    Write-Step "Installing Python silently..."
    $pyargs = @(
        "/quiet",
        "InstallAllUsers=0",
        "PrependPath=1",
        "Include_test=0",
        "Include_pip=1"
    )
    $proc = Start-Process -FilePath $PYTHON_INSTALLER -ArgumentList $pyargs -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        Write-Fail "Python installer exited with code $($proc.ExitCode)"
    }
    Write-OK "Python installed successfully"

    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("PATH", "User")
}

# 3. Install PyInstaller
Write-Step "Checking PyInstaller"
if (Test-Path $PYINSTALLER_EXE) {
    Write-OK "PyInstaller already installed"
} else {
    Write-Step "Installing PyInstaller via pip..."
    $proc = Start-Process -FilePath $PIP_EXE -ArgumentList "install -U pyinstaller" -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ne 0) {
        Write-Fail "pip install pyinstaller failed with code $($proc.ExitCode)"
    }
    Write-OK "PyInstaller installed"
}

# 4. Download software-remediation.py from GitHub
Write-Step "Downloading software-remediation.py from GitHub"
try {
    Invoke-WebRequest -Uri $SCRIPT_URL -OutFile $SCRIPT_PATH -UseBasicParsing
} catch {
    Write-Fail "Failed to download script: $_"
}
Write-OK "Script downloaded to $SCRIPT_PATH"

# 5. Build executable with PyInstaller
Write-Step "Building software-remediation.exe with PyInstaller"
$proc = Start-Process -FilePath $PYINSTALLER_EXE `
    -ArgumentList "--onefile", $SCRIPT_PATH, "--distpath", "$WORK_DIR\dist", "--workpath", "$WORK_DIR\build", "--specpath", $WORK_DIR `
    -Wait -PassThru -NoNewWindow
if ($proc.ExitCode -ne 0) {
    Write-Fail "PyInstaller build failed with exit code $($proc.ExitCode)"
}
if (-not (Test-Path $DIST_EXE)) {
    Write-Fail "Build succeeded but exe not found at $DIST_EXE"
}
Write-OK "Executable built at $DIST_EXE"

# 6. Deploy to Wazuh AR bin
Write-Step "Deploying to Wazuh Active Response bin directory"
if (-not (Test-Path $AR_BIN_DIR)) {
    Write-Fail "Wazuh AR bin directory not found at $AR_BIN_DIR - is the agent installed?"
}
Copy-Item -Path $DIST_EXE -Destination "$AR_BIN_DIR\software-remediation.exe" -Force
Write-OK "Deployed to $AR_BIN_DIR"

# 7. Restart Wazuh agent
Write-Step "Restarting Wazuh agent"
Restart-Service -Name wazuh -Force
Start-Sleep -Seconds 3
$svc = Get-Service -Name wazuh
if ($svc.Status -ne "Running") {
    Write-Fail "Wazuh agent failed to start. Current status: $($svc.Status)"
}
Write-OK "Wazuh agent restarted successfully - status: $($svc.Status)"

Write-Host "`n[DONE] Deployment complete. software-remediation.exe is active." -ForegroundColor Green
