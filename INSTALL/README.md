# WAZUH

**SIEM + XDR · All-in-One Install · Agent Deployment · Tuning · ILM**

![License](https://img.shields.io/badge/License-GPL%20v3-blue?style=for-the-badge)
![Platform](https://img.shields.io/badge/PLATFORM-UBUNTU%2022.04-555555?style=for-the-badge)
![Wazuh](https://img.shields.io/badge/WAZUH-4.14.5-0052CC?style=for-the-badge)
![Agents](https://img.shields.io/badge/AGENTS-200+-E8590C?style=for-the-badge)
![Indexer](https://img.shields.io/badge/INDEXER-OPENSEARCH-D32F2F?style=for-the-badge)
![Status](https://img.shields.io/badge/STATUS-ACTIVE-26A69A?style=for-the-badge)
![Windows](https://img.shields.io/badge/AGENT-WINDOWS%20%7C%20LINUX-333333?style=for-the-badge)

`Wazuh v4.14.5` · `Ubuntu 22.04 LTS`

---
## Dashboard Preview
 
![Wazuh Dashboard](https://raw.githubusercontent.com/20MH1A04H9/WAZUH/main/assets/dashboard.png)
 
---

## Table of Contents

1. [System Requirements](#1-system-requirements)
2. [Pre-Installation Setup](#2-pre-installation-setup)
3. [Install Wazuh Server (All-in-One)](#3-install-wazuh-server-all-in-one)
4. [Access Wazuh Dashboard](#4-access-wazuh-dashboard)
5. [Install Wazuh Agent — Linux](#5-install-wazuh-agent--linux)
6. [Install Wazuh Agent — Windows](#6-install-wazuh-agent--windows)
7. [Verify Agent Connection](#7-verify-agent-connection)
8. [Network Ports](#8-network-ports)
9. [Resource Sizing — 200 Agents](#9-resource-sizing--200-agents)
10. [Kernel & OS Tuning](#10-kernel--os-tuning)
11. [JVM Heap Configuration](#11-jvm-heap-configuration)
12. [ILM Policy — Index Lifecycle](#12-ilm-policy--index-lifecycle)
13. [Security Best Practices](#13-security-best-practices)
14. [Service Management](#14-service-management)
15. [Important Directories](#15-important-directories)

---

## 1. System Requirements

| Component | Minimum | Recommended (200 agents) |
|---|---|---|
| CPU | 4 vCPU | 16 vCPU |
| RAM | 8 GB | 16–24 GB |
| Disk | 50 GB | 400–800 GB |
| OS | Ubuntu 20.04 | Ubuntu 22.04 LTS |

> **Indexer cluster** (3 nodes for 200 agents): 8 vCPU + 24 GB RAM + 200–250 GB SSD **per node**

---

## 2. Pre-Installation Setup

### Update system

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install curl apt-transport-https unzip wget -y
```

### Kernel tuning (required for Wazuh Indexer)

```bash
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### Disable swap

```bash
sudo swapoff -a
# Comment out any swap line in /etc/fstab:
# /swapfile none swap sw 0 0
```

Or create a dedicated swapfile:

```bash
sudo fallocate -l 8G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

### Increase file descriptors

Add to `/etc/security/limits.conf`:

```
wazuh-indexer soft nofile 65536
wazuh-indexer hard nofile 65536
wazuh-indexer soft nproc 4096
wazuh-indexer hard nproc 4096
```

---

## 3. Install Wazuh Server (All-in-One)

Installs **Manager + Indexer + Dashboard** in a single step:

```bash
curl -sO https://packages.wazuh.com/4.14/wazuh-install.sh && sudo bash ./wazuh-install.sh -a
```

> Installation takes 10–20 minutes. Save the generated `admin` password from the output.

---

## 4. Access Wazuh Dashboard

```
https://YOUR_WAZUH_SERVER_IP
```

| Field | Value |
|---|---|
| Username | `admin` |
| Password | *(from installation output)* |

> Change the default password immediately after first login.

---

## 5. Install Wazuh Agent — Linux

```bash
wget https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_4.14.2-1_amd64.deb \
  && sudo WAZUH_MANAGER='YOUR_WAZUH_SERVER_IP' dpkg -i ./wazuh-agent_4.14.2-1_amd64.deb

sudo systemctl start wazuh-agent
sudo systemctl enable wazuh-agent
sudo systemctl status wazuh-agent
```

---

## 6. Install Wazuh Agent — Windows

> Run all commands in **PowerShell as Administrator**

```powershell
# Create temp directory
New-Item -ItemType Directory -Force C:\Temp

# Download agent MSI
Invoke-WebRequest -Uri https://packages.wazuh.com/4.x/windows/wazuh-agent-4.14.2-1.msi `
  -OutFile C:\Temp\wazuh-agent.msi

# Silent install
msiexec.exe /i C:\Temp\wazuh-agent.msi /q `
  WAZUH_MANAGER='YOUR_WAZUH_SERVER_IP' `
  WAZUH_MANAGER_PORT='1514' `
  WAZUH_AGENT_GROUP='default'

# (Optional) Set agent name to hostname
$conf = 'C:\Program Files (x86)\ossec-agent\ossec.conf'
(Get-Content $conf) -replace '<agent_name>.*</agent_name>', `
  '<agent_name>' + $env:COMPUTERNAME + '</agent_name>' | Set-Content $conf

# Start and enable service
NET START WazuhSvc
Set-Service -Name WazuhSvc -StartupType Automatic

# Verify
Get-Service WazuhSvc | Select-Object Name, Status, StartType
```

Allow outbound firewall ports:

```powershell
New-NetFirewallRule -DisplayName "Wazuh Agent" `
  -Direction Outbound `
  -RemoteAddress YOUR_WAZUH_SERVER_IP `
  -RemotePort 1514,1515 `
  -Protocol TCP `
  -Action Allow
```

Test connectivity:

```powershell
Test-NetConnection -ComputerName YOUR_WAZUH_SERVER_IP -Port 1514
Test-NetConnection -ComputerName YOUR_WAZUH_SERVER_IP -Port 1515
# Both must show TcpTestSucceeded: True
```

---

## 7. Verify Agent Connection

**Dashboard:** `https://YOUR_WAZUH_SERVER_IP` → Agents → Summary → Status: Active ✅

**Windows logs:**

```powershell
Get-Content "C:\Program Files (x86)\ossec-agent\ossec.log" -Tail 30
Restart-Service WazuhSvc
```

---

## 8. Network Ports

| Service | Port | Protocol | Purpose |
|---|---|---|---|
| Wazuh Dashboard | 443 | TCP | Web interface |
| Wazuh REST API | 55000 | TCP | API access |
| Agent communication | 1514 | TCP | Agent events to manager |
| Agent registration | 1515 | TCP | Agent enrollment |
| Indexer API | 9200 | TCP | OpenSearch API |
| Syslog | 514 | UDP | External log collection |

```bash
sudo ufw allow 443/tcp
sudo ufw allow 1514/tcp
sudo ufw allow 1515/tcp
sudo ufw allow 55000/tcp
sudo ufw allow 9200/tcp
sudo ufw reload
```

---

## 9. Resource Sizing — 200 Agents

| Role | CPU | RAM | Storage |
|---|---|---|---|
| Wazuh Indexer (×3 nodes) | 8 vCPU each | 24 GB each | 200–250 GB SSD each |
| Wazuh Manager | 4 vCPU | 8–16 GB | — |
| Wazuh Dashboard | 2–4 vCPU | 8–16 GB | — |

| Agents | Indexer Nodes | Total CPU | Total RAM | Storage (90 days) |
|---|---|---|---|---|
| 1–25 | 1 | 4 vCPU | 8 GB | 50 GB |
| 25–50 | 1 | 8 vCPU | 8 GB | 100 GB |
| 50–100 | 1–2 | 8 vCPU | 8 GB | 200 GB |
| **200** | **3** | **48 vCPU** | **48 GB** | **400–500 GB** |
| 300 | 3 | 72 vCPU | 96 GB | 600–800 GB |
| 500 | 5 | 160 vCPU | 192 GB | 1.2–1.5 TB |

---

## 10. Kernel & OS Tuning

```bash
sudo tee /etc/sysctl.d/99-wazuh-indexer.conf << 'EOF'
vm.max_map_count=262144
fs.file-max=65536
EOF

sudo sysctl -p --system
```

### systemd override for Wazuh Indexer

```bash
sudo mkdir -p /etc/systemd/system/wazuh-indexer.service.d/

sudo tee /etc/systemd/system/wazuh-indexer.service.d/override.conf << 'EOF'
[Service]
LimitMEMLOCK=infinity
LimitNOFILE=65536
LimitNPROC=4096
EOF

sudo systemctl daemon-reload
sudo systemctl restart wazuh-indexer
```

---

## 11. JVM Heap Configuration

| Server RAM | Recommended Xms/Xmx |
|---|---|
| 8 GB | `-Xms2g -Xmx2g` |
| 16 GB | `-Xms4g -Xmx4g` |
| 24 GB | `-Xms6g -Xmx6g` |
| 32 GB | `-Xms8g -Xmx8g` |
| 64 GB | `-Xms16g -Xmx16g` |

```bash
# Check current heap
cat /etc/wazuh-indexer/jvm.options | grep -E "Xms|Xmx"

# Edit
sudo nano /etc/wazuh-indexer/jvm.options

sudo systemctl restart wazuh-indexer
```

---

## 12. ILM Policy — Index Lifecycle

### Create 30-day alert retention policy

```bash
curl -X PUT "https://localhost:9200/_plugins/_ism/policies/wazuh-alert-retention-30d" \
  -H 'Content-Type: application/json' \
  -u admin:YOUR_ADMIN_PASSWORD \
  -k \
  -d '{
    "policy": {
      "policy_id": "wazuh-alert-retention-30d",
      "description": "Delete wazuh alerts after 30 days",
      "default_state": "retention_state",
      "states": [
        {
          "name": "retention_state",
          "actions": [],
          "transitions": [
            {
              "state_name": "delete_alerts",
              "conditions": { "min_index_age": "30d" }
            }
          ]
        },
        {
          "name": "delete_alerts",
          "actions": [{ "delete": {} }],
          "transitions": []
        }
      ],
      "ism_template": [
        { "index_patterns": ["wazuh-alerts-*"], "priority": 200 }
      ]
    }
  }'
```

### Apply to existing indices

```bash
curl -X POST "https://localhost:9200/wazuh-alerts-*/_plugins/_ism/add_policy" \
  -H 'Content-Type: application/json' \
  -u admin:YOUR_ADMIN_PASSWORD \
  -k \
  -d '{"policy_id": "wazuh-alert-retention-30d"}'
```

### Verify

```bash
curl -X GET "https://localhost:9200/wazuh-alerts-*/_plugins/_ism/explain" \
  -u admin:YOUR_ADMIN_PASSWORD -k
```

---

## 13. Security Best Practices

- ✅ Change default `admin` password after first login
- ✅ Restrict dashboard access to trusted IPs only
- ✅ Replace self-signed certificates with valid SSL certs
- ✅ Enable `ufw` firewall rules on the server
- ✅ Monitor agent integrity regularly
- ✅ Keep Wazuh updated to latest stable version
- ✅ Enable ILM to prevent disk overflow
- ✅ Schedule daily snapshots to S3 or NFS

---

## 14. Service Management

```bash
# Status
sudo systemctl status wazuh-manager
sudo systemctl status wazuh-indexer
sudo systemctl status wazuh-dashboard

# Restart all
sudo systemctl restart wazuh-manager wazuh-indexer wazuh-dashboard

# Stop all
sudo systemctl stop wazuh-manager wazuh-indexer wazuh-dashboard
```

---

## 15. Important Directories

| Directory | Purpose |
|---|---|
| `/var/ossec/logs/` | Wazuh logs |
| `/var/ossec/etc/ossec.conf` | Main config file |
| `/var/ossec/ruleset/` | Detection rules |
| `/var/ossec/queue/` | Event queue |
| `/etc/wazuh-indexer/` | Indexer config & JVM options |
| `/etc/wazuh-dashboard/` | Dashboard config |

```bash
sudo nano /var/ossec/etc/ossec.conf
sudo systemctl restart wazuh-manager
```

---

## Architecture

```
Endpoints (Windows / Linux / macOS / Cloud)
              │
         Wazuh Agents
         :1514 / :1515
              │
              ▼
    ┌─────────────────────┐
    │   Wazuh Manager     │
    │   REST API :55000   │
    └─────────┬───────────┘
              │
              ▼
    ┌─────────────────────┐
    │  Wazuh Indexer      │
    │  OpenSearch :9200   │
    │  3-node cluster     │
    └─────────┬───────────┘
              │
              ▼
    ┌─────────────────────┐
    │  Wazuh Dashboard    │
    │  https :443         │
    └─────────────────────┘
              │
              ▼
       Security Analysts
```

---

## License

GPL-3.0
