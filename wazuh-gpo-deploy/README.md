# Wazuh Agent GPO Deployment

Automated Wazuh Agent v4.14.5 deployment to Windows endpoints via Active Directory Group Policy Objects (GPO). No internet access required on endpoints — MSI is pre-staged in SYSVOL.

---

## Environment

| Parameter | Value |
|-----------|-------|
| Domain | `viswa.local` |
| DC Hostname | `WIN-IQ934P80NUM.viswa.local` |
| DC IP | `10.2.0.121` |
| Endpoint OU | `OU=Wazuh,DC=viswa,DC=local` |
| Wazuh Manager | `aiwazuh.socexperts.space` |
| Wazuh Version | `4.14.5` |
| SYSVOL Scripts Path | `C:\Windows\SYSVOL\sysvol\viswa.local\scripts` |

---

## Architecture

```
AD GPO (Startup Script)
        │
        ▼
wazuh-agent-install.bat   ← runs as SYSTEM on every endpoint boot
        │
        ├── Copies agent.ps1 + wazuh-agent.msi from SYSVOL to %TEMP%
        │
        └── Runs agent.ps1
                │
                ├── [1/4] Removes existing Wazuh Agent (if any)
                ├── [2/4] Verifies MSI exists in %TEMP%
                ├── [3/4] Installs MSI silently with manager config
                ├── [4/4] Cleans ossec.conf + enables SCA/remote commands
                └── Starts WazuhSvc (auto)
```

---

## Files

| File | Purpose |
|------|---------|
| `wazuh-agent-install.bat` | GPO startup script — copies files and launches PS1 |
| `agent.ps1` | PowerShell install script — installs, configures, starts Wazuh agent |
| `wazuh-agent-4.14.5-1.msi` | Wazuh Agent MSI *(not in repo — stage manually in SYSVOL)* |

---

## Prerequisites

### 1. Download Wazuh MSI

Download on the DC (or any machine with internet):

```powershell
Invoke-WebRequest `
  -Uri "https://packages.wazuh.com/4.x/windows/wazuh-agent-4.14.5-1.msi" `
  -OutFile "C:\Windows\SYSVOL\sysvol\viswa.local\scripts\wazuh-agent-4.14.5-1.msi"
```

### 2. Copy All Files to SYSVOL

```cmd
copy wazuh-agent-install.bat "C:\Windows\SYSVOL\sysvol\viswa.local\scripts\"
copy agent.ps1               "C:\Windows\SYSVOL\sysvol\viswa.local\scripts\"
```

### 3. Set SYSVOL Permissions

```cmd
icacls "C:\Windows\SYSVOL\sysvol\viswa.local\scripts" /grant "Domain Computers:(RX)" /T
```

Verify all files are present:

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

Open Group Policy Management Console on DC:

```
Win + R → gpmc.msc
```

1. Expand **Forest → Domains → viswa.local**
2. Right-click **Wazuh** OU → **Create a GPO in this domain and Link it here**
3. Name it: `Wazuh-Agent-Deploy`
4. Click **OK**

---

## Step 2 — Add Startup Script to GPO

1. Right-click `Wazuh-Agent-Deploy` → **Edit**
2. Navigate to:
```
Computer Configuration
  → Windows Settings
    → Scripts (Startup/Shutdown)
      → Startup
```
3. Click **Add** → **Browse**
4. Navigate to `\\viswa.local\SYSVOL\viswa.local\scripts\`
5. Select `wazuh-agent-install.bat` → **Open** → **OK** → **OK**

---

## Step 3 — Move Computers to Wazuh OU

Move each endpoint computer account to the `Wazuh` OU:

```powershell
Move-ADComputer -Identity "COMPUTERNAME" -TargetPath "OU=Wazuh,DC=viswa,DC=local"
```

Or drag and drop in **AD Users and Computers**.

---

## Step 4 — Enable Firewall Rules on Endpoints

Run on each endpoint for remote management access:

```cmd
netsh advfirewall firewall add rule name="Allow ICMPv4" protocol=icmpv4:8,any dir=in action=allow
winrm quickconfig
netsh advfirewall firewall add rule name="WinRM" protocol=TCP dir=in localport=5985 action=allow
```

Enable WinRM trusted hosts on DC:

```powershell
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
```

---

## Step 5 — Deploy

Force GPO update on DC:

```cmd
gpupdate /force
```

Reboot endpoint to trigger startup script:

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

### Check Install Log (on endpoint)

```cmd
type C:\wazuh-gpo-install.log
```

Expected output:
```
[DATE TIME] Starting Wazuh Agent GPO deployment on ENDPOINT
[DATE TIME] Copying files from SYSVOL...
[DATE TIME] Files copied successfully
[DATE TIME] Running agent.ps1...
[DATE TIME] Wazuh Agent installed successfully on ENDPOINT
```
###  Run as Administrator on ENDPOINT:
Right-click CMD → Run as Administrator, then:

```
cmd /c "\\WIN-IQ934P80NUM\SYSVOL\viswa.local\scripts\wazuh-agent-install.bat
```

Or run directly as admin:
``` 
powershell -ExecutionPolicy Bypass -Command "Start-Process cmd -ArgumentList '/c \\WIN-IQ934P80NUM\SYSVOL\viswa.local\scripts\wazuh-agent-install.bat' -Verb RunAs -Wait

```

Note: GPO startup scripts run as SYSTEM automatically — so when deployed via GPO on reboot it will work. The access denied is only because sai is a standard user running it manually.

### Check Service (on endpoint)

```cmd
sc query WazuhSvc
```

Expected: `STATE: 4 RUNNING`

### Verify Agent in Wazuh Dashboard

Log into `https://aiwazuh.socexperts.space` → **Agents** → endpoint should appear as **Active**.

---

## Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| `wazuh-gpo-install.log` not found | BAT script not in GPO startup | Add `wazuh-agent-install.bat` to GPO Startup Scripts |
| `Access is denied` running BAT manually | Standard user — needs admin | Run CMD as Administrator |
| `Could not resolve hostname: aiwazuh.socexperts.space` | No DNS/internet on endpoint | Add hosts file entry: `echo <WAZUH_IP> aiwazuh.socexperts.space >> C:\Windows\System32\drivers\etc\hosts` |
| `Auth key not imported` | Agent not registered yet | Run `agent-auth.exe -m aiwazuh.socexperts.space -P "Viswa@12345." -A <HOSTNAME>` |
| MSI not found in `%TEMP%` | SYSVOL not reachable via IP | Use DC hostname not IP in `SYSVOL_SHARE` path |
| SYSVOL not accessible | SYSVOL/NETLOGON shares missing | Run `net start netlogon` on DC |
| GPO not applied | Computer in wrong OU | Move computer to `OU=Wazuh` in AD |
| WazuhSvc not created after reboot | PS1 failed silently | Check `%TEMP%\wazuh-agent-install.log` on endpoint |

---

## Key Notes

- **Idempotent** — BAT skips install if `WazuhSvc` already exists and running
- **SYSVOL path** — must use DC hostname (`WIN-IQ934P80NUM`), not IP address
- **GPO runs as SYSTEM** — no elevation issues during actual deployment
- **ossec.conf** — FIM directories and registry monitoring stripped for clean config
- **SCA + remote commands** — enabled via `local_internal_options.conf`
- **Registration password** — `Viswa@12345.` must match Wazuh manager authd config

---

## Roll Out to 100 Endpoints

1. Move all 100 computer accounts to `OU=Wazuh`
2. Enable firewall rules on each endpoint (or push via separate GPO)
3. Reboot each endpoint — GPO startup script runs automatically
4. Monitor in Wazuh Dashboard — agents appear as Active within 1-2 minutes of boot
