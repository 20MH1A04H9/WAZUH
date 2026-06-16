# Wazuh Agent GPO Deployment

Automated Wazuh agent deployment across Windows domain endpoints using Group Policy startup scripts. Handles fresh installs and clean reinstalls — removes existing agent binaries, config, and registry entries before deploying.

---

## Overview

| Item | Value |
|------|-------|
| Agent Version | 4.14.5 |
| Deployment Method | GPO Startup Script |
| Target OS | Windows (Domain-joined) |
| Manager | `<WAZUH_MANAGER_FQDN>` |

---

## Prerequisites

- Windows Server with Active Directory and Group Policy Management
- Wazuh Manager reachable from all target endpoints
- Domain share accessible by `Domain Computers`

---

## Repository Structure

```
.
├── wazuh-agent-4.14.5-1.msi   # Wazuh agent installer
├── install_wazuh.ps1           # GPO startup script
└── README.md
```

---

## Deployment Steps

### 1. Create Deployment Folder on Domain Controller

```
C:\WazuhDeploy\
├── wazuh-agent-4.14.5-1.msi
└── install_wazuh.ps1
```

### 2. Create SMB Share

```powershell
New-SmbShare -Name WazuhDeploy -Path C:\WazuhDeploy -ReadAccess "Domain Computers"
```

Verify:

```powershell
Get-SmbShare
```

### 3. Create WAZUH Organizational Unit

In **Active Directory Users and Computers**, create a new OU named `WAZUH` and move target computer objects into it.

### 4. Create and Link GPO

In **Group Policy Management**:

1. Create a new GPO named `Agent Installation`
2. Link it to the `WAZUH` OU

### 5. Configure Startup Script

Navigate to:

```
Computer Configuration → Policies → Windows Settings → Scripts (Startup/Shutdown) → Startup
```

Click **Show Files**, copy `install_wazuh.ps1` into the Startup Scripts folder, then add it via **Add → Browse**.

### 6. Enable PowerShell Script Execution

```
Computer Configuration → Policies → Administrative Templates
→ Windows Components → Windows PowerShell
→ Turn on Script Execution → Allow all scripts
```

### 7. Enable Network Availability at Startup

```
Computer Configuration → Policies → Administrative Templates
→ System → Logon
→ Always wait for the network at computer startup and logon → Enabled
```

### 8. Apply Policy on Target Endpoint

```cmd
gpupdate /force
```

Then restart:

```powershell
Restart-Computer -ComputerName <TARGET_IP> -Force
```

---

## Verification

### Confirm GPO Applied

```cmd
gpresult /r
```

Expected output includes:

```
Applied Group Policy Objects
    Agent Installation
```

### Check Installation Log

```
C:\Windows\Temp\Wazuh-GPO-Install.log
```

Expected entries:

```
Script Started
Wazuh Agent Installed Successfully
Script Completed Successfully
```

---

## Script Behavior (`install_wazuh.ps1`)

| Scenario | Action |
|----------|--------|
| No agent found | Fresh install |
| Agent service / folder / registry detected | Full removal → clean reinstall |

**Post-install actions performed automatically:**

- Removes `windows_registry` and `registry_ignore` blocks from `ossec.conf`
- Enables remote commands (`wazuh_command.remote_commands=1`)
- Enables SCA remote commands (`sca.remote_commands=1`)
- Sets `WazuhSvc` to Automatic startup and starts the service

---

## Configuration

Edit these variables at the top of `install_wazuh.ps1` before deployment:

```powershell
$MSIPath             = "\\<DC_NAME>\WazuhDeploy\wazuh-agent-4.14.5-1.msi"
$WazuhManager        = "<WAZUH_MANAGER_FQDN>"
$RegistrationPassword = "<REGISTRATION_PASSWORD>"
```

`$AgentName` is set automatically to `$env:COMPUTERNAME`.

---

## Troubleshooting

| Issue | Check |
|-------|-------|
| MSI not found | Verify share permissions for `Domain Computers`; confirm `\\<DC_NAME>\WazuhDeploy` is accessible from endpoint |
| Script not executing | Confirm PowerShell execution policy GPO is applied (`gpresult /r`) |
| Service not starting | Review log for MSI exit code; check `C:\Program Files (x86)\ossec-agent\ossec.log` |
| Agent not registering | Verify manager FQDN resolves from endpoint; check registration password |

---

## License

MIT
