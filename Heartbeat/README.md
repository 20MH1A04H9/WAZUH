# 🫀 Heartbeat Endpoint Monitoring — Wazuh SIEM Integration

> Automated **Elastic Heartbeat v9.4.2** endpoint up/down monitoring via **ICMP Ping → Logstash → OpenSearch → Wazuh Dashboard**. deploy with a single PowerShell script. Results visible in real-time every 30 seconds.

<p align="center">
  <img src="https://img.shields.io/badge/Heartbeat-9.4.2-00BFB3?style=for-the-badge&logo=elastic&logoColor=white"/>
  <img src="https://img.shields.io/badge/Logstash-8.19.16-F9A825?style=for-the-badge&logo=logstash&logoColor=white"/>
  <img src="https://img.shields.io/badge/Wazuh-4.14.5-006DFF?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/OpenSearch-Enabled-003B5C?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/Protocol-ICMP_Ping-brightgreen?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/Interval-30_Seconds-orange?style=for-the-badge"/>
</p>

---

## Table of Contents

- [Overview](#overview)
- [Infrastructure](#infrastructure)
- [Architecture](#architecture)
- [Files Required](#files-required)
- [Prerequisites](#prerequisites)
- [Step 1 — Install Java & Logstash](#step-1--install-java--logstash)
- [Step 2 — Install OpenSearch Output Plugin](#step-2--install-opensearch-output-plugin)
- [Step 3 — Configure Logstash Pipeline](#step-3--configure-logstash-pipeline)
- [Step 4 — Open Firewall & Network Ports](#step-4--open-firewall--network-ports)
- [Step 5 — Configure Heartbeat on Windows](#step-5--configure-heartbeat-on-windows)
- [Step 6 — Install Heartbeat as Windows Service](#step-6--install-heartbeat-as-windows-service)
- [Step 7 — Create OpenSearch Index Pattern](#step-7--create-opensearch-index-pattern)
- [Verification Checklist](#verification-checklist)
- [Data Flow](#data-flow)
- [Key Fields in OpenSearch](#key-fields-in-opensearch)


---

## Overview

This repository documents the complete deployment of **Elastic Heartbeat** for Windows endpoint availability monitoring, integrated with a self-hosted **Wazuh SIEM** stack via **Logstash** and **OpenSearch**.

Every monitored endpoint is pinged via **ICMP every 30 seconds**. Results are shipped to Logstash on port `5044`, indexed into OpenSearch as `heartbeat-YYYY.MM.DD`, and queryable from the Wazuh Dashboard using the `heartbeat-*` index pattern.

**SOC:** cyberexperts.online &nbsp;|&nbsp; **Date:** 09-06-2026 &nbsp;|&nbsp; **Classification:** Confidential

---

## Infrastructure

| Component | Details |
|---|---|
| Heartbeat Version | `9.4.2` |
| Install Path (Windows) | `C:\Program Files\Elastic\Beats\9.4.2\heartbeat` |
| Wazuh Server IP | `123.45.67.89` |
| Logstash Port | `5044` (TCP) |
| OpenSearch Index | `heartbeat-YYYY.MM.DD` |
| Monitor Protocol | ICMP Ping |
| Check Interval | Every 30 seconds |
| Test Endpoint | `10.2.0.143` |

---

## Architecture

```
Windows Endpoint
      │
      │  ICMP Ping (every 30s)
      ▼
Heartbeat Agent (Windows Service)
      │
      │  Beats protocol  ──  TCP 5044
      ▼
Logstash :5044          [Wazuh Server: 123.45.67.89]
      │
      │  logstash-output-opensearch
      ▼
OpenSearch  ──►  heartbeat-YYYY.MM.DD
      │
      ▼
Wazuh Dashboard  (index pattern: heartbeat-*)
```

---

## Files Required

```
heartbeat-deploy/
├── heartbeat.exe          # Heartbeat binary (v9.4.2)
├── heartbeat.yml          # Template config (overwritten by install.ps1)
├── install.ps1            # Auto-install PowerShell script
└── README.txt             # Deployment instructions for field use
```

---

## Prerequisites

- **Wazuh Server** (`123.45.67.89`) running Wazuh 4.14.5 with OpenSearch
- **Java 17** installed on the Wazuh server (required by Logstash)
- **Logstash 8.x** installed on the Wazuh server
- **Windows endpoint** (any version) with PowerShell available
- **AWSNSG / firewall** rule allowing inbound TCP `5044` to the Wazuh server
- Administrator rights on Windows endpoint for service installation

---

## Step 1 — Install Java & Logstash

Run on the **Wazuh server**:

```bash
# Install Java 17
apt install openjdk-17-jre-headless -y
java -version
# Expected: openjdk version "17.0.19"

# Add Elastic 8.x APT repository
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch \
  | gpg --dearmor -o /usr/share/keyrings/elastic-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/elastic-keyring.gpg] \
  https://artifacts.elastic.co/packages/8.x/apt stable main" \
  | tee /etc/apt/sources.list.d/elastic-8.x.list

# Install Logstash
apt update && apt install logstash -y
```

---

## Step 2 — Install OpenSearch Output Plugin

```bash
/usr/share/logstash/bin/logstash-plugin install logstash-output-opensearch
```

> **Verify:** `logstash-plugin list | grep opensearch` should return `logstash-output-opensearch`

---

## Step 3 — Configure Logstash Pipeline

Create `/etc/logstash/conf.d/heartbeat.conf`:

```ruby
input {
  beats {
    port => 5044
  }
}

filter {
  mutate {
    add_field => { "pipeline" => "heartbeat" }
  }
}

output {
  opensearch {
    hosts                        => ["https://localhost:9200"]
    index                        => "heartbeat-%{+YYYY.MM.dd}"
    user                         => "admin"
    password                     => "${OPENSEARCH_PASSWORD}"
    ssl                          => true
    ssl_certificate_verification => false
  }
}
```

Enable and start Logstash:

```bash
systemctl enable logstash
systemctl start logstash

# Confirm listening on 5044
ss -tnp | grep 5044
```

---

## Step 4 — Open Firewall & Network Ports

**Wazuh Server (UFW):**

```bash
ufw allow 5044/tcp
ufw reload
```

**AWSNSG (Portal):**
- Direction: `Inbound`
- Protocol: `TCP`
- Port: `5044`
- Source: `Any`
- Action: `Allow`

**Windows Endpoint (PowerShell — run as Administrator):**

```powershell
New-NetFirewallRule `
  -DisplayName "Heartbeat Outbound to Logstash" `
  -Direction Outbound `
  -Protocol TCP `
  -RemoteAddress 123.45.67.89 `
  -RemotePort 5044 `
  -Action Allow
```

**Test connectivity from endpoint:**

```powershell
Test-NetConnection 123.45.67.89 -Port 5044
# Expected: TcpTestSucceeded : True
```

---

## Step 5 — Configure Heartbeat on Windows

Edit `heartbeat.yml` in `C:\Program Files\Elastic\Beats\9.4.2\heartbeat\`:

```yaml
heartbeat.monitors:
  - type: icmp
    id: endpoint-icmp
    name: Endpoint Ping Monitor
    hosts: ["10.2.0.143"]
    schedule: '@every 30s'
    timeout: 5s

output.logstash:
  hosts: ["123.45.67.89:5044"]

logging.level: info
logging.to_files: true
logging.files:
  path: C:\ProgramData\heartbeat\logs
  name: heartbeat
  keepfiles: 7
```

---

## Step 6 — Install Heartbeat as Windows Service

Run in PowerShell **as Administrator** from the Heartbeat install directory:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
cd "C:\Program Files\Elastic\Beats\9.4.2\heartbeat"

# Register the service
sc.exe create heartbeat `
  binPath= '"C:\Program Files\Elastic\Beats\9.4.2\heartbeat\heartbeat.exe" -c heartbeat.yml --path.home "." --path.data "C:\ProgramData\heartbeat"' `
  start= auto `
  DisplayName= "Elastic Heartbeat"

# Start the service
Start-Service heartbeat

# Confirm running
Get-Service heartbeat
# Expected: Status = Running
```

---

## Step 7 — Create OpenSearch Index Pattern

**Set replicas to 0** (required for single-node cluster — makes index go Green):

```bash
curl -k -u admin:${OPENSEARCH_PASSWORD} \
  -X PUT "https://localhost:9200/heartbeat-*/_settings" \
  -H "Content-Type: application/json" \
  -d '{ "index": { "number_of_replicas": 0 } }'
```

**Create index pattern in Wazuh Dashboard:**

```bash
curl -k -u admin:${OPENSEARCH_PASSWORD} \
  -X POST "https://localhost:9200/.kibana/_doc/index-pattern:heartbeat-*" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "index-pattern",
    "index-pattern": {
      "title": "heartbeat-*",
      "timeFieldName": "@timestamp"
    }
  }'
```

Or via the Dashboard UI: **Stack Management → Index Patterns → Create → `heartbeat-*` → Time field: `@timestamp`**

---

### Client Deployment Commands

```powershell
# Run as Administrator on the target endpoint
Set-ExecutionPolicy Bypass -Scope Process -Force
cd "C:\Program Files\Elastic\Beats\9.4.2\heartbeat"
.\heartbeat.exe -c heartbeat.yml -e
```

---

## Verification Checklist

| # | Check | Command | Expected Result |
|---|---|---|---|
| 1 | Heartbeat service running | `Get-Service heartbeat` | `Status: Running` |
| 2 | Logstash listening on 5044 | `ss -tnp \| grep 5044` | `LISTEN` |
| 3 | TCP connectivity from endpoint | `Test-NetConnection 123.45.67.89 -Port 5044` | `TcpTestSucceeded: True` |
| 4 | Logstash → OpenSearch connected | `journalctl -u logstash \| grep -i connect` | Connection confirmed |
| 5 | Index exists and is Green | `GET /heartbeat-*/_cat/indices?v` | `green open heartbeat-...` |
| 6 | Documents growing | `GET /heartbeat-*/_count` | `15+` and increasing every 30s |
| 7 | Endpoint status field | Query `monitor.status` in Dashboard | `up` |

---

## Data Flow

Each endpoint running Heartbeat sends the following every 30 seconds:

```
Heartbeat pings 10.2.0.143 via ICMP
        │
        ▼
Packages result as Beats event:
  monitor.status  = "up" / "down"
  agent.hostname  = <endpoint hostname>
  agent.ip        = <endpoint IP>
  @timestamp      = <UTC time of check>
  rtt.total.us    = <round-trip time in microseconds>
        │
        ▼
Ships to Logstash 123.45.67.89:5044
        │
Logstash adds: pipeline = "heartbeat"
        │
        ▼
Indexed as: heartbeat-2026.06.09
        │
        ▼
Queryable in Wazuh Dashboard → heartbeat-*
```

---

## Key Fields in OpenSearch

| Field | Type | Description |
|---|---|---|
| `monitor.status` | keyword | `up` or `down` |
| `monitor.name` | keyword | Monitor display name |
| `monitor.host` | keyword | Target hostname or IP being pinged |
| `monitor.type` | keyword | Always `icmp` |
| `@timestamp` | date | Time of the check (UTC) |
| `agent.hostname` | keyword | Reporting endpoint hostname |
| `agent.ip` | ip | Reporting endpoint IP |
| `rtt.total.us` | long | Round-trip time in microseconds |
| `pipeline` | keyword | Always `heartbeat` (added by Logstash filter) |

---

## Troubleshooting

**Heartbeat can't reach Logstash:**
```powershell
Test-NetConnection 123.45.67.89 -Port 5044
# If False → check AWSNSG inbound rule and UFW on the Wazuh server
```
```bash
ufw status | grep 5044
```

**Index stays Yellow (not Green):**
```bash
# Single-node cluster cannot place replicas — force to 0
curl -k -u admin:${OPENSEARCH_PASSWORD} \
  -X PUT "https://localhost:9200/heartbeat-*/_settings" \
  -H "Content-Type: application/json" \
  -d '{ "index": { "number_of_replicas": 0 } }'
```

**Logstash fails to connect to OpenSearch after restart:**
```bash
# Logstash retries automatically once OpenSearch is fully up
journalctl -u logstash -n 50 --no-pager | grep -i "error\|connect\|restored"
```

**No documents after 5 minutes:**
```bash
# Verify the pipeline is loaded
curl -s http://localhost:9600/_node/pipelines?pretty | grep heartbeat

# Check for pipeline errors
journalctl -u logstash -n 100 --no-pager | grep -i "error\|warn"
```

**Heartbeat service fails to start on Windows:**
```powershell
# Check Windows Event Log for service errors
Get-EventLog -LogName System -Source "Service Control Manager" -Newest 20 |
  Where-Object { $_.Message -match "heartbeat" }
```

---

