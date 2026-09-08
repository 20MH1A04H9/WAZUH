# 🛡️ Wazuh Agent Deployment via Microsoft Intune

> Deployment guide for pushing the **Wazuh Windows agent** fleet-wide using **Microsoft Intune**, via a PowerShell Platform Script. Covers the working deployment path, the failure modes hit along the way, and the fixes for each.

<p align="center">
  <img src="https://img.shields.io/badge/Windows_10%2F11-0078D4?style=for-the-badge&logo=windows&logoColor=white"/>
  <img src="https://img.shields.io/badge/Wazuh_Agent-4.14.x-006DFF?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/Microsoft_Intune-0078D4?style=for-the-badge&logo=microsoftintune&logoColor=white"/>
  <img src="https://img.shields.io/badge/Deployment-Platform_Script-7A5AF8?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/Status-Working-2EA44F?style=for-the-badge"/>
</p>

---

## Table of Contents

- [Architecture](#architecture)
- [Deployment Methods Compared](#deployment-methods-compared)
- [Method A — Win32 App (abandoned)](#method-a--win32-app-abandoned)
- [Method B — Platform Script (working)](#method-b--platform-script-working)
- [Full Install Script](#full-install-script)
- [Issues Encountered and Fixes](#issues-encountered-and-fixes)
- [Prerequisites Checklist](#prerequisites-checklist)
- [Verification](#verification)
- [References](#references)

---

## Architecture

```
Intune-Managed Windows Endpoint
  │
  ├─── Intune Management Extension
  │       └── Platform Script (PowerShell, runs as SYSTEM)
  │             └── Downloads + silently installs Wazuh Agent MSI
  │                   └── Registers with Wazuh Manager over 1515/tcp
  │                         └── Streams events over 1514/tcp
  │
  └─── Wazuh Manager (cloud VM)
          ├── wazuh-authd    (enrollment, port 1515)
          ├── wazuh-remoted  (agent traffic, port 1514)
          └── wazuh-manager  (core service)
                └── Both cloud NSG *and* OS firewall (ufw) must
                    independently allow 1515/1514 inbound
```

### Rollout Flow Summary

```
INTUNE          →  Platform Script  →  Runs as SYSTEM on assigned devices
INSTALL         →  msiexec /i        →  Silent MSI install + service start
ENROLLMENT      →  wazuh-agent.exe   →  Requests key from manager:1515
STEADY STATE    →  wazuh-agent.exe   →  Streams events to manager:1514
```

---

## Deployment Methods Compared

| Method | Pros | Cons |
|---|---|---|
| **Win32 app** | Native MSI detection, built-in uninstall lifecycle, self-healing (reinstalls if removed) | `.intunewin` packaging step; MSI detection rules behaved inconsistently in this tenant; stale enforcement state persisted after deletion |
| **Platform Script** ✅ | Simple, no packaging, runs once as SYSTEM, easy to iterate on | No native detection/self-healing — script owns its own idempotency and exit-code handling |

This deployment uses **Method B (Platform Script)** after Method A hit a persistent, hard-to-diagnose enforcement bug.

---

## Method A — Win32 App (abandoned)

Steps taken before abandoning this path:

1. Downloaded the Wazuh agent MSI matching the manager version
2. Wrote `install.ps1` / `uninstall.ps1` wrapping `msiexec`
3. Packaged with `IntuneWinAppUtil.exe` into a `.intunewin` file
4. Created the Win32 app with MSI-based detection, using the product code extracted via the `WindowsInstaller.Installer` COM object
5. Assigned to a pilot device group

**Why it was abandoned:** after deleting and recreating the app mid-troubleshooting, a stale enforcement action persisted in the Intune Management Extension's local device cache. Even with the app fully removed from the console, the device later executed a queued **uninstall** (`msiexec /x <ProductCode>`) against a working Wazuh install — with zero corresponding entry in the app's own Intune history. Deleting a Win32 app that was previously targeted at a device does not reliably cancel an already-queued enforcement action.

If revisiting this path, clear local state first:

```powershell
Stop-Service -Name IntuneManagementExtension -Force
Remove-Item -Path "C:\ProgramData\Microsoft\IntuneManagementExtension\Win32App*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\Program Files (x86)\Microsoft Intune Management Extension\Content\*" -Recurse -Force -ErrorAction SilentlyContinue
Start-Service -Name IntuneManagementExtension
```

---

## Method B — Platform Script (working)

**Path:** Intune admin center → **Devices → Scripts and remediations → Platform scripts → + Add → Windows 10 and later**

### Script Settings

| Setting | Value | Why |
|---|---|---|
| Run this script using the logged-on credentials | **No** | Must run as SYSTEM — installs a Windows service |
| Enforce script signature check | **No** | Script is not code-signed |
| Run script in 64-bit PowerShell Host | **Yes** | Matches OS architecture, avoids WOW64 path/registry redirection |

### Assignment

Target a small **pilot device group** first — never "All devices" on the first rollout. Confirm every device in the pilot group is properly **Azure AD Joined** or **Hybrid Azure AD Joined** (see [Issues Encountered](#issues-encountered-and-fixes) — BYOD/Registered-only devices silently never process System-context deployments).

---

## Full Install Script

```powershell
$ErrorActionPreference = "Stop"
$logFile = "C:\ProgramData\WazuhIntuneInstall.log"
Start-Transcript -Path $logFile -Append

try {
    $msiUrl  = "https://packages.wazuh.com/4.x/windows/wazuh-agent-<VERSION>.msi"
    $msiPath = "$env:tmp\wazuh-agent.msi"
    $manager = "<your-wazuh-manager-fqdn>"

    Write-Output "Downloading Wazuh agent from $msiUrl"
    Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath

    # IMPORTANT: no single quotes around property values.
    # Windows command-line parsing does NOT strip single quotes the way a
    # shell does -- wrapping a value in 'single quotes' passes the quote
    # characters through literally into the MSI property, producing an
    # unresolvable hostname like 'aiwazuh.example.com' (quotes included).
    # This was the root cause of every enrollment failure during rollout.
    $msiArgs = @(
        "/i", "`"$msiPath`"",
        "/q",
        "WAZUH_MANAGER=$manager",
        "WAZUH_REGISTRATION_PASSWORD=<your-registration-password>"
    )

    Write-Output "Installing Wazuh agent (manager=$manager)"
    $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -NoNewWindow -PassThru
    $msiExitCode = $proc.ExitCode
    Write-Output "msiexec exited with code $msiExitCode"

    # 0 = success, 3010 = success but reboot required
    if ($msiExitCode -eq 0 -or $msiExitCode -eq 3010) {
        Start-Sleep -Seconds 5
        Write-Output "Starting Wazuh service"
        NET START Wazuh
        Write-Output "Install completed, exit code $msiExitCode"
        Stop-Transcript
        exit $msiExitCode
    }
    else {
        Write-Error "msiexec failed with exit code $msiExitCode"
        Stop-Transcript
        exit $msiExitCode
    }
}
catch {
    Write-Error "Install failed: $_"
    Stop-Transcript
    exit 1
}
```

> ⚠️ **Security note:** embedding the registration password directly in the script means it is visible in plaintext to anyone with Intune script-read permissions on the tenant. Acceptable for a pilot test only. For wider rollout, read the password from a pre-provisioned, ACL-restricted local file (`C:\ProgramData\WazuhProvision\reg.key`, SYSTEM-only read), or avoid password-based enrollment entirely by pre-generating `client.keys` per agent on the manager and deploying those directly.

---

## Issues Encountered and Fixes

| # | Symptom | Root Cause | Fix |
|---|---|---|---|
| 1 | Win32 app assignment never processed on a test device | Device was Azure AD **Registered** (BYOD-style), not Azure AD **Joined** — `dsregcmd /status` showed `AzureAdJoined: NO` | Only use properly Azure AD Joined / Hybrid Joined devices for System-context deployments |
| 2 | Detection rule showed a red X despite a correct MSI product code | Intune console UI validation quirk / stale state | Delete and re-add the detection rule fresh rather than editing in place |
| 3 | `msiexec` couldn't find the downloaded installer | `Invoke-WebRequest -OutFile` given a path with no `.msi` extension | Always explicitly append `.msi` to the output filename |
| 4 | Script reported generic success/failure regardless of what `msiexec` actually did | Script didn't capture `msiexec`'s real exit code | Use `Start-Process -PassThru` and propagate `$proc.ExitCode` |
| 5 | Agent installed, then silently disappeared minutes later | Stale Win32 app **uninstall** enforcement action fired from Intune Management Extension's local cache, tied to a previously deleted app | Clear IME's local Win32 app state (stop service → delete cache → restart service) before reusing a device for a different deployment method |
| 6 | Agent installed and ran, but never enrolled — `ERROR: Could not resolve hostname` | Manager value passed **with literal single quotes** (`WAZUH_MANAGER='host'`) — Windows does not strip single quotes on the command line, so they became part of the hostname string | Remove all single quotes from MSI property values |
| 7 | Hostname resolved correctly, but enrollment still failed — `Unable to connect to enrollment service` | Cloud NSG allowed port 1515/1514 inbound, but the manager VM's own OS firewall (`ufw`) had no rule for those ports — both layers must independently allow the traffic | `sudo ufw allow 1515/tcp && sudo ufw allow 1514/tcp && sudo ufw reload` |

---

## Prerequisites Checklist

- [ ] Target devices are Azure AD Joined or Hybrid Azure AD Joined (`dsregcmd /status` → `AzureAdJoined: YES`)
- [ ] Agent MSI version matches (or is supported by) the target manager's version
- [ ] Cloud NSG allows inbound `1515/tcp` (enrollment) and `1514/tcp` (agent traffic)
- [ ] Manager's OS-level firewall independently allows the same ports
- [ ] `wazuh-authd` is running and listening (`sudo ss -tulnp | grep 1515`)
- [ ] No MSI property values are wrapped in single quotes anywhere in the script
- [ ] Registration credentials are not hardcoded in a script visible to broad Intune script-read access, beyond a pilot test

---

## Verification

**On the endpoint**, after deployment:

```powershell
# Service should be running
Get-Service -Name WazuhSvc

# Log should show a successful connection, not a hostname/connection error
Get-Content "C:\Program Files (x86)\ossec-agent\ossec.log" -Tail 20
```

**On the manager**, confirm the new agent appears:

```bash
sudo /var/ossec/bin/agent_control -l
```

**In Intune**, check the Platform Script's **Device status** blade — should show `Succeeded` for the target device, with no follow-up `msiexec /x` transaction in Windows Event Viewer's Application log shortly after (a sign of the Method A enforcement bug resurfacing).

---

## References

| Resource | Link |
|---|---|
| 📘 Wazuh Windows Agent | [documentation.wazuh.com/windows](https://documentation.wazuh.com/current/installation-guide/wazuh-agent/wazuh-agent-package-windows.html) |
| 🖥️ Intune Platform Scripts | [learn.microsoft.com/mem/intune/apps/intune-management-extension](https://learn.microsoft.com/en-us/mem/intune/apps/intune-management-extension) |
| 📦 Intune Win32 App Management | [learn.microsoft.com/mem/intune/apps/apps-win32-app-management](https://learn.microsoft.com/en-us/mem/intune/apps/apps-win32-app-management) |
| 🔐 Azure AD Join Types | [learn.microsoft.com/entra/identity/devices](https://learn.microsoft.com/en-us/entra/identity/devices/overview) |

<div align="center">

🛡️ **Wazuh Agent Rollout — Intune Platform Script**

</div>
