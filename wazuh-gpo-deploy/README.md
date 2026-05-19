# Wazuh Agent Deployment via Windows GPO

A step-by-step guide for deploying Wazuh agents silently across domain-joined Windows endpoints using Group Policy Object (GPO) and MSI software installation.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Overview](#overview)
- [Step 1 — Prepare the Wazuh Agent MSI](#step-1--prepare-the-wazuh-agent-msi)
- [Step 2 — Host the MSI on a Network Share](#step-2--host-the-msi-on-a-network-share)
- [Step 3 — Create a GPO for Software Installation](#step-3--create-a-gpo-for-software-installation)
- [Step 4 — Configure MSI Transform (Optional)](#step-4--configure-msi-transform-optional)
- [Step 5 — Assign the GPO to Target OUs](#step-5--assign-the-gpo-to-target-ous)
- [Step 6 — Verify Deployment](#step-6--verify-deployment)
- [Troubleshooting](#troubleshooting)
- [Agent Group Assignment](#agent-group-assignment)
- [Uninstallation via GPO](#uninstallation-via-gpo)

---

## Prerequisites

| Requirement | Details |
|---|---|
| Wazuh Manager | Version 4.x, reachable from endpoints |
| Domain Controller | Windows Server 2016 / 2019 / 2022 |
| Network Share | UNC path accessible by all target machines (`SYSTEM` account) |
| Wazuh Agent MSI | Downloaded from the [Wazuh downloads page](https://documentation.wazuh.com/current/installation-guide/wazuh-agent/wazuh-agent-package-windows.html) |
| Permissions | Domain Admin or Group Policy delegation rights |

---

## Overview

GPO-based deployment uses **Computer Configuration → Software Installation** to push the Wazuh agent MSI during machine startup. This approach:

- Requires no manual intervention on endpoints
- Works across all domain-joined Windows machines in target OUs
- Passes Wazuh Manager IP and agent group via MSI properties
- Triggers on the **next reboot** of each target machine

---

## Step 1 — Prepare the Wazuh Agent MSI

Download the Wazuh agent MSI for the appropriate architecture.

```
# 64-bit (recommended)
wazuh-agent-4.x.x-1.msi

# 32-bit (legacy systems)
wazuh-agent-4.x.x-1-i386.msi
```

Key MSI properties used during silent install:

| Property | Description | Example |
|---|---|---|
| `WAZUH_MANAGER` | Wazuh Manager IP or hostname | `192.168.1.10` |
| `WAZUH_AGENT_GROUP` | Agent group(s) to assign | `windows-servers` |
| `WAZUH_AGENT_NAME` | Override agent name (optional) | `%COMPUTERNAME%` |
| `WAZUH_REGISTRATION_SERVER` | Custom registration server (optional) | `192.168.1.10` |

---

## Step 2 — Host the MSI on a Network Share

The GPO Software Installation method requires the MSI to be accessible via a **UNC path** — not a mapped drive letter.

**1. Create a shared folder on a file server or the DC:**

```
\\DC01\NETLOGON\Wazuh\
```

> Using `NETLOGON` is convenient as it is already replicated via SYSVOL and accessible to all domain machines.

**2. Place the MSI in the share:**

```
\\DC01\NETLOGON\Wazuh\wazuh-agent-4.x.x-1.msi
```

**3. Set share permissions:**

| Account | Permission |
|---|---|
| `Domain Computers` | Read |
| `Authenticated Users` | Read |
| `Domain Admins` | Full Control |

> The deployment runs under the `SYSTEM` account context, which authenticates as the machine account. Ensure `Domain Computers` has at minimum Read access.

---

## Step 3 — Create a GPO for Software Installation

**1. Open Group Policy Management Console (GPMC):**

```
gpmc.msc
```

**2. Create a new GPO:**

- Right-click the target OU → **Create a GPO in this domain, and Link it here…**
- Name it: `Wazuh Agent Deployment`

**3. Edit the GPO:**

Navigate to:

```
Computer Configuration
  └── Policies
        └── Software Settings
              └── Software Installation
```

**4. Add the package:**

- Right-click **Software Installation** → **New** → **Package…**
- Browse to the UNC path:
  ```
  \\DC01\NETLOGON\Wazuh\wazuh-agent-4.x.x-1.msi
  ```
- Select deployment method: **Advanced**

**5. Configure deployment options:**

Under the **Deployment** tab:

- Deployment type: `Assigned`
- Install this application at logon: ☑ (applies on next startup)

Under the **Modifications** tab (if using an MST transform — see Step 4):

- Add your `.mst` transform file

---

## Step 4 — Configure MSI Transform (Optional)

To pass Wazuh Manager address and agent group silently, create an **MST transform file** using a tool like [Orca MSI Editor](https://docs.microsoft.com/en-us/windows/win32/msi/orca-exe) (part of the Windows SDK).

**Alternative: Use a GPO Startup Script instead**

If transforms are not available, use a PowerShell startup script as an alternative to pass properties directly:

```
Computer Configuration
  └── Policies
        └── Windows Settings
              └── Scripts (Startup/Shutdown)
                    └── Startup → PowerShell Scripts
```

**Startup Script (`Deploy-WazuhAgent.ps1`):**

```powershell
$MSI     = "\\DC01\NETLOGON\Wazuh\wazuh-agent-4.x.x-1.msi"
$Manager = "192.168.1.10"
$Group   = "windows-servers"
$LogFile = "C:\Windows\Temp\wazuh-install.log"

# Skip if Wazuh service already exists
if (Get-Service -Name "WazuhSvc" -ErrorAction SilentlyContinue) {
    Write-Output "Wazuh agent already installed. Skipping."
    exit 0
}

$Args = @(
    "/i `"$MSI`"",
    "/qn",
    "WAZUH_MANAGER=`"$Manager`"",
    "WAZUH_AGENT_GROUP=`"$Group`"",
    "/l*v `"$LogFile`""
)

Start-Process msiexec.exe -ArgumentList $Args -Wait -NoNewWindow
```

> Using a startup script gives full control over install conditions, logging, and retry logic.

---

## Step 5 — Assign the GPO to Target OUs

**1. Link the GPO** to the OU containing the target computer accounts:

```
gpmc.msc → YourDomain.local → Computers (or custom OU) → Link GPO
```

**2. Set Security Filtering** (optional — restrict to specific computers):

- Remove `Authenticated Users` from Security Filtering
- Add a security group containing only the target computer accounts (e.g., `Wazuh-Targets`)

**3. Force a GP update for immediate testing:**

```cmd
gpupdate /force
```

> The MSI will actually install on the **next reboot** of target machines, not immediately after `gpupdate`.

---

## Step 6 — Verify Deployment

**On target endpoints — check service status:**

```cmd
sc query WazuhSvc
```

Expected output:

```
SERVICE_NAME: WazuhSvc
        TYPE               : 10  WIN32_OWN_PROCESS
        STATE              : 4  RUNNING
```

**Check Wazuh Manager for new agents:**

```bash
# On the Wazuh Manager
/var/ossec/bin/agent_control -l
```

**Check installation log on endpoint:**

```
C:\Windows\Temp\wazuh-install.log
```

**Check Windows Event Log for GP software installation events:**

```
Event Viewer → Applications and Services Logs → Microsoft → Windows → GroupPolicy
```

Look for Event IDs `301` (software install success) or `303` (failure).

---

## Troubleshooting

| Symptom | Likely Cause | Resolution |
|---|---|---|
| Agent not installed after reboot | UNC path inaccessible | Verify `Domain Computers` has Read on the share |
| `WazuhSvc` not found | MSI install failed silently | Check `C:\Windows\Temp\wazuh-install.log` |
| Agent appears in manager but shows disconnected | Firewall blocking port 1514/1515 | Open TCP 1514 (agent comms) and TCP 1515 (registration) outbound |
| Agent registered but wrong group | Group property not applied | Verify `WAZUH_AGENT_GROUP` in script/transform |
| GPO not applying | Security filtering mismatch | Run `gpresult /r` on endpoint to confirm GPO is applied |

**Run GP diagnostic on endpoint:**

```cmd
gpresult /h C:\gpreport.html /f
```

Open `C:\gpreport.html` in a browser to inspect applied policies and software installations.

---

## Agent Group Assignment

To assign agents to groups post-deployment from the Wazuh Manager:

```bash
# Assign a specific agent to a group
/var/ossec/bin/agent_groups -a -i <AGENT_ID> -g <GROUP_NAME>

# Verify group assignment
/var/ossec/bin/agent_groups -l -i <AGENT_ID>
```

To assign via the Wazuh Dashboard:

1. Navigate to **Agents** → select agent → **Edit Groups**
2. Add or change the group assignment

---

## Uninstallation via GPO

To remove the Wazuh agent via GPO:

1. Open the GPO containing the software installation
2. Right-click the Wazuh package → **All Tasks** → **Remove**
3. Select: **Immediately uninstall the software from users and computers**

This will trigger uninstallation on the next reboot of all machines where the GPO applies.

---

## References

- [Wazuh Agent Installation on Windows](https://documentation.wazuh.com/current/installation-guide/wazuh-agent/wazuh-agent-package-windows.html)
- [Wazuh Agent Enrollment](https://documentation.wazuh.com/current/user-manual/agent/agent-enrollment/index.html)
- [Microsoft — Deploy Software Using GPO](https://learn.microsoft.com/en-us/troubleshoot/windows-server/group-policy/use-group-policy-to-install-software)
- [Orca MSI Editor (Windows SDK)](https://docs.microsoft.com/en-us/windows/win32/msi/orca-exe)

---

*Maintained by the Security Operations team. Update the MSI path and version string when upgrading Wazuh agents.*
