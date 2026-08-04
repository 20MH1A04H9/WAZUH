# Shodan Critical Asset Monitoring for Wazuh

Continuous monitoring of critical, internet-facing assets using the Shodan API, integrated into Wazuh as a custom log source. Detects newly exposed assets, new open ports, new CVEs, SSL certificate changes, and DNS drift for FQDN-based assets.

## Architecture

```
Shodan API  →  Python script (cron/systemd)  →  JSON log file  →  Wazuh localfile  →  decoder/rules  →  alerts
```

The script runs on a schedule, checks each asset in your critical asset list against Shodan, diffs the result against the last known state, and writes a structured JSON event per asset to a log file that Wazuh ingests like any other log source.

## Prerequisites

- A Wazuh manager (tested against 4.14.x)
- Python 3.8+ on the manager, with the `requests` library available
- A Shodan account and API key

### A note on Shodan plan tiers

The `/shodan/host/<ip>` lookup endpoint used by this script **requires query credits**. A plain free Shodan account has **0 query credits** and will return `403` on every lookup — this isn't a bug, it's the account tier. Your options:

| Plan | Query credits | Cost |
|---|---|---|
| Free | 0 | $0 |
| Membership | 100/month | $49 one-time |
| Small Business+ | 10,000+/month | Subscription |

If you're staying on the free tier, use the **InternetDB variant** of this integration instead (see [Free-tier alternative](#free-tier-alternative-internetdb) below) — it uses a separate, uncredited Shodan endpoint that returns ports, hostnames, and CVEs at no cost, with slightly less detail (no SSL cert/banner data).

## Setup

### 1. Get a Shodan API key

Sign up at [shodan.io](https://www.shodan.io) and grab your key from **Account**. Treat it as a secret — never commit it to this repo or paste it into a chat/ticket. Rotate immediately if it's ever exposed.

### 2. Create required directories and files on the Wazuh manager

```bash
sudo mkdir -p /var/ossec/integrations
sudo touch /var/log/wazuh-shodan-critical.log
sudo chown wazuh:wazuh /var/ossec/integrations /var/log/wazuh-shodan-critical.log
sudo chmod 750 /var/ossec/integrations
sudo chmod 640 /var/log/wazuh-shodan-critical.log
```

> Don't `chown -R` on `/var/ossec/integrations` if other integrations (VirusTotal, Slack, PagerDuty, etc.) already live there with their own file-level ownership — apply ownership to the directory and to files this integration creates specifically.

### 3. Define your critical asset list

Create `/var/ossec/etc/lists/critical_servers`:

```
# format: target:asset_name|business_unit|environment|criticality|owner|asset_type
203.0.113.10:web-prod-01|ISS-Technologies|production|critical|network-team|ip
app.example.com:app-prod|CyberExperts|CyberAxisLab|production|high|app-team|fqdn
```

- `asset_type` is `ip` or `fqdn`. If omitted, it's inferred automatically.
- Use real public-facing IPs/hostnames — internal/RFC1918 addresses or documentation IPs (e.g. `203.0.113.0/24`) will just return "not found" or resolve nothing useful.

```bash
sudo chown wazuh:wazuh /var/ossec/etc/lists/critical_servers
sudo chmod 640 /var/ossec/etc/lists/critical_servers
```

### 4. Install dependencies

```bash
pip install requests --break-system-packages
```

### 5. Deploy the script

Copy `shodan_asset_monitor.py` to `/var/ossec/integrations/shodan_asset_monitor.py`:

```bash
sudo chown wazuh:wazuh /var/ossec/integrations/shodan_asset_monitor.py
sudo chmod 750 /var/ossec/integrations/shodan_asset_monitor.py
```

### 6. Run it manually first

Never run this as `root` — the log/state files need to stay owned by `wazuh`:

```bash
sudo -u wazuh env SHODAN_API_KEY="your-key" \
  python3 /var/ossec/integrations/shodan_asset_monitor.py
```

Check the output:

```bash
sudo cat /var/log/wazuh-shodan-critical.log
sudo cat /var/ossec/integrations/shodan_asset_state.json
```

Look for:
- `integration_health` → `status: api_key_valid`
- One `asset_exposure_check` or `dns_monitoring` event per asset
- `shodan_status: found` or `not_found` (both fine) — anything starting with `api_error_` or `exception` means something's wrong (bad key, no query credits, network egress blocked from the manager)

### 7. Schedule it

Cron example (every 6 hours):

```bash
sudo -u wazuh crontab -e
```

```
0 */6 * * * SHODAN_API_KEY="your-key" /usr/bin/python3 /var/ossec/integrations/shodan_asset_monitor.py
```

Prefer keeping the key out of crontab in plaintext — source it from a root-only env file instead:

```bash
0 */6 * * * . /etc/wazuh-shodan.env && /usr/bin/python3 /var/ossec/integrations/shodan_asset_monitor.py
```

### 8. Wire into `ossec.conf`

> **TODO — not yet completed in this project.** Add a `localfile` block pointing at `/var/log/wazuh-shodan-critical.log` with `log_format json`, then author decoders/rules mapped to this script's `event_type` field (`asset_exposure_check`, `dns_monitoring`, `missing_daily_execution`, `api_quota_low`, `script_execution_failure`) and to MITRE ATT&CK where applicable (e.g. T1590 – Gather Victim Network Information).

### 9. Health monitoring

Run with `--check-health` on a separate daily cron to detect a stalled/broken integration:

```bash
0 8 * * * SHODAN_API_KEY="your-key" /usr/bin/python3 /var/ossec/integrations/shodan_asset_monitor.py --check-health
```

This emits a `critical` severity `missing_daily_execution` event if the last successful run is more than 26 hours old.

## Free-tier alternative (InternetDB)

> **TODO — not yet implemented.** If staying on the free Shodan plan, `shodan_host_lookup()` should be pointed at `https://internetdb.shodan.io/{ip}` instead of `/shodan/host/{ip}`. This endpoint is free and uncredited but returns a reduced field set (ports, hostnames, tags, CVEs — no ISP/org/ASN, no SSL cert or banner data). The `extract_ssl_cert` / service-fingerprint logic would need to degrade gracefully in that case.

## Event types emitted

| `event_type` | Meaning |
|---|---|
| `integration_run_start` / `integration_run_complete` | Run lifecycle markers |
| `integration_health` | API key validity / quota / daily-execution status |
| `api_quota_low` | Query credits ≤ 10 |
| `asset_exposure_check` | Per-IP result: ports, CVEs, exposure state, diffs vs. last run |
| `dns_monitoring` | Per-FQDN result: resolved IPs and diffs vs. last run |
| `missing_daily_execution` | Last successful run older than 26h |
| `config_error` | Malformed asset list line, or empty asset list |
| `script_execution_failure` | Unhandled exception in the script |

## Security notes

- Never commit a real API key. Use `SHODAN_API_KEY` env var only.
- Rotate the key immediately if it's ever pasted into a chat, ticket, or committed accidentally.
- Run as the `wazuh` service user, not root.
- The asset list itself (`critical_servers`) reveals your critical infrastructure — keep its permissions at `640`, owned by `wazuh:wazuh`.
