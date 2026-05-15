# 🛡️ WAZUH — Installation Guide

> **MY VISWA-Wazuh** · Server: `192.168.1.100` · Domain: `wazuh.viswa.local`

![Visitors](https://visitor-badge.laobi.icu/badge?page_id=20MH1A04H9.WAZUH)
![License](https://img.shields.io/badge/License-GPL%20v3-blue.svg)
![Platform](https://img.shields.io/badge/Platform-Ubuntu%2022.04-informational)
![Agents](https://img.shields.io/badge/Agents-200-critical)
![Status](https://img.shields.io/badge/Status-Active-success)

---

## 📋 Table of Contents

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
sudo apt update
sudo apt upgrade -y
```

### Install required packages

```bash
sudo apt install curl apt-transport-https unzip wget -y
```

### Kernel tuning (required for Wazuh Indexer)

```bash
# Set vm.max_map_count
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### Disable swap (required)

```bash
sudo swapoff -a
sudo nano /etc/fstab
# Comment out any swap line:
# /swapfile none swap sw 0 0
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

Run the official installer — installs **Manager + Indexer + Dashboard**:

```bash
curl -sO https://packages.wazuh.com/4.14/wazuh-install.sh && sudo bash ./wazuh-install.sh -a
```

> ⏱️ Installation takes **10–20 minutes**

At the end, save your credentials:

```
User: admin
Password: <generated — save this!>
```

---

## 4. Access Wazuh Dashboard

Open browser and go to:

```
https://192.168.1.100
```

Or using domain:

```
https://wazuh.viswa.local
```

| Field | Value |
|---|---|
| Username | `admin` |
| Password | *(from installation output)* |

> ⚠️ Change default password after first login!

---

## 5. Install Wazuh Agent — Linux

### Download and install agent

```bash
wget https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_4.14.2-1_amd64.deb \
  && sudo WAZUH_MANAGER='192.168.1.100' dpkg -i ./wazuh-agent_4.14.2-1_amd64.deb
```

### Start and enable agent

```bash
sudo systemctl start wazuh-agent
sudo systemctl enable wazuh-agent
```

### Verify agent status

```bash
sudo systemctl status wazuh-agent
```

---

## 6. Install Wazuh Agent — Windows

> **Run all commands in PowerShell as Administrator**

### Step 1 — Create temp directory

```powershell
New-Item -ItemType Directory -Force C:\Temp
```

### Step 2 — Download agent MSI

```powershell
Invoke-WebRequest -Uri https://packages.wazuh.com/4.x/windows/wazuh-agent-4.14.2-1.msi `
  -OutFile C:\Temp\wazuh-agent.msi
```

### Step 3 — Silent install with Viswa server IP

```powershell
msiexec.exe /i C:\Temp\wazuh-agent.msi /q `
  WAZUH_MANAGER='192.168.1.100' `
  WAZUH_MANAGER_PORT='1514' `
  WAZUH_AGENT_GROUP='default'
```

### Step 4 — Set agent name to hostname (optional)

```powershell
$conf = 'C:\Program Files (x86)\ossec-agent\ossec.conf'
(Get-Content $conf) -replace '<agent_name>.*</agent_name>', `
  '<agent_name>' + $env:COMPUTERNAME + '</agent_name>' | Set-Content $conf
```

### Step 5 — Start and auto-enable service

```powershell
NET START WazuhSvc
Set-Service -Name WazuhSvc -StartupType Automatic
```

### Step 6 — Verify service running

```powershell
Get-Service WazuhSvc | Select-Object Name, Status, StartType
```

> ✅ Expected: `Status: Running`

### Step 7 — Allow outbound firewall ports

```powershell
New-NetFirewallRule -DisplayName "Wazuh Agent" `
  -Direction Outbound `
  -RemoteAddress 192.168.1.100 `
  -RemotePort 1514,1515 `
  -Protocol TCP `
  -Action Allow
```

### Step 8 — Test connectivity to Viswa server

```powershell
Test-NetConnection -ComputerName 192.168.1.100 -Port 1514
Test-NetConnection -ComputerName 192.168.1.100 -Port 1515
```

> ✅ Both must show `TcpTestSucceeded: True`

---

## 7. Verify Agent Connection

### In the Wazuh dashboard

```
1. Open https://wazuh.viswa.local
2. Login as admin
3. Go to: Agents → Summary
4. Look for your hostname → Status: Active ✅
```

### Check agent logs (Windows troubleshooting)

```powershell
Get-Content "C:\Program Files (x86)\ossec-agent\ossec.log" -Tail 30
```

### Restart agent (Windows)

```powershell
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
| Indexer API | 9200 | TCP | OpenSearch/Elasticsearch API |
| Syslog | 514 | UDP | External log collection |

### Open ports on Viswa server (Ubuntu)

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
| Wazuh Server (Manager) | 4 vCPU | 8–16 GB | — |
| Wazuh Dashboard | 2–4 vCPU | 8–16 GB | — |

### Cluster sizing summary

| Agents | Indexer nodes | Total CPU | Total RAM | Storage (90 days) |
|---|---|---|---|---|
| 1–25 | 1 node | 4 vCPU | 8 GB | 50 GB |
| 25–50 | 1 node | 8 vCPU | 8 GB | 100 GB |
| 50–100 | 1–2 nodes | 8 vCPU | 8 GB | 200 GB |
| **200** | **3 nodes** | **48 vCPU** | **48 GB** | **400–500 GB** |
| 300 | 3 nodes | 72 vCPU | 96 GB | 600–800 GB |
| 500 | 5 nodes | 160 vCPU | 192 GB | 1.2–1.5 TB |

---

## 10. Kernel & OS Tuning

```bash
# Create sysctl config
sudo nano /etc/sysctl.d/99-wazuh-indexer.conf
```

Add:

```
vm.max_map_count=262144
fs.file-max=65536
```

Apply:

```bash
sudo sysctl -p --system
```

### Systemd override for Wazuh Indexer

```bash
sudo mkdir -p /etc/systemd/system/wazuh-indexer.service.d/
sudo nano /etc/systemd/system/wazuh-indexer.service.d/override.conf
```

Paste:

```ini
[Service]
LimitMEMLOCK=infinity
LimitNOFILE=65536
LimitNPROC=4096
```

Apply:

```bash
sudo systemctl daemon-reload
sudo systemctl restart wazuh-indexer
```

---

## 11. JVM Heap Configuration

| Server RAM | Recommended Xms/Xmx |
|---|---|
| 8 GB | `-Xms2g -Xmx2g` |
| 16 GB | `-Xms4g -Xmx4g` |
| **24 GB** *(MY setup)* | **`-Xms6g -Xmx6g`** |
| 32 GB | `-Xms8g -Xmx8g` |
| 64 GB | `-Xms16g -Xmx16g` |

### Check current heap

```bash
cat /etc/wazuh-indexer/jvm.options | grep -E "Xms|Xmx"
```

### Edit heap size

```bash
sudo nano /etc/wazuh-indexer/jvm.options
```

Set (for 24 GB server):

```
-Xms6g
-Xmx6g
```

### Restart indexer

```bash
sudo systemctl restart wazuh-indexer
sudo systemctl status wazuh-indexer
```

---

## 12. ILM Policy — Index Lifecycle

### Create ILM policy (30-day alert retention)

```bash
curl -X PUT "https://localhost:9200/_plugins/_ism/policies/wazuh-alert-retention-30d" \
  -H 'Content-Type: application/json' \
  -u admin:<YOUR_PASSWORD> \
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

### Apply policy to existing indices

```bash
curl -X POST "https://localhost:9200/wazuh-alerts-*/_plugins/_ism/add_policy" \
  -H 'Content-Type: application/json' \
  -u admin:<YOUR_PASSWORD> \
  -k \
  -d '{"policy_id": "wazuh-alert-retention-30d"}'
```

### Verify ILM is active

```bash
curl -X GET "https://localhost:9200/wazuh-alerts-*/_plugins/_ism/explain" \
  -u admin:<YOUR_PASSWORD> -k
```

---

## 13. Security Best Practices

- ✅ Change default `admin` password after first login
- ✅ Restrict dashboard access to trusted IPs only
- ✅ Use valid SSL certificates (replace self-signed)
- ✅ Enable firewall rules (`ufw`) on the Viswa server
- ✅ Monitor agent integrity regularly
- ✅ Keep Wazuh updated to latest stable version
- ✅ Enable ILM to prevent disk overflow
- ✅ Schedule daily snapshots to S3 or NFS

---

## 14. Service Management

### Check status

```bash
sudo systemctl status wazuh-manager
sudo systemctl status wazuh-indexer
sudo systemctl status wazuh-dashboard
```

### Restart all services

```bash
sudo systemctl restart wazuh-manager wazuh-indexer wazuh-dashboard
```

### Stop all services

```bash
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

### Edit main config

```bash
sudo nano /var/ossec/etc/ossec.conf
```

### Restart after config change

```bash
sudo systemctl restart wazuh-manager
```

---

## Architecture Overview

```
Endpoints (Windows / Linux / macOS / Cloud)
              │
         Wazuh Agents
         :1514 / :1515
              │
              ▼
    Wazuh Server (Manager)
    192.168.1.100 · wazuh.viswa.local
    REST API: :55000
              │
              ▼
    Wazuh Indexer (OpenSearch)
    :9200 · 3-node cluster
              │
              ▼
    Wazuh Dashboard
    https://wazuh.viswa.local · :443
              │
              ▼
       Security Analysts
```

---

## ✅ Summary

Wazuh provides a unified **SIEM + XDR** platform for monitoring 200+ endpoints. This guide covers the full lifecycle from server install to Windows/Linux agent deployment, tuning for production, and ILM policies for 30-day retention.

---

<div align="center">

🛡️ **MY VISWA-Wazuh** · `192.168.1.100` · `wazuh.viswa.local`

Made with ❤️ for Cybersecurity · GPL-3.0

</div>
