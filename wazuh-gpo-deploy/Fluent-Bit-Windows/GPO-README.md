# 🪟 Fluent Bit GPO Deployment — Wazuh Log Shipping to Loki

> End-to-end guide for deploying **Fluent Bit** across Windows domain endpoints using **Active Directory Group Policy Objects (GPO)**. Ships Wazuh agent logs from all domain-joined machines to a centralized **Loki** instance for analysis in **Grafana** — fully automated, idempotent, zero-touch per endpoint.

<p align="center">
  <img src="https://img.shields.io/badge/Domain-viswa.local-0078D4?style=for-the-badge&logo=windows&logoColor=white"/>
  <img src="https://img.shields.io/badge/Fluent_Bit-3.2.2-49BDA5?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/Loki-Log_Aggregation-F7A600?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/Grafana-Dashboard-F46800?style=for-the-badge&logo=grafana&logoColor=white"/>
  <img src="https://img.shields.io/badge/GPO-Active_Directory-0078D4?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/Endpoints-100_Machines-brightgreen?style=for-the-badge"/>
</p>

---

## Table of Contents

- [Overview](#overview)
- [Environment Details](#environment-details)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Step 1 — Prepare Configuration Files](#step-1--prepare-configuration-files)
- [Step 2 — Create and Link GPO](#step-2--create-and-link-gpo)
- [Step 3 — Prepare Endpoints](#step-3--prepare-endpoints)
- [Step 4 — Deploy and Verify](#step-4--deploy-and-verify)
- [Step 5 — Verify Logs in Grafana](#step-5--verify-logs-in-grafana)
- [Step 6 — Roll Out to All 100 Endpoints](#step-6--roll-out-to-all-100-endpoints)
- [Troubleshooting](#troubleshooting)
- [References](#references)

---

## Overview

This deployment automates Fluent Bit installation across all domain-joined Windows endpoints via GPO startup scripts. Each endpoint:

1. Reads the Wazuh agent log (`ossec.log`) via Fluent Bit's tail plugin
2. Ships logs to a centralized Loki instance over HTTP port 3100
3. Makes logs available in Grafana per hostname via LogQL

The BAT script is **idempotent** — it skips installation if Fluent Bit is already present and always overwrites the config, enabling config updates by simply pushing a new `fluent-bit.conf` to SYSVOL.

---

## Environment Details

| Parameter | Value |
|---|---|
| **Domain** | `viswa.local` |
| **DC Hostname** | `WIN-IQ934P80NUM.viswa.local` |
| **DC IP** | `<DC_IP>` |
| **Endpoint OU** | `OU=Fluent,DC=viswa,DC=local` |
| **Loki Host** | `<Loki_IP>:3100` |
| **Wazuh Log Path** | `C:\Program Files (x86)\ossec-agent\ossec.log` |
| **Fluent Bit Install Dir** | `C:\fluent-bit\` |
| **SYSVOL Scripts Path** | `C:\Windows\SYSVOL\sysvol\viswa.local\scripts` |
| **Fluent Bit Version** | `3.2.2 (win64)` |
| **Target Endpoints** | 100 domain-joined Windows machines |

---

## Architecture

```
Domain Endpoints (100× Windows Servers)
  │
  │  ossec.log (written by Wazuh Agent)
  │
  ▼
Fluent Bit (installed via GPO)
  │  tail plugin → reads ossec.log continuously
  │  Tag: wazuh
  │  Label: job=windows, hostname=${COMPUTERNAME}, service_name=wazuh
  │
  │  HTTP → Port 3100
  ▼
Loki (Centralized Log Aggregation)
  │
  ▼
Grafana (LogQL Dashboards)
  └── Filter by hostname, job, service_name
```

### GPO Deployment Flow

```
Domain Controller (DC)
  │
  ├── SYSVOL\viswa.local\scripts\
  │     ├── fluent-bit-install.bat      ← GPO Startup Script
  │     ├── fluent-bit.conf             ← Fluent Bit config
  │     └── fluent-bit-installer.exe    ← Silent installer binary
  │
  │  GPO: Fluent-Bit-Deploy
  │  Linked to: OU=Fluent,DC=viswa,DC=local
  │
  ▼
Endpoints in Fluent OU
  └── On each reboot → GPO startup script runs automatically
        ├── Install Fluent Bit (if not present)
        ├── Overwrite fluent-bit.conf (always)
        ├── Create/restart fluent-bit service
        └── Log result → C:\fluent-bit\install.log
```

---

## Prerequisites

### Files Required in SYSVOL

Place all 3 files in the SYSVOL scripts folder on the DC before creating the GPO:

| File | Description |
|---|---|
| `fluent-bit-install.bat` | GPO startup script — installs, configures, and starts Fluent Bit |
| `fluent-bit.conf` | Fluent Bit configuration — Wazuh log input + Loki output |
| `fluent-bit-installer.exe` | Fluent Bit v3.2.2 win64 silent installer binary |

### Create SYSVOL Scripts Folder

Run on the **Domain Controller**:

```cmd
mkdir "C:\Windows\SYSVOL\sysvol\viswa.local\scripts"
```

### Set SYSVOL Permissions

Allow domain computers to read the scripts folder:

```cmd
icacls "C:\Windows\SYSVOL\sysvol\viswa.local\scripts" /grant "Domain Computers:(RX)" /T
```

---

## Step 1 — Prepare Configuration Files

### fluent-bit.conf

Save as `C:\Windows\SYSVOL\sysvol\viswa.local\scripts\fluent-bit.conf`:

```ini
[SERVICE]
    Flush           5
    Log_Level       info
    Parsers_File    C:\fluent-bit\conf\parsers.conf

[INPUT]
    Name              tail
    Path              C:\Program Files (x86)\ossec-agent\ossec.log
    Tag               wazuh
    Read_from_Head    true
    Refresh_Interval  5
    Skip_Long_Lines   On
    DB                C:\fluent-bit\conf\wazuh.db

[OUTPUT]
    Name         loki
    Match        wazuh
    Host         <Loki_IP>
    Port         3100
    Labels       job=windows,hostname=${COMPUTERNAME},service_name=wazuh
```

> `Match wazuh` ensures only Wazuh logs are shipped.
> `${COMPUTERNAME}` auto-resolves per endpoint — no manual configuration needed per machine.

---

### fluent-bit-install.bat

Save as `C:\Windows\SYSVOL\sysvol\viswa.local\scripts\fluent-bit-install.bat`:

```batch
@echo off
SET SYSVOL_SHARE=\\WIN-IQ934P80NUM\SYSVOL\viswa.local\scripts
SET INSTALL_DIR=C:\fluent-bit
SET LOG_FILE=C:\fluent-bit\install.log
SET INSTALLER=%SYSVOL_SHARE%\fluent-bit-installer.exe
SET CONF_SRC=%SYSVOL_SHARE%\fluent-bit.conf
SET CONF_DST=%INSTALL_DIR%\conf\fluent-bit.conf

:: Create install directory
if not exist "%INSTALL_DIR%\conf" mkdir "%INSTALL_DIR%\conf"

:: Log start
echo [%DATE% %TIME%] GPO startup script started >> "%LOG_FILE%"

:: Install Fluent Bit only if not already installed
if not exist "%INSTALL_DIR%\fluent-bit.exe" (
    echo [%DATE% %TIME%] Installing Fluent Bit... >> "%LOG_FILE%"
    "%INSTALLER%" /S /D=%INSTALL_DIR%
    echo [%DATE% %TIME%] Install successful >> "%LOG_FILE%"
) else (
    echo [%DATE% %TIME%] Fluent Bit already installed, skipping >> "%LOG_FILE%"
)

:: Always overwrite config (enables config updates via GPO)
copy /Y "%CONF_SRC%" "%CONF_DST%"
echo [%DATE% %TIME%] Config copied successfully >> "%LOG_FILE%"

:: Create or restart Fluent Bit service
sc query fluent-bit >nul 2>&1
if %errorlevel% neq 0 (
    sc create fluent-bit binPath= "\"%INSTALL_DIR%\fluent-bit.exe\" -c \"%CONF_DST%\"" start= auto DisplayName= "Fluent Bit"
    echo [%DATE% %TIME%] Service created >> "%LOG_FILE%"
)

:: Always restart to apply latest config
net stop fluent-bit >nul 2>&1
net start fluent-bit
echo [%DATE% %TIME%] Fluent Bit running successfully on %COMPUTERNAME% >> "%LOG_FILE%"
```

> **Key behaviors:**
> - Skips install if Fluent Bit already present → idempotent
> - Always overwrites `fluent-bit.conf` → push config updates via SYSVOL
> - Restarts service on every boot → always applies latest config
> - All activity logged to `C:\fluent-bit\install.log`

---

## Step 2 — Create and Link GPO

### Open Group Policy Management Console

```
Win + R → gpmc.msc → Enter
```

### Create GPO

```
1. Expand: Forest → Domains → viswa.local
2. Locate: OU=Fluent
3. Right-click Fluent OU → "Create a GPO in this domain and Link it here"
4. Name: Fluent-Bit-Deploy
5. Click OK
```

### Edit GPO — Add Startup Script

```
1. Right-click Fluent-Bit-Deploy → Edit
2. Navigate to:
   Computer Configuration
     └── Windows Settings
           └── Scripts (Startup/Shutdown)
                 └── Startup
3. Double-click Startup → Click Add
4. Click Browse → navigate to:
   \\viswa.local\SYSVOL\viswa.local\scripts\
5. Select fluent-bit-install.bat → Open → OK → OK
```

### Force GPO Update on DC

```cmd
gpupdate /force
```

---

## Step 3 — Prepare Endpoints

### Move Computer Account to Fluent OU

**Option A — AD Users and Computers (GUI):**
```
Open ADUC → locate computer account → drag to OU=Fluent
```

**Option B — PowerShell on DC:**
```powershell
Move-ADComputer `
  -Identity "COMPUTERNAME" `
  -TargetPath "OU=Fluent,DC=viswa,DC=local"
```

### Enable Firewall Rules on Each Endpoint

```cmd
:: Allow ICMP (ping) for connectivity testing
netsh advfirewall firewall add rule ^
  name="Allow ICMPv4" protocol=icmpv4:8,any dir=in action=allow

:: Enable WinRM for remote PowerShell
winrm quickconfig

:: Allow WinRM port
netsh advfirewall firewall add rule ^
  name="WinRM" protocol=TCP dir=in localport=5985 action=allow
```

### Enable WinRM Trusted Hosts on DC

Run on the **DC** to allow remote PowerShell commands to endpoints:

```powershell
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
```

---

## Step 4 — Deploy and Verify

### Reboot Endpoint to Trigger GPO Startup Script

```cmd
:: Remote reboot from DC (replace IP with endpoint IP)
shutdown /m \\<ENDPOINT_IP> /r /f /t 0
```

### Verify GPO Applied

Run on DC after endpoint reboots:

```cmd
gpresult /S <ENDPOINT_IP> /R /SCOPE COMPUTER
```

Look for `Fluent-Bit-Deploy` under **Applied Group Policy Objects**.

### Check Install Log on Endpoint

```cmd
type C:\fluent-bit\install.log
```

Expected output:

```
[DD/MM/YYYY HH:MM:SS] GPO startup script started
[DD/MM/YYYY HH:MM:SS] Install successful
[DD/MM/YYYY HH:MM:SS] Config copied successfully
[DD/MM/YYYY HH:MM:SS] Service created
[DD/MM/YYYY HH:MM:SS] Fluent Bit running successfully on ENDPOINT
```

### Verify Fluent Bit Service

```cmd
sc query fluent-bit
```

Expected output:

```
SERVICE_NAME: fluent-bit
        TYPE               : 10  WIN32_OWN_PROCESS
        STATE              : 4  RUNNING
        WIN32_EXIT_CODE    : 0  (0x0)
        CHECKPOINT         : 0x0
        WAIT_HINT          : 0x0
```

### Verify via PowerShell

```powershell
Get-Service fluent-bit
```

Expected:

```
Status   Name         DisplayName
------   ----         -----------
Running  fluent-bit   Fluent Bit
```

---

## Step 5 — Verify Logs in Grafana

Open Grafana → **Explore** → select **Loki** data source.

### LogQL — Single Endpoint

```logql
{job="windows", service_name="wazuh", hostname="ENDPOINT"}
```

### LogQL — All Endpoints

```logql
{job="windows", service_name="wazuh"}
```

### LogQL — Log Count per Host (Last 5 Minutes)

```logql
count by (hostname) (rate({job="windows", service_name="wazuh"}[5m]))
```

### LogQL — Filter by Log Level

```logql
{job="windows", service_name="wazuh"} |= "ERROR"
{job="windows", service_name="wazuh"} |= "WARNING"
{job="windows", service_name="wazuh"} |= "critical"
```

### LogQL — Wazuh Rule ID Filter

```logql
{job="windows", service_name="wazuh"} | json | rule_id="5710"
```

> All 100 hostnames should appear in the Loki label dropdown once deployed across all endpoints.

---

## Step 6 — Roll Out to All 100 Endpoints

Once verified on the first endpoint, repeat for all remaining machines:

```
For each of the 100 endpoints:

1. Move computer account to OU=Fluent in AD
   Move-ADComputer -Identity "PC-NAME" -TargetPath "OU=Fluent,DC=viswa,DC=local"

2. Enable firewall rules on endpoint
   (or push via separate GPO to the Fluent OU)

3. Reboot the endpoint
   shutdown /m \\<ENDPOINT_IP> /r /f /t 0

4. Verify in Grafana
   {job="windows", service_name="wazuh", hostname="PC-NAME"}
```

### Bulk Reboot via PowerShell (DC)

```powershell
# Define all endpoint IPs
$endpoints = @(
    "10.2.1.10",
    "10.2.1.11",
    "10.2.1.12"
    # ... add all 100 IPs
)

foreach ($ip in $endpoints) {
    Write-Host "Rebooting $ip..."
    shutdown /m \\$ip /r /f /t 0
    Start-Sleep -Seconds 2
}
```

### Bulk GPO Verification via PowerShell (DC)

```powershell
$endpoints = @("10.2.1.10", "10.2.1.11", "10.2.1.12")

foreach ($ip in $endpoints) {
    Write-Host "=== Checking GPO on $ip ==="
    gpresult /S $ip /R /SCOPE COMPUTER 2>&1 | Select-String "Fluent-Bit-Deploy"
}
```

---

## Troubleshooting

| Issue | Cause | Fix |
|---|---|---|
| **SYSVOL not accessible** | Using IP instead of hostname in path | Use hostname (`WIN-IQ934P80NUM`) not IP in `SYSVOL_SHARE` path |
| **Service not created** | Script error or permission issue | Check `C:\fluent-bit\install.log` for error messages |
| **Logs not appearing in Loki** | Wazuh agent not running | Verify: `sc query WazuhSvc` — must be `RUNNING` |
| **GPO not applied** | Computer not in Fluent OU | Run `gpresult /R /SCOPE COMPUTER` on endpoint — check applied GPOs |
| **Script not running on startup** | Computer still in default Computers OU | Move computer account to `OU=Fluent,DC=viswa,DC=local` |
| **WinRM access denied** | User not in Remote Management group | Add admin account to **Remote Management Users** group on endpoint |
| **SYSVOL shares missing** | Netlogon service stopped | Run: `net share SYSVOL` and `net start netlogon` on DC |
| **Config not updating** | Old service using cached config | Restart service: `net stop fluent-bit && net start fluent-bit` |
| **Fluent Bit exits immediately** | Config syntax error | Run manually: `C:\fluent-bit\fluent-bit.exe -c C:\fluent-bit\conf\fluent-bit.conf` |
| **No hostname label in Grafana** | `${COMPUTERNAME}` not resolving | Verify `Labels` line in `fluent-bit.conf` — must use `${COMPUTERNAME}` not `%COMPUTERNAME%` |

### Debug Fluent Bit Manually on Endpoint

```cmd
:: Run interactively to see live errors
"C:\fluent-bit\fluent-bit.exe" -c "C:\fluent-bit\conf\fluent-bit.conf" -vv
```

### Check Loki Connectivity from Endpoint

```powershell
# Test Loki is reachable from endpoint
Test-NetConnection -ComputerName <Loki_IP> -Port 3100
```

Expected:

```
TcpTestSucceeded : True
```

---

## References

| Resource | Link |
|---|---|
| 📘 Fluent Bit Windows Docs | [docs.fluentbit.io/installation/windows](https://docs.fluentbit.io/manual/installation/windows) |
| 🔍 Fluent Bit Loki Output | [docs.fluentbit.io/loki](https://docs.fluentbit.io/manual/pipeline/outputs/loki) |
| 📊 Grafana Loki LogQL | [grafana.com/docs/loki/logql](https://grafana.com/docs/loki/latest/query/) |
| 🪟 GPO Startup Scripts | [docs.microsoft.com/gpo-scripts](https://docs.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2012-r2-and-2012/dn581922(v=ws.11)) |
| 🔧 Active Directory OU Management | [docs.microsoft.com/ad-ou](https://docs.microsoft.com/en-us/windows-server/identity/ad-ds/manage/component-updates/active-directory-domain-services-component-updates) |
