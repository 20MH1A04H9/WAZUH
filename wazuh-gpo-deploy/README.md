# Wazuh Agent Deployment via Active Directory GPO

Automated, enterprise-scale Wazuh agent rollout to Windows endpoints using Group Policy Objects — no manual installs, no per-machine SSH, no agent management overhead.

---

## Overview

This project automates Wazuh agent deployment across a Windows AD environment using GPO startup scripts. Rather than installing agents endpoint-by-endpoint, a single BAT file is distributed via Group Policy and executes at machine startup under SYSTEM context — handling old agent removal, fresh installation, and config hardening in one pass.

**What it does:**
- Removes any existing Wazuh agent cleanly (services, binaries, folders)
- Installs the Wazuh agent silently via MSI
- Replaces the default `ossec.conf` syscheck block to remove registry and FIM noise
- Enforces `local_internal_options.conf` settings for remote command execution
- Targets only managed endpoints via AD Security Group filtering — DC and SIEM servers are never touched

---

## Environment

| Component | Detail |
|---|---|
| Domain Controller OS | Windows Server 2019 |
| AD Roles | AD DS, DNS |
| Wazuh Server | Separate Ubuntu host |
| Target endpoints | Windows workstations in OU `SV` |
| GPO tool | `gpmc.msc` |

---

## Prerequisites

- Domain Admin or equivalent privileges
- Wazuh MSI installer accessible from endpoints (network share or embedded in script)
- GPMC installed on management machine
- WMI and remote management firewall rules open on endpoints (for remote `gpupdate` — optional)

---

## Step-by-Step Deployment

### 1. Create an OU for Managed Endpoints

Open **Active Directory Users and Computers** (`dsa.msc`) and create an OU:

```
SV
```

Move your target endpoints (e.g., `KIRANPC`, `AXUIS-1`) into this OU.

> ⚠️ Do **not** leave endpoints in the default `Computers` container. GPO targeting is messy there and you will hit unexpected scope issues.

---

### 2. Create a Security Group

Create a new **Security Group**:

```
Wazuh-Agents
```

Add only managed client computers as members.

> ⚠️ **Never add:**
> - Domain Controller
> - Wazuh Server
> - Any SIEM/logging infrastructure
>
> If your DC ends up in this group, it **will** reboot during deployment. Ask me how I know.

---

### 3. Create and Link the GPO

Open **Group Policy Management Console** (`gpmc.msc`):

1. Create a new GPO: `Wazuh – Agent Installation`
2. Link it to the `SV` OU

---

### 4. Configure Security Filtering

In the GPO **Scope** tab:

- **Remove:** `Authenticated Users`
- **Add:** `Wazuh-Agents`

This ensures the policy only applies to machines explicitly added to the security group.

---

### 5. Add the Startup Script

Navigate inside the GPO editor:

```
Computer Configuration
  → Policies
    → Windows Settings
      → Scripts (Startup/Shutdown)
        → Startup
```

1. Click **Add → Browse**
2. Copy `wazuh-install.bat` into the scripts folder that opens
3. Select **only the filename** — `wazuh-install.bat`

> ⚠️ Do **not** enter a UNC path like `\\server\share\wazuh-install.bat`. GPO startup scripts must reference the file by name only, relative to the GPO's scripts directory. Using a UNC path is one of the most common reasons the script silently does nothing.

---

### 6. The BAT File

The script runs under `SYSTEM` context at machine startup. It must be self-contained.

```bat
@echo off

:: ─────────────────────────────────────────────
:: STEP 1: Remove existing Wazuh agent
:: ─────────────────────────────────────────────
net stop WazuhSvc >nul 2>&1
sc delete WazuhSvc >nul 2>&1

wmic product where "name like 'Wazuh%%'" call uninstall /nointeractive >nul 2>&1

rd /s /q "C:\Program Files (x86)\ossec-agent" >nul 2>&1
rd /s /q "C:\Program Files\ossec-agent" >nul 2>&1

timeout /t 5 /nobreak >nul

:: ─────────────────────────────────────────────
:: STEP 2: Install new agent silently
:: ─────────────────────────────────────────────
msiexec /i "\\YOUR-SERVER\share\wazuh-agent.msi" /qn WAZUH_MANAGER="YOUR-WAZUH-IP" WAZUH_REGISTRATION_SERVER="YOUR-WAZUH-IP" >nul 2>&1

timeout /t 15 /nobreak >nul

:: ─────────────────────────────────────────────
:: STEP 3: Replace syscheck block in ossec.conf
:: ─────────────────────────────────────────────
set CONF="C:\Program Files (x86)\ossec-agent\ossec.conf"

powershell -Command "$c = Get-Content %CONF% -Raw; $c = $c -replace '(?s)<syscheck>.*?</syscheck>', '<syscheck><disabled>no</disabled><frequency>43200</frequency></syscheck>'; Set-Content %CONF% $c"

:: ─────────────────────────────────────────────
:: STEP 4: Enable remote commands
:: ─────────────────────────────────────────────
set INTCONF="C:\Program Files (x86)\ossec-agent\local_internal_options.conf"
echo wazuh_command.remote_commands=1 >> %INTCONF%
echo sca.remote_commands=1 >> %INTCONF%

:: ─────────────────────────────────────────────
:: STEP 5: Start agent
:: ─────────────────────────────────────────────
net start WazuhSvc >nul 2>&1
```

> ⚠️ **Critical:** All PowerShell called from a BAT file in GPO/SYSTEM context **must be single-line**. Do not use multiline PowerShell with `^` continuation inside quoted strings. CMD, SYSTEM context, and the PowerShell host all parse line continuation differently — what works interactively will silently fail under GPO.

---

### 7. The syscheck Block

The BAT replaces the default syscheck block with a minimal config that disables registry monitoring and default FIM paths:

```xml
<syscheck>
  <disabled>no</disabled>
  <frequency>43200</frequency>
</syscheck>
```

> The reason this does a **full block replacement** rather than regex line deletion: removing specific lines with regex at enterprise scale is unreliable. One malformed match leaves stale config behind. Replacing the entire block is idempotent and predictable.

---

### 8. Force Policy Update (Optional)

If you don't want to wait for the next reboot cycle, push a GPUpdate to all group members from your admin machine:

```powershell
Get-ADGroupMember "Wazuh-Agents" |
Where-Object {
    $_.objectClass -eq "computer" -and
    $_.Name -ne $env:COMPUTERNAME
} |
ForEach-Object {
    Invoke-GPUpdate -Computer $_.Name -Force
}
```

> Requires WMI and remote management firewall rules to be open on target machines. If this fails silently, check firewall — don't assume GPO isn't linked.

---

### 9. Reboot Endpoints

Startup scripts only execute on reboot. Force a restart across all group members:

```powershell
Get-ADGroupMember "Wazuh-Agents" |
Where-Object {
    $_.objectClass -eq "computer" -and
    $_.Name -ne $env:COMPUTERNAME
} |
ForEach-Object {
    Restart-Computer -ComputerName $_.Name -Force
}
```

---

## Verification

### Confirm GPO Applied

On any target endpoint, run:

```cmd
gpresult /r
```

Under **COMPUTER SETTINGS → Applied Group Policy Objects**, you must see:

```
Wazuh – Agent Installation
```

If it's missing, the GPO is either not linked to the correct OU, the machine is not in `Wazuh-Agents`, or the machine hasn't rebooted since the policy was created.

### Confirm Registry Monitoring Removed

```powershell
Select-String -Path "C:\Program Files (x86)\ossec-agent\ossec.conf" -Pattern "windows_registry|directories|registry_ignore"
```

Expected: **no output**. Any match means the syscheck replacement didn't run cleanly.

---

## Troubleshooting

| Symptom | Root Cause | Fix |
|---|---|---|
| GPO not applying | GPO not linked to OU | Link GPO to correct OU in gpmc.msc |
| Startup script does nothing | UNC path used instead of filename | Re-add script using filename only |
| `Invoke-GPUpdate` fails silently | WMI / firewall blocking | Open WMI ports or just reboot endpoints manually |
| Registry monitoring still present | Regex XML cleanup failed | Re-run with full block replacement logic |
| Domain Controller rebooted | DC was in `Wazuh-Agents` group | Audit group membership before deployment |
| Agent installs but doesn't register | Wrong manager IP in MSI args | Verify `WAZUH_MANAGER` and `WAZUH_REGISTRATION_SERVER` values |

---

## Repository Structure

```
.
├── README.md
├── scripts/
│   └── wazuh-install.bat       # GPO startup script

```

---

