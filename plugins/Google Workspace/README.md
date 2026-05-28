# Google Workspace → Wazuh Integration

Complete guide for integrating Google Workspace audit logs into Wazuh SIEM using the `wazuh-gworkspace` community wodle with a systemd-based scheduler.

---

## Architecture

```
Google Workspace Admin
        │
        │  Google Admin SDK / Alert Center API
        ▼
Service Account (Domain-Wide Delegation)
        │
        │  OAuth2 / HTTPS
        ▼
gworkspace.py (Python wodle)
        │
        │  JSON events → stdout
        ▼
Wazuh Manager (command wodle / systemd)
        │
        ▼
Wazuh Indexer → Wazuh Dashboard
```

---

## What Gets Monitored

| Application | Events Captured |
|---|---|
| **admin** | User creation, password resets, role changes, domain settings |
| **login** | Login success/failure, suspicious logins, 2FA events |
| **drive** | File sharing, external access, downloads, deletions |
| **token** | OAuth app authorizations, scope grants |
| **saml** | SSO login attempts and failures |
| **calendar** | Event sharing, external invites |
| **groups** | Group membership changes |
| **mobile** | Suspicious device activity |
| **alert center** | Phishing alerts, malware, suspicious login warnings |
| **rules** | DLP rule triggers |
| **user_accounts** | Account setting changes |

---

## Folder Structure

```
google-workspace/
├── README.md                          # This file
├── wodle/
│   ├── gworkspace.py                  # Main Python wodle script
│   ├── config.json                    # Service account + customer config
│   └── service_account_key.json       # ⚠️ Add to .gitignore — never commit
├── rules/
│   └── gworkspace_rules.xml           # Wazuh detection rules
└── systemd/
    ├── gworkspace-wazuh.service       # systemd service unit
    └── gworkspace-wazuh.timer         # systemd timer (runs every 30s)
```

> ⚠️ **Never commit** `service_account_key.json` or `config.json` (contains credentials) to version control.

---

## Prerequisites

- Wazuh Manager installed and running
- Python 3 with packages: `google-auth`, `google-auth-httplib2`, `google-api-python-client`
- Google Workspace Super Admin access
- Google Cloud project with billing enabled (free tier is sufficient)

---

## Phase 1 — Google Cloud Console Setup

### Step 1 — Create a GCP Project

1. Go to [console.cloud.google.com](https://console.cloud.google.com)
2. Create a new project (e.g. `wazuh-gworkspace`)
3. Note the **Project ID**

### Step 2 — Enable Required APIs

In **APIs & Services → Library**, enable:

- **Admin SDK API**
- **Google Workspace Alert Center API**

### Step 3 — Create a Service Account

1. Go to **IAM & Admin → Service Accounts → Create Service Account**
2. Name: `wazuh-monitor`
3. After creation → **Keys tab → Add Key → JSON**
4. Download the JSON key file → copy to your Wazuh server

### Step 4 — Enable Domain-Wide Delegation

1. On the service account → **Edit → Advanced Settings**
2. Enable **Domain-wide delegation**
3. Note the **Client ID** (long numeric string)

---

## Phase 2 — Google Workspace Admin Console

### Step 5 — Authorize the Service Account

1. Go to **admin.google.com → Security → Access and data controls → API controls**
2. Click **Manage Domain Wide Delegation → Add new**
3. Enter:
   - **Client ID**: (from Step 4)
   - **OAuth Scopes**:
     ```
     https://www.googleapis.com/auth/admin.reports.audit.readonly,
     https://www.googleapis.com/auth/apps.alerts
     ```
4. Click **Authorize**

---

## Phase 3 — Wazuh Server Setup

### Step 6 — Install the Wodle

```bash
cd /var/ossec/wodles/
git clone https://github.com/avanwouwe/wazuh-gworkspace.git gworkspace
```

### Step 7 — Install Python Dependencies

```bash
pip3 install google-auth google-auth-httplib2 google-api-python-client --break-system-packages
```

### Step 8 — Copy Credentials

```bash
cp /root/your-service-account-key.json /var/ossec/wodles/gworkspace/wodle/service_account_key.json
chmod 640 /var/ossec/wodles/gworkspace/wodle/service_account_key.json
chown root:wazuh /var/ossec/wodles/gworkspace/wodle/service_account_key.json
```

### Step 9 — Create config.json

```bash
cat > /var/ossec/wodles/gworkspace/wodle/config.json << 'EOF'
{
    "service_account": "admin@yourdomain.com",
    "customer_id": "your_customer_id"
}
EOF
```

> 💡 `customer_id` can be `my_customer` (auto-resolves) or your actual ID (e.g. `C0xxxxxxx`) found at **admin.google.com → Account → Account settings**.

### Step 10 — Test Manually

```bash
python3 /var/ossec/wodles/gworkspace/wodle/gworkspace.py -a admin -o 2
```

Expected output — JSON events like:
```json
{"srcip": "x.x.x.x", "user": "admin@yourdomain.com", "gworkspace": {"application": "admin", "eventtype": "user settings", "eventname": "create user", ...}}
```

### Step 11 — Install Detection Rules

```bash
cp /var/ossec/wodles/gworkspace/rules/*.xml /var/ossec/etc/rules/
chown root:wazuh /var/ossec/etc/rules/gworkspace*.xml
```

---

## Phase 4 — systemd Service Setup

Replace the ossec.conf wodle approach with a proper systemd service and timer.

### Step 12 — Create the Service Unit

```bash
cat > /etc/systemd/system/gworkspace-wazuh.service << 'EOF'
[Unit]
Description=Google Workspace Wazuh Integration
After=wazuh-manager.service
Wants=wazuh-manager.service

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 /var/ossec/wodles/gworkspace/wodle/gworkspace.py -a all -o 2
User=root
StandardOutput=journal
StandardError=journal
EOF
```

### Step 13 — Create the Timer Unit

```bash
cat > /etc/systemd/system/gworkspace-wazuh.timer << 'EOF'
[Unit]
Description=Run Google Workspace Wazuh Integration every 30 seconds
Requires=gworkspace-wazuh.service

[Timer]
OnBootSec=10sec
OnUnitActiveSec=30sec
Unit=gworkspace-wazuh.service

[Install]
WantedBy=timers.target
EOF
```

> ⚠️ 30 seconds is aggressive for testing. For production, use `10min` to avoid Google API rate limits (`429 Too Many Requests`).

### Step 14 — Enable and Start

```bash
systemctl daemon-reload
systemctl enable gworkspace-wazuh.timer
systemctl start gworkspace-wazuh.timer
systemctl status gworkspace-wazuh.timer
```

### Step 15 — Restart Wazuh

```bash
systemctl restart wazuh-manager
```

---

## Verification

### Check Timer is Running

```bash
systemctl status gworkspace-wazuh.timer
journalctl -u gworkspace-wazuh.service -f
```

### Verify Alerts are Flowing

```bash
tail -f /var/ossec/logs/alerts/alerts.json | grep gworkspace
```

### In Wazuh Dashboard

Go to **Security Events** and filter:
```
rule.groups: gworkspace
```
or
```
data.gworkspace.application: admin
```

---

## Rules Reference

Rules are in `/var/ossec/etc/rules/gworkspace_rules.xml` — IDs `64600–65499`.

| Rule ID | Level | Trigger |
|---|---|---|
| 64600 | 3 | Any Google Workspace event (base rule) |
| 64601 | 14 | Extraction error |
| 64610 | 5 | SAML / token / login events |
| 64612 | 6 | Admin / groups / GCP events |
| 64614 | 7 | Rules / user account changes |
| 64616 | 10 | Security settings change |
| 64624 | 12 | Delegated admin sensitive activity |
| 64628 | 10 | Suspicious login detected |
| 64650 | 10 | Intensive file download (DLP) |
| 64654 | 12 | Many failed logins — credential stuffing |
| 64700 | 10 | Alert Center event |

### Rule Group Tags

The rules are tagged with both groups for dashboard compatibility:

```xml
<group name="gworkspace,gcp,">
```

This means events appear when filtering either `rule.groups: gworkspace` or `rule.groups: gcp` in the Wazuh Dashboard.

---

## Useful Dashboard Queries

| Query | Purpose |
|---|---|
| `rule.groups: gworkspace` | All Google Workspace events |
| `data.gworkspace.application: admin` | Admin console activity |
| `data.gworkspace.eventname: create user` | New user creation |
| `data.gworkspace.eventtype: user settings` | User setting changes |
| `data.gworkspace.application: login` | All login events |
| `data.gworkspace.application: drive` | Drive activity |
| `rule.id: 64654` | Brute force / credential stuffing |
| `rule.level: [10 TO 14]` | High severity events only |

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `KeyError: 'service_account'` | Wrong key name in config.json | Use `service_account` not `delegated_account` |
| `FileNotFoundError: config.json` | Wrong working directory | Run from `/var/ossec/wodles/gworkspace/wodle/` or use full paths |
| `403 Alert Center API disabled` | API not enabled in GCP | Enable at `console.developers.google.com/apis/api/alertcenter.googleapis.com` |
| `No such file: framework/python` | Shell wrapper uses wrong Python path | Run `gworkspace.py` directly with `python3` |
| `externally-managed-environment` | Debian pip restriction | Add `--break-system-packages` flag |
| `429 Too Many Requests` | Timer interval too short | Increase `OnUnitActiveSec` to `5min` or `10min` |

---

## Security Notes

- The service account key JSON has full read access to all audit logs — protect it like a password
- Add `service_account_key.json` and `config.json` to `.gitignore`
- Restrict the service account to read-only scopes only (already done with the OAuth scopes above)
- Rotate the service account key periodically via GCP Console
