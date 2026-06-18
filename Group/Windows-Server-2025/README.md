# Windows Audit Policy & Sysmon Setup for Wazuh

This script configures Windows Advanced Audit Policy and installs Sysmon to provide rich telemetry for ingestion by a Wazuh SIEM deployment.

## Prerequisites

- Run PowerShell **as Administrator** (required for `auditpol` and Sysmon installation)
- Wazuh agent already installed and able to reach your Wazuh manager
- `Install-Sysmon-Wazuh.ps1` present in your `Downloads` folder (or update the path below)

> **Note:** If this host is domain-joined, GPO-pushed audit policy can override local `auditpol` settings. For consistency across multiple machines, push these subcategories via **Group Policy → Advanced Audit Policy Configuration** instead of (or in addition to) running this locally.

> Also ensure **"Force audit policy subcategory settings"** is enabled, otherwise the legacy 9-category audit policy can override these subcategory settings:
> ```powershell
> reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v SCENoApplyLegacyAuditPolicy /t REG_DWORD /d 1 /f
> ```

## 1. Allow script execution

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
```

## 2. Install Sysmon

```powershell
cd $env:USERPROFILE\Downloads
.\Install-Sysmon-Wazuh.ps1
```

## 3. Configure Advanced Audit Policy

### System Events
```powershell
auditpol /set /subcategory:"Security System Extension" /success:enable /failure:enable
auditpol /set /subcategory:"System Integrity" /success:enable /failure:enable
auditpol /set /subcategory:"Other System Events" /success:enable /failure:enable
auditpol /set /subcategory:"Security State Change" /success:enable /failure:enable
```

### Logon / Authentication
```powershell
auditpol /set /subcategory:"Logon" /success:enable /failure:enable
auditpol /set /subcategory:"Logoff" /success:enable
auditpol /set /subcategory:"Account Lockout" /success:enable /failure:enable
auditpol /set /subcategory:"Special Logon" /success:enable /failure:enable
auditpol /set /subcategory:"Group Membership" /success:enable /failure:enable
```

### Account Management (AD Users)
```powershell
auditpol /set /subcategory:"User Account Management" /success:enable /failure:enable
auditpol /set /subcategory:"Computer Account Management" /success:enable /failure:enable
auditpol /set /subcategory:"Security Group Management" /success:enable /failure:enable
```

### Kerberos / Domain Authentication
```powershell
auditpol /set /subcategory:"Credential Validation" /success:enable /failure:enable
auditpol /set /subcategory:"Kerberos Authentication Service" /success:enable /failure:enable
auditpol /set /subcategory:"Kerberos Service Ticket Operations" /success:enable /failure:enable
auditpol /set /subcategory:"Other Account Logon Events" /success:enable /failure:enable
```

### Process Monitoring
```powershell
auditpol /set /subcategory:"Process Creation" /success:enable /failure:enable
auditpol /set /subcategory:"Process Termination" /success:enable
```

### Privilege Monitoring
```powershell
auditpol /set /subcategory:"Sensitive Privilege Use" /success:enable /failure:enable
```

### AD Object Monitoring
```powershell
auditpol /set /subcategory:"Directory Service Access" /success:enable /failure:enable
auditpol /set /subcategory:"Directory Service Changes" /success:enable /failure:enable
```

### File / Registry Monitoring
```powershell
auditpol /set /subcategory:"File System" /success:enable /failure:enable
auditpol /set /subcategory:"Registry" /success:enable /failure:enable
```

> ⚠️ Enabling these subcategories only generates events for objects that already have a **SACL** configured. You still need to add auditing entries to the specific files, folders, or registry keys you want monitored (via `Set-Acl` or Group Policy).

### SMB / Share Monitoring
```powershell
auditpol /set /subcategory:"File Share" /success:enable /failure:enable
auditpol /set /subcategory:"Detailed File Share" /success:enable /failure:enable
```

### Policy Change Monitoring
```powershell
auditpol /set /subcategory:"Audit Policy Change" /success:enable /failure:enable
auditpol /set /subcategory:"Authentication Policy Change" /success:enable /failure:enable
auditpol /set /subcategory:"Authorization Policy Change" /success:enable /failure:enable
```

## 4. Verify

```powershell
auditpol /get /category:*
```

## Wazuh Agent Configuration

Enabling these audit policies only generates the Windows Event Log entries — your Wazuh agent's `ossec.conf` still needs `<localfile>` entries to collect them, for example:

```xml
<localfile>
  <location>Microsoft-Windows-Sysmon/Operational</location>
  <log_format>eventchannel</log_format>
</localfile>

<localfile>
  <location>Security</location>
  <log_format>eventchannel</log_format>
</localfile>

<localfile>
  <location>System</location>
  <log_format>eventchannel</log_format>
</localfile>
```

Restart the Wazuh agent after updating `ossec.conf`:

```powershell
Restart-Service -Name WazuhSvc
```
