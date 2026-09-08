# Wazuh Agent Deployment via Microsoft Intune

Deploying the Wazuh Windows agent fleet-wide using Intune, via a PowerShell Platform Script. Documents two approaches attempted (Win32 app vs. Platform Script), the failure modes hit along the way, and the working end state.

## Table of Contents

- [Overview](#overview)
- [Approach 1: Win32 App (abandoned)](#approach-1-win32-app-abandoned)
- [Approach 2: Platform Script (done)](#approach-2-platform-script-working)
- [The Install Script](#the-install-script)
- [Issues Encountered and Fixes](#issues-encountered-and-fixes)
- [Prerequisites Checklist](#prerequisites-checklist)
- [Verification](#verification)

## Overview

Two deployment mechanisms are available in Intune for pushing a silent installer:

| Method | Pros | Cons |
|---|---|---|
| **Win32 app** | Native detection rules, self-healing (reinstalls if removed), supports uninstall lifecycle | More setup (`.intunewin` packaging), MSI detection rules can behave inconsistently across tenants |
| **Platform Script** | Simple, no packaging step, runs once as SYSTEM | No built-in detection/self-healing; script must handle its own idempotency |

This deployment ended up using a **Platform Script**, after the Win32 app approach hit a hard-to-diagnose issue (see below).

## Approach 1: Win32 App (abandoned)

Steps taken:
1. Downloaded the Wazuh agent MSI matching the manager version.
2. Wrote `install.ps1` / `uninstall.ps1` wrapping `msiexec`.
3. Packaged with `IntuneWinAppUtil.exe` into a `.intunewin` file.
4. Created the Win32 app in Intune, with MSI-based detection using the product code (extracted via the `WindowsInstaller.Installer` COM object).
5. Assigned to a pilot device group.

**Why it was abandoned:** after deleting and recreating the app during troubleshooting, a stale enforcement action persisted in the Intune Management Extension's local state on the test device. Even after the app was deleted from the console, the device later executed a queued **uninstall** (`msiexec /x <ProductCode>`) against Wazuh, silently removing a working install with no corresponding entry in the app's own history. This traced back to Win32 app "required install" assignments not being fully retracted when an app is deleted while already targeted at a device — the local device cache and reboot/grace-period ("GRS") state needs to be manually cleared:

```powershell
Stop-Service -Name IntuneManagementExtension -Force
Remove-Item -Path "C:\ProgramData\Microsoft\IntuneManagementExtension\Win32App*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\Program Files (x86)\Microsoft Intune Management Extension\Content\*" -Recurse -Force -ErrorAction SilentlyContinue
Start-Service -Name IntuneManagementExtension
```

Given the added complexity of managing this state, the Platform Script approach was adopted instead.

## Approach 2: Platform Script (working)

**Path:** Intune admin center → **Devices → Scripts and remediations → Platform scripts → + Add → Windows 10 and later**

**Script settings:**

| Setting | Value | Why |
|---|---|---|
| Run this script using the logged-on credentials | **No** | Must run as SYSTEM to install a Windows service |
| Enforce script signature check | **No** | Script isn't code-signed |
| Run script in 64-bit PowerShell Host | **Yes** | Matches OS architecture, avoids WOW64 redirection issues |

**Assignment:** target a small pilot device group first, not "All devices."

## The Install Script

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

    # IMPORTANT: no single quotes around property values. Windows command-line
    # parsing does NOT strip single quotes the way a shell does -- wrapping
    # values in 'single quotes' passes the quote characters through literally
    # into the MSI property, producing an unresolvable hostname like
    # 'aiwazuh.example.com' (quotes included). This was the root cause of
    # every enrollment failure during initial rollout. Use no quoting for
    # simple values, or double quotes only if a value contains spaces.
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

> **Security note:** embedding the registration password directly in the script means it's visible in plaintext to anyone with Intune script-read permissions on the tenant. For production use, read it from a pre-provisioned, ACL-restricted local file instead (`C:\ProgramData\WazuhProvision\reg.key`), or better, avoid password-based enrollment entirely by pre-generating `client.keys` per agent on the manager and deploying those directly.

## Issues Encountered and Fixes

| # | Symptom | Root Cause | Fix |
|---|---|---|---|
| 1 | Win32 app assignment never processed on a test device | Device was Azure AD **Registered** (BYOD-style), not Azure AD **Joined** — `dsregcmd /status` showed `AzureAdJoined: NO` | Use only properly Azure AD Joined / Hybrid Joined devices for System-context Win32 app or script deployment |
| 2 | Detection rule validation showed a red X despite correct MSI product code | Intune console UI quirk / stale validation state | Delete and re-add the detection rule fresh rather than editing in place |
| 3 | `msiexec` missing `.msi` extension in ad-hoc test commands | `Invoke-WebRequest -OutFile` was given a path with no extension | Always explicitly append `.msi` to the output filename |
| 4 | Script exit code always reported success/failure generically | Script didn't capture `msiexec`'s actual `$LASTEXITCODE` | Use `Start-Process -PassThru` and propagate `$proc.ExitCode` |
| 5 | Agent installed then silently disappeared minutes later | Stale Win32 app **uninstall** enforcement action fired from Intune Management Extension's local cache, tied to a previously deleted app | Clear `IntuneManagementExtension` local Win32 app state (service stop, cache folder delete, service restart) before reusing a device for a different deployment method |
| 6 | Agent installed and service ran, but never enrolled — `ERROR: Could not resolve hostname` | **Manager value passed with literal single quotes** (`WAZUH_MANAGER='host'`) — Windows does not strip single quotes on the command line, so they became part of the hostname string | Remove all single quotes from MSI property values in the install script |
| 7 | Hostname resolved correctly, but enrollment still failed: `Unable to connect to enrollment service` | Azure NSG allowed port 1515/1514 inbound, but the manager VM's own OS firewall (`ufw`) had no rule for those ports — both layers must independently allow the traffic | `sudo ufw allow 1515/tcp && sudo ufw allow 1514/tcp && sudo ufw reload` |

## Prerequisites Checklist

Before deploying to a new device or fleet, confirm:

- [ ] Target devices are Azure AD Joined or Hybrid Azure AD Joined (`dsregcmd /status` → `AzureAdJoined: YES`)
- [ ] Agent MSI version matches (or is supported by) the target manager's version
- [ ] Manager's cloud-provider network security group allows inbound 1515/tcp (enrollment) and 1514/tcp (agent traffic)
- [ ] Manager's OS-level firewall (`ufw`/`iptables`/etc.) independently allows the same ports
- [ ] `wazuh-authd` is running and listening (`sudo ss -tulnp | grep 1515`)
- [ ] No MSI property values are wrapped in single quotes in any install script
- [ ] Registration credentials are not hardcoded in a script visible to broad Intune script-read access, for anything beyond a pilot test

## Verification

On a target device, after deployment:

```powershell
# Service should be running
Get-Service -Name WazuhSvc

# Log should show a successful connection, not a hostname/connection error
Get-Content "C:\Program Files (x86)\ossec-agent\ossec.log" -Tail 20
```

On the manager, confirm the new agent appears:

```bash
sudo /var/ossec/bin/agent_control -l
```
