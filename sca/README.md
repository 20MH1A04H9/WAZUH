## Windows Agent — SCA Configuration

Add the following block to the Windows agent configuration file:
 
**File path:** `C:\Program Files (x86)\ossec-agent\ossec.conf`
 
```xml
<sca>
  <enabled>yes</enabled>
  <interval>60s</interval>
  <policies>
    <policy>C:\Program Files (x86)\ossec-agent\shared\bitlocker_sca.yml</policy>
    <policy>C:\Program Files (x86)\ossec-agent\shared\antivirus_sca.yml</policy>
    <policy>C:\Program Files (x86)\ossec-agent\shared\win_applications_sca.yml</policy>
    <policy>C:\Program Files (x86)\ossec-agent\shared\powershell_sca.yml</policy>
  </policies>
</sca>
```
 
### Configuration Fields
 
| Field | Value | Description |
|---|---|---|
| `<enabled>` | `yes` | Enables SCA module on the agent |
| `<interval>` | `60s` | Runs a scan every 60 seconds |
| `<policy>` | path to `.yml` | Full path to each SCA policy file |
 
---
## SCA Policy Files
 
| File | Location on Agent | Description |
|---|---|---|
| `bitlocker_sca.yml` | `C:\Program Files (x86)\ossec-agent\shared\` | Verifies BitLocker drive encryption is enabled |
| `antivirus_sca.yml` | `C:\Program Files (x86)\ossec-agent\shared\` | Checks antivirus is installed, running, and updated |
 
These files are automatically pushed to agents via the Wazuh Manager shared directory:
```
/var/ossec/etc/shared/default/
```
 
---
 
## How It Works
 
```
Wazuh Manager
  └── /var/ossec/etc/shared/default/
        ├── antivirus_sca.yml   ──► pushed to ──► C:\...\ossec-agent\shared\
        └── bitlocker_sca.yml   ──► pushed to ──► C:\...\ossec-agent\shared\
```
 
1. Manager pushes `.yml` files to all connected Windows agents via the shared folder
2. The agent reads `ossec.conf` and loads the SCA policies from the `<policies>` block
3. Every `60s` the agent scans the endpoint and reports results back to the manager
4. Results appear in **Wazuh Dashboard → Security Configuration Assessment**
