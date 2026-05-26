# WAZUH — Security Configuration Assessment (SCA) Policies , Rules and Decoders

---

## One-Line Installers

### Wazuh Rules and Decodes
```bash
curl -so ~/wazuh.sh https://raw.githubusercontent.com/20MH1A04H9/WAZUH/main/scripts/wazuh.sh && bash ~/wazuh.sh
```

### SCA Policy Installer
```bash
curl -so ~/install_sca.sh https://raw.githubusercontent.com/20MH1A04H9/WAZUH/main/scripts/install_sca.sh && sudo bash ~/install_sca.sh
```

---

## What Gets Installed

| Policy File | Description |
|---|---|
| `antivirus_sca.yml` | Checks antivirus software is installed, running, and up to date |
| `bitlocker_sca.yml` | Verifies BitLocker drive encryption compliance on Windows endpoints |

### Install Paths

| Location | Purpose |
|---|---|
| `/var/ossec/etc/shared/default/` | Shared with all agents automatically |
| `/var/ossec/ruleset/sca/` | Scanned directly by the Wazuh Manager |

---

## Requirements

- Wazuh Manager installed and running
- Root / sudo access
- `curl` or `wget`
- Outbound internet access to `raw.githubusercontent.com`

---

## What the SCA Installer Does

1. Downloads `antivirus_sca.yml` and `bitlocker_sca.yml` from this repo
2. Installs them into `/var/ossec/etc/shared/default/`
3. Copies them to `/var/ossec/ruleset/sca/` for manager-side scanning
4. Backs up any existing versions before overwriting
5. Sets correct ownership (`root:wazuh`) and permissions (`640`)
6. Restarts Wazuh Manager to apply the policies

---

## Verify Installation

After running the installer, confirm the policies are active:

```bash
# Watch SCA logs in real time
tail -f /var/ossec/logs/ossec.log | grep -i sca

# List installed policy files
ls -la /var/ossec/etc/shared/default/*.yml
ls -la /var/ossec/ruleset/sca/*.yml
```

Then check results in the **Wazuh Dashboard**:
> Security Configuration Assessment → select your agent

---

## Repository Structure

```
WAZUH/
├── scripts/
│   ├── wazuh.sh          # Wazuh Rules and Decodes
│   └── install_sca.sh    # SCA policy one-line installer
```

---



**Policies not showing in Dashboard**
- Wait ~1 minute after restart for the first scan to complete
- Ensure the agent is connected: check **Agents** tab in the dashboard

---

## License

MIT
