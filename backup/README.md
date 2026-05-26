# Wazuh Backup & Retention Guide

Complete guide for backing up your Wazuh server configuration, rules, decoders, and logs — including automated retention cleanup.

---

## Folder Structure

```
wazuh-backup/
├── README.md                   # This file
├── scripts/
│   ├── wazuh-backup.sh         # Full backup script
│   └── wazuh-retention.sh      # Auto-delete old backups

```

---

## What Gets Backed Up

| Path | Contents |
|---|---|
| `/etc/filebeat/` | Filebeat config (indexer/dashboard connection) |
| `/var/ossec/api/configuration/` | Wazuh API config |
| `/var/ossec/etc/client.keys` | Agent registration keys |
| `/var/ossec/etc/sslmanager*` | SSL certificates |
| `/var/ossec/etc/ossec.conf` | Main Wazuh config |
| `/var/ossec/etc/internal_options.conf` | Internal options |
| `/var/ossec/etc/local_internal_options.conf` | Local overrides |
| `/var/ossec/etc/rules/` | All rules (custom + default) |
| `/var/ossec/etc/decoders/` | All decoders |
| `/var/ossec/etc/shared/` | Agent groups |
| `/var/ossec/logs/` | Logs (useful for forensics) |
| `/var/ossec/stats/` | Statistics |

### ❌ Intentionally Excluded (runtime cache — not needed for restore)

- `/var/ossec/queue/vd/`
- `/var/ossec/queue/db/`
- `/var/ossec/queue/tmp/`
- `/var/ossec/queue/agent-info/backup/`



## Notes

- Run backups before any major change (rule updates, config changes, upgrades)
- Store archives offsite or in cloud storage for disaster recovery
- The backup script uses `rsync` — install it first if missing: `apt install rsync -y`
