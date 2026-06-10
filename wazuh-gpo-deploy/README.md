# 🛡️ Wazuh Agent GPO Deployment

> Automated **Wazuh Agent v4.14.5** deployment to Windows endpoints via **Active Directory Group Policy Objects (GPO)**. No internet access required on endpoints — the MSI is pre-staged in SYSVOL and pushed silently on each boot.

<p align="center">
  <img src="https://img.shields.io/badge/Wazuh-4.14.5-006DFF?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/Domain-viswa.local-0078D4?style=for-the-badge&logo=windows&logoColor=white"/>
  <img src="https://img.shields.io/badge/GPO-Active_Directory-0078D4?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/Endpoints-200_Machines-brightgreen?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/No_Internet-Required-orange?style=for-the-badge"/>
</p>

---

## Table of Contents

- [Overview](#overview)
- [Environment](#environment)
- [Architecture](#architecture)
- [Files](#files)
- [Prerequisites](#prerequisites)
- [Step 1 — Create GPO](#step-1--create-gpo)
- [Step 2 — Add Startup Script to GPO](#step-2--add-startup-script-to-gpo)
- [Step 3 — Move Computers to Fluent OU](#step-3--move-computers-to-fluent-ou)
- [Step 4 — Enable Firewall Rules on Endpoints](#step-4--enable-firewall-rules-on-endpoints)
- [Step 5 — Deploy](#step-5--deploy)
- [Step 6 — Verify](#step-6--verify)
- [Roll Out to 200 Endpoints](#roll-out-to-200-endpoints)
- [Key Notes](#key-notes)
- [Troubleshooting](#troubleshooting)
- [References](#references)

---

## Overview

This guide automates Wazuh Agent installation across all domain-joined Windows endpoints using a GPO startup script. On each endpoint reboot, the GPO automatically:

1. Copies the MSI and PowerShell script from SYSVOL to `%TEMP%`
2. Removes any existing Wazuh Agent installation
3. Installs the MSI silently with the correct manager configuration
4. Cleans `ossec.conf` and enables SCA + remote commands
5. Starts `WazuhSvc` on auto

The script is **idempotent** — it skips installation if `WazuhSvc` is already running.

---

## Environment

| Parameter | Value |
|---|---|
| **Domain** | `viswa.local` |
| **DC Hostname** | `WIN-IQ934P80NUM.viswa.local` |
| **DC IP** | `<DC_IP>` |
| **Endpoint OU** | `OU=Fluent,DC=viswa,DC=local` |
| **Wazuh Manager** | `<Wazuh_Manager_Hostname>` |
| **Wazuh Version** | `4.14.5` |
| **SYSVOL Scripts Path** | `C:\Windows\SYSVOL\sysvol\viswa.local\scripts` |
| **Install Log** | `C:\wazuh-gpo-install.log` |
| **Target Endpoints** | 200 domain-joined Windows machines |

---

## Architecture

```
AD GPO (Startup Script)
        │
        ▼
wazuh-agent-install.bat      ← runs as SYSTEM on every endpoint boot
        │
        ├── Copies agent.ps1 + wazuh-agent.msi
        │   from SYSVOL → %TEMP%
        │
        └── Executes agent.ps1
                │
                ├── [1/4] Remove existing Wazuh Agent (if any)
                ├── [2/4] Verify MSI exists in %TEMP%
                ├── [3/4] Install MSI silently with manager config
                ├── [4/4] Clean ossec.conf + enable SCA / remote commands
                └── Start WazuhSvc (auto)
                        │
                        ▼
                Wazuh Manager ──► OpenSearch ──► Wazuh Dashboard
```

### GPO Deployment Flow

```
Domain Controller
  │
  ├── SYSVOL\viswa.local\scripts\
  │     ├── wazuh-agent-install.bat    ← GPO Startup Script
  │     ├── agent.ps1                  ← PowerShell install script
  │     └── wazuh-agent-4.14.5-1.msi  ← Agent installer (pre-staged)
  │
  │  GPO: Wazuh-Agent-Deploy
  │  Linked to: OU=Fluent,DC=viswa,DC=local
  │
  ▼
Endpoints in Fluent OU
  └── On reboot → BAT runs as SYSTEM
        └── PS1 installs, configures, starts WazuhSvc
              └── Agent registers → appears Active in Dashboard
```

---

## Files

| File | Purpose |
|---|---|
| `wazuh-agent-install.bat` | GPO startup script — copies files from SYSVOL and launches `agent.ps1` |
| `agent.ps1` | PowerShell install script — removes old agent, installs MSI, configures, starts service |
| `wazuh-agent-4.14.5-1.msi` | Wazuh Agent installer *(stage manually in SYSVOL — not in repo)* |

---

## Prerequisites

### 1. Download Wazuh MSI

Run on the DC (internet access required on DC only):

```powershell
Invoke-WebRequest `
  -Uri "https://packages.wazuh.com/4.x/windows/wazuh-agent-4.14.5-1.msi" `
  -OutFile "C:\Windows\SYSVOL\sysvol\viswa.local\scripts\wazuh-agent-4.14.5-1.msi"
```

### 2. Copy All Scripts to SYSVOL

```cmd
copy wazuh-agent-install.bat "C:\Windows\SYSVOL\sysvol\viswa.local\scripts\"
copy agent.ps1               "C:\Windows\SYSVOL\sysvol\viswa.local\scripts\"
```

### 3. Set SYSVOL Permissions

```cmd
icacls "C:\Windows\SYSVOL\sysvol\viswa.local\scripts" /grant "Domain Computers:(RX)" /T
```

### 4. Verify All Files Are Present

```cmd
dir "C:\Windows\SYSVOL\sysvol\viswa.local\scripts\"
```

Expected output:

```
wazuh-agent-install.bat
agent.ps1
wazuh-agent-4.14.5-1.msi
```

---

## Step 1 — Create GPO

Open Group Policy Management Console on the DC:

```
Win + R → gpmc.msc → Enter
```

```
1. Expand: Forest → Domains → viswa.local
2. Locate: OU=Fluent
3. Right-click Fluent OU → "Create a GPO in this domain and Link it here"
4. Name: Wazuh-Agent-Deploy
5. Click OK
```

---

## Step 2 — Add Startup Script to GPO

```
1. Right-click Wazuh-Agent-Deploy → Edit
2. Navigate to:
   Computer Configuration
     └── Windows Settings
           └── Scripts (Startup/Shutdown)
                 └── Startup
3. Double-click Startup → Click Add
4. Click Browse → navigate to:
   \\viswa.local\SYSVOL\viswa.local\scripts\
5. Select wazuh-agent-install.bat → Open → OK → OK
```

---

## Step 3 — Move Computers to Fluent OU

**Option A — PowerShell on DC:**

```powershell
Move-ADComputer `
  -Identity "COMPUTERNAME" `
  -TargetPath "OU=Fluent,DC=viswa,DC=local"
```

**Option B — GUI:**

```
Open Active Directory Users and Computers
→ Locate the computer account
→ Drag and drop into OU=Fluent
```

---

## Step 4 — Enable Firewall Rules on Endpoints

Run on each endpoint to allow remote management:

```cmd
:: Allow ICMP ping
netsh advfirewall firewall add rule ^
  name="Allow ICMPv4" protocol=icmpv4:8,any dir=in action=allow

:: Enable WinRM
winrm quickconfig

:: Allow WinRM port
netsh advfirewall firewall add rule ^
  name="WinRM" protocol=TCP dir=in localport=5985 action=allow
```

Enable WinRM Trusted Hosts on the **DC**:

```powershell
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
```

---

## Step 5 — Deploy

Force GPO update on the DC:

```cmd
gpupdate /force
```

Reboot the endpoint to trigger the GPO startup script:

```cmd
shutdown /m \\<ENDPOINT_IP> /r /f /t 0
```

---

## Step 6 — Verify

### Check GPO Applied (from DC)

```cmd
gpresult /S <ENDPOINT_IP> /R /SCOPE COMPUTER
```

Look for `Wazuh-Agent-Deploy` under **Applied Group Policy Objects**.

---

### Check Install Log (on endpoint)

```cmd
type C:\wazuh-gpo-install.log
```

Expected output:

```
[DD/MM/YYYY HH:MM:SS] Starting Wazuh Agent GPO deployment on ENDPOINT
[DD/MM/YYYY HH:MM:SS] Copying files from SYSVOL...
[DD/MM/YYYY HH:MM:SS] Files copied successfully
[DD/MM/YYYY HH:MM:SS] Running agent.ps1...
[DD/MM/YYYY HH:MM:SS] Wazuh Agent installed successfully on ENDPOINT
```

---

### Check Wazuh Service (on endpoint)

```cmd
sc query WazuhSvc
```

Expected:

```
SERVICE_NAME: WazuhSvc
        TYPE               : 10  WIN32_OWN_PROCESS
        STATE              : 4  RUNNING
        WIN32_EXIT_CODE    : 0  (0x0)
```

PowerShell alternative:

```powershell
Get-Service WazuhSvc
```

Expected:

```
Status   Name       DisplayName
------   ----       -----------
Running  WazuhSvc   Wazuh
```

---

### Verify Agent in Wazuh Dashboard

```
Log into: https://<Wazuh_Manager_Hostname>
Navigate: Agents → Search by hostname
Expected: Agent status = Active (green)
```

Agent appears as **Active** within 1–2 minutes of boot.

---

## Roll Out to 200 Endpoints

Once verified on the first endpoint, repeat for all 200 machines:

```
For each endpoint:

1. Move computer account to OU=Fluent
2. Enable firewall rules (or push via separate GPO)
3. Reboot the endpoint
4. Verify agent appears Active in Wazuh Dashboard
```

### Bulk Move Computers to Fluent OU

```powershell
$computers = @("PC-01", "PC-02", "PC-03") # Add all 200 names

foreach ($pc in $computers) {
    Move-ADComputer `
      -Identity $pc `
      -TargetPath "OU=Fluent,DC=viswa,DC=local"
    Write-Host "[+] Moved: $pc"
}
```

### Bulk Reboot Endpoints (from DC)

```powershell
$endpoints = @(
    "10.2.1.10",
    "10.2.1.11",
    "10.2.1.12"
    # ... all 200 IPs
)

foreach ($ip in $endpoints) {
    Write-Host "Rebooting $ip..."
    shutdown /m \\$ip /r /f /t 0
    Start-Sleep -Seconds 3
}
```

### Bulk GPO Verification (from DC)

```powershell
$endpoints = @("10.2.1.10", "10.2.1.11", "10.2.1.12")

foreach ($ip in $endpoints) {
    Write-Host "=== $ip ==="
    gpresult /S $ip /R /SCOPE COMPUTER 2>&1 | `
      Select-String "Wazuh-Agent-Deploy"
}
```

### Bulk Agent Status Check via PowerShell Remoting

```powershell
$endpoints = @("10.2.1.10", "10.2.1.11", "10.2.1.12")

foreach ($ip in $endpoints) {
    $status = Invoke-Command -ComputerName $ip -ScriptBlock {
        (Get-Service WazuhSvc).Status
    } -ErrorAction SilentlyContinue
    Write-Host "$ip → WazuhSvc: $status"
}
```

---

## Key Notes

| Note | Detail |
|---|---|
| **Idempotent** | BAT skips install if `WazuhSvc` already exists and is running |
| **SYSVOL path** | Must use DC hostname (`WIN-IQ934P80NUM`) not IP address |
| **GPO runs as SYSTEM** | No elevation issues during actual deployment |
| **ossec.conf** | FIM directories and registry monitoring stripped for clean base config |
| **SCA + remote commands** | Enabled via `local_internal_options.conf` |
| **No internet on endpoints** | MSI is pre-staged in SYSVOL — endpoints never need internet access |
| **Registration** | Agent registers with Wazuh Manager automatically on first start |

---

## Troubleshooting

| Issue | Cause | Fix |
|---|---|---|
| `wazuh-gpo-install.log` not found | BAT not added to GPO startup | Add `wazuh-agent-install.bat` to GPO Startup Scripts (Step 2) |
| `Access is denied` running BAT manually | Standard user — needs elevation | Run CMD as Administrator |
| `Could not resolve hostname` for Manager | No DNS resolution on endpoint | Add entry: `echo <WAZUH_IP> <Manager_Hostname> >> C:\Windows\System32\drivers\etc\hosts` |
| `Auth key not imported` | Agent not registered with Manager | Run: `agent-auth.exe -m <MANAGER> -A <HOSTNAME>` |
| MSI not found in `%TEMP%` | SYSVOL unreachable via IP | Use DC hostname not IP in `SYSVOL_SHARE` path in BAT |
| SYSVOL not accessible | NETLOGON service stopped | Run `net start netlogon` on DC |
| GPO not applied | Computer in wrong OU | Move computer to `OU=Fluent,DC=viswa,DC=local` |
| `WazuhSvc` not created after reboot | PS1 failed silently | Check `%TEMP%\wazuh-agent-install.log` on endpoint |
| Agent shows Disconnected in Dashboard | Manager unreachable | Test port 1514: `Test-NetConnection -ComputerName <MANAGER> -Port 1514` |

### Test Manager Connectivity from Endpoint

```powershell
Test-NetConnection -ComputerName <Wazuh_Manager_Hostname> -Port 1514
```

Expected:

```
TcpTestSucceeded : True
```

---

## References

| Resource | Link |
|---|---|
| 📘 Wazuh Windows Agent Docs | [documentation.wazuh.com/windows-agent](https://documentation.wazuh.com/current/installation-guide/wazuh-agent/wazuh-agent-package-windows.html) |
| 🪟 GPO Startup Scripts | [docs.microsoft.com/gpo-scripts](https://docs.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2012-r2-and-2012/dn581922(v=ws.11)) |
| 🔧 Wazuh Agent Config Reference | [documentation.wazuh.com/ossec-conf](https://documentation.wazuh.com/current/user-manual/reference/ossec-conf/index.html) |
| 🛡️ Wazuh SCA | [documentation.wazuh.com/sca](https://documentation.wazuh.com/current/user-manual/capabilities/sec-config-assessment/index.html) |
