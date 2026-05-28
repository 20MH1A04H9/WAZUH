# 🪵 Apache Access Logs Integration with Wazuh / OpenSearch

> Complete guide for integrating Apache HTTP Server access logs with the Wazuh/OpenSearch observability stack using **Fluent Bit** as the log forwarder. Enables real-time visibility into web traffic, HTTP status codes, request patterns, and source IP analytics through OpenSearch Dashboards.

<p align="center">
  <img src="https://img.shields.io/badge/Ubuntu-24.04-E95420?style=for-the-badge&logo=ubuntu&logoColor=white"/>
  <img src="https://img.shields.io/badge/Apache-2.4.58-D22128?style=for-the-badge&logo=apache&logoColor=white"/>
  <img src="https://img.shields.io/badge/Fluent_Bit-v5.0.6-49BDA5?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/OpenSearch-2.19.5-005EB8?style=for-the-badge&logo=opensearch&logoColor=white"/>
  <img src="https://img.shields.io/badge/Wazuh-4.14.5-blue?style=for-the-badge"/>
</p>

---

## Table of Contents

- [Architecture](#architecture)
- [Infrastructure](#infrastructure)
- [Prerequisites](#prerequisites)
- [Step 1 — Install Fluent Bit](#step-1--install-fluent-bit)
- [Step 2 — Configure Fluent Bit](#step-2--configure-fluent-bit)
- [Step 3 — Configure OpenSearch](#step-3--configure-opensearch)
- [Step 4 — Create Systemd Service](#step-4--create-systemd-service)
- [Step 5 — OpenSearch Dashboard Integration](#step-5--opensearch-dashboard-integration)
- [Step 6 — Verification](#step-6--verification)
- [ECS Field Mapping](#ecs-field-mapping)
- [Dashboard Assets](#dashboard-assets)
- [Troubleshooting](#troubleshooting)

---

## Architecture

```
Apache HTTP Server
  │
  │  writes to
  ▼
/var/log/apache2/access.log
  │
  │  tailed + parsed by
  ▼
Fluent Bit v5.0.6
  │  → Parses Apache log format
  │  → Maps fields to ECS (Elastic Common Schema)
  │  → Forwards via HTTPS on port 9200
  ▼
OpenSearch (Wazuh Indexer) — index: ss4o_logs-apache-default
  │
  ▼
OpenSearch Dashboards (Apache Integration)
  → Pre-built visualizations, dashboards & saved searches
```

---

## Infrastructure

| Component | Details |
|---|---|
| **Apache Server IP** | `<Apache_Server_IP>` (public) / `<Apache_Server_Private_IP>` (private) |
| **Wazuh/OpenSearch IP** | `<Wazuh_Server_IP>` (public) / `<Wazuh_Server_Private_IP>` (private) |
| **Fluent Bit Version** | v5.0.6 |
| **OpenSearch Version** | 2.19.5 (Wazuh Indexer) |
| **Apache Version** | 2.4.58 (Ubuntu) |
| **Log Index** | `ss4o_logs-apache-default` |
| **Network Note** | Different Azure VNets — communication via public IP |

---

## Prerequisites

### Apache Server

- Ubuntu 24.04 LTS
- Apache HTTP Server 2.4.x running
- Access to `/var/log/apache2/access.log`
- Outbound HTTPS access to Wazuh server on **port 9200**

### Wazuh Server

- Wazuh 4.14.5 with OpenSearch (Wazuh Indexer) running
- Port **9200** open in Azure NSG for inbound connections
- OpenSearch bound to `0.0.0.0` (not `127.0.0.1`)

### Network Configuration

Apache and Wazuh servers are in different Azure VNets:

```bash
# 1. Open port 9200 inbound on Wazuh NSG
#    Rule name: Allow-OpenSearch-9200

# 2. Change OpenSearch network.host (see Step 3)

# 3. Verify connectivity from Apache server
curl -sk https://<Wazuh_Server_IP>:9200
```

---

## Step 1 — Install Fluent Bit

Run the following on the **Apache server**:

```bash
# Add Fluent Bit GPG key
curl https://packages.fluentbit.io/fluentbit.key | \
  sudo gpg --dearmor -o /usr/share/keyrings/fluentbit-keyring.gpg

# Add repository
echo "deb [signed-by=/usr/share/keyrings/fluentbit-keyring.gpg] \
  https://packages.fluentbit.io/ubuntu/noble noble main" | \
  sudo tee /etc/apt/sources.list.d/fluent-bit.list

# Install
sudo apt update && sudo apt install -y fluent-bit

# Add to PATH
sudo ln -s /opt/fluent-bit/bin/fluent-bit /usr/local/bin/fluent-bit

# Verify version
fluent-bit --version
# Expected: v5.0.6
```

---

## Step 2 — Configure Fluent Bit

### 2.1 Create Config Directory

```bash
sudo mkdir -p /opt/fluent-bit/etc
```

### 2.2 Create Apache Log Parser

Create `/opt/fluent-bit/etc/parsers-apache.conf`:

```ini
[PARSER]
    Name        apache
    Format      regex
    Regex       ^(?<host>[^ ]*) [^ ]* (?<user>[^ ]*) \[(?<time>[^\]]*)\] "(?<method>\S+)(?: +(?<path>[^\"]*?)(?: +\S*)?)?" (?<code>[^ ]*) (?<size>[^ ]*)(?: "(?<referer>[^\"]*)" "(?<agent>[^\"]*)")?$
    Time_Key    time
    Time_Format %d/%b/%Y:%H:%M:%S %z
```

### 2.3 Main Configuration File

Create `/opt/fluent-bit/etc/fluent-bit-apache.conf`:

```ini
[SERVICE]
    Flush        5
    Daemon       Off
    Log_Level    info
    Parsers_File /opt/fluent-bit/etc/parsers-apache.conf

[INPUT]
    Name              tail
    Path              /var/log/apache2/access.log
    Tag               apache.access
    Parser            apache
    Refresh_Interval  5

[FILTER]
    Name    modify
    Match   apache.*
    Rename  host    source.ip
    Rename  method  http.request.method
    Rename  path    url.original
    Rename  code    http.response.status_code
    Rename  size    http.response.bytes
    Rename  agent   user_agent.original
    Rename  user    user.name
    Add     event.dataset          apache.access
    Add     event.module           apache
    Add     service.type           apache
    Add     data_stream.type       logs
    Add     data_stream.dataset    apache.access
    Add     data_stream.namespace  default

[OUTPUT]
    Name            opensearch
    Match           *
    Host            <Wazuh_Server_IP>
    Port            9200
    HTTP_User       admin
    HTTP_Passwd     YOUR_PASSWORD
    tls             On
    tls.verify      Off
    Index           ss4o_logs-apache-default
    Suppress_Type_Name On
```

> ⚠️ Replace `YOUR_PASSWORD` with your actual Wazuh/OpenSearch admin password.

---

## Step 3 — Configure OpenSearch

Run the following on the **Wazuh server**:

### 3.1 Allow External Connections

```bash
# Change network.host from 127.0.0.1 to 0.0.0.0
sudo sed -i 's/network.host: "127.0.0.1"/network.host: "0.0.0.0"/' \
  /etc/wazuh-indexer/opensearch.yml

# Restart Wazuh Indexer
sudo systemctl restart wazuh-indexer
```

> ⚠️ **Security Note:** Changing `network.host` to `0.0.0.0` exposes OpenSearch externally. Always restrict access to trusted IPs only via Azure NSG rules.

### 3.2 Verify Connectivity

From the **Apache server**:

```bash
curl -sk --connect-timeout 5 \
  https://<Wazuh_Server_IP>:9200 \
  -u admin:'YOUR_PASSWORD' | head -c 100

# Expected: JSON with cluster name 'wazuh-cluster'
```

---

## Step 4 — Create Systemd Service

Create a permanent service so Fluent Bit starts automatically on the **Apache server**:

```bash
sudo tee /etc/systemd/system/fluent-bit-apache.service << 'EOF'
[Unit]
Description=Fluent Bit Apache Log Forwarder
After=network.target apache2.service

[Service]
Type=simple
ExecStart=/opt/fluent-bit/bin/fluent-bit -c /opt/fluent-bit/etc/fluent-bit-apache.conf
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable fluent-bit-apache
sudo systemctl start fluent-bit-apache

# Check status
sudo systemctl status fluent-bit-apache
```

---

## Step 5 — OpenSearch Dashboard Integration

### 5.1 Install Apache Integration

1. Go to **Wazuh Dashboard → Indexer Management → Integrations → Available**
2. Click **Apache Access Logs**
3. Set **Connection Type** → `OpenSearch Index`
4. Set **Index** → select `ss4o_logs-apache-default`
5. Click **Save**

---

## Step 6 — Verification

### 6.1 Check Log Count

Run on the **Wazuh server**:

```bash
curl -sk -u admin:'YOUR_PASSWORD' \
  https://localhost:9200/ss4o_logs-apache-default/_count

# Expected: {"count": <number>, ...}
```

### 6.2 Verify ECS Fields

```bash
curl -sk -u admin:'YOUR_PASSWORD' \
  https://localhost:9200/ss4o_logs-apache-default/_search?pretty \
  -H 'Content-Type: application/json' \
  -d '{"size":1,"sort":[{"@timestamp":{"order":"desc"}}]}' | \
  python3 -m json.tool | \
  grep -E "source\.|http\.|url\.|user_agent\.|event\."
```

### 6.3 Generate Test Traffic

From any machine:

```bash
for i in {1..20}; do
  curl -s http://<Apache_Server_IP>/ > /dev/null
  curl -s http://<Apache_Server_IP>/admin > /dev/null
  curl -s http://<Apache_Server_IP>/notfound > /dev/null
done
```

### 6.4 View Dashboard

```
Wazuh Dashboard → Explore → Dashboards → search "Apache"
→ Open: Access and error logs ECS
```

---

## ECS Field Mapping

Fluent Bit renames Apache log fields to ECS (Elastic Common Schema) format:

| ECS Field | Description |
|---|---|
| `source.ip` | Client IP address |
| `http.request.method` | HTTP method (GET, POST, etc.) |
| `url.original` | Request URL path |
| `http.response.status_code` | HTTP response code |
| `http.response.bytes` | Response size in bytes |
| `user_agent.original` | Browser/client user agent string |
| `user.name` | Authenticated username (if any) |
| `event.dataset` | Always: `apache.access` |
| `event.module` | Always: `apache` |
| `service.type` | Always: `apache` |

---

## Dashboard Assets

The Apache integration installs these pre-built assets automatically:

| Asset Name | Type |
|---|---|
| `ss4o_logs-*-*` | Index Pattern |
| Apache access logs | Saved Search |
| Apache errors log | Saved Search |
| Browsers breakdown | Visualization |
| Unique IPs map | Visualization |
| Operating systems breakdown | Visualization |
| Error logs over time | Visualization |
| Top URLs by response code | Visualization |
| Response codes over time | Visualization |
| Access and error logs ECS | Dashboard |
| Top IPs by Request Count | Observability Search |
| Top Status by Count | Observability Search |
| Number of Requests | Observability Search |
| Total Bytes Served | Observability Search |
| Requests by User Agent | Observability Search |

---

## Troubleshooting

| Issue | Fix |
|---|---|
| `Parser 'apache' not registered` | Create `/opt/fluent-bit/etc/parsers-apache.conf` with regex parser and add `Parsers_File` to `[SERVICE]` block |
| `Connection timeout to OpenSearch` | Check Azure NSG has port 9200 open; verify OpenSearch bound to `0.0.0.0` not `127.0.0.1` |
| `Public IP timeout (same subscription)` | Use private IP if VNets are peered, or public IP only if NSG allows it |
| `Different VNet — no connectivity` | Set up Azure VNet peering or use public IP with NSG rule |
| `0 new files found in Fluent Bit` | Normal when no new log entries — generate traffic to test (Step 6.3) |
| `Dashboard shows 0 data` | Check index pattern matches `ss4o_logs-apache-default`; refresh field list in Dashboard |
| `ECS fields missing` | Ensure `[FILTER] modify` block renames fields correctly before `[OUTPUT]` |
| `chunk cannot be retried` | OpenSearch returning error — check credentials and network; enable `Log_Level debug` in `[SERVICE]` |

### Enable Debug Logging

```bash
# Edit [SERVICE] block in fluent-bit-apache.conf
Log_Level    debug

# Then restart
sudo systemctl restart fluent-bit-apache

# Watch live logs
sudo journalctl -u fluent-bit-apache -f
```

---

<p align="center">
  🪵 Apache → Fluent Bit → OpenSearch → Wazuh Dashboard
</p>

<p align="center">
  <a href="https://github.com/20MH1A04H9/WAZUH">← Back to WAZUH Repository</a>
</p>
