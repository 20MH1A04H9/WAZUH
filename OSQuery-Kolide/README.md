# 🔍 Kolide Fleet + Graylog + OSQuery — Fleet Endpoint Monitoring

> Complete deployment guide for **Kolide Fleet** as an OSQuery fleet manager, integrated with **Graylog** for log aggregation and **Filebeat** for log shipping. Covers Ansible-based deployment, Windows and Linux OSQuery agent rollout, query packs, Graylog streams, and the full observability pipeline.

<p align="center">
  <img src="https://img.shields.io/badge/Kolide_Fleet-OSQuery_Manager-blue?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/OSQuery-Endpoint_Monitoring-orange?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/Graylog-Log_Aggregation-FF3333?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/Filebeat-Log_Shipper-00BFB3?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/Ansible-Automation-EE0000?style=for-the-badge&logo=ansible&logoColor=white"/>
  <img src="https://img.shields.io/badge/Platform-Ubuntu%20%7C%20CentOS%20%7C%20Windows-lightgrey?style=for-the-badge"/>
</p>

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Kolide Terms Glossary](#kolide-terms-glossary)
- [Infrastructure Requirements](#infrastructure-requirements)
- [Part 1 — Install Kolide Fleet on Ubuntu](#part-1--install-kolide-fleet-on-ubuntu)
  - [Step 1 — Clone & Configure Ansible](#step-1--clone--configure-ansible)
  - [Step 2 — Generate JWT Key](#step-2--generate-jwt-key)
  - [Step 3 — Configure Kolide Variables](#step-3--configure-kolide-variables)
  - [Step 4 — Set Inventory Hosts](#step-4--set-inventory-hosts)
  - [Step 5 — Run Ansible Playbook](#step-5--run-ansible-playbook)
  - [Step 6 — Kolide Web GUI Setup](#step-6--kolide-web-gui-setup)
- [Part 2 — OSQuery Windows Agent Deployment](#part-2--osquery-windows-agent-deployment)
  - [Step 1 — Get Enroll Secret from Kolide](#step-1--get-enroll-secret-from-kolide)
  - [Step 2 — Configure Windows Agent Variables](#step-2--configure-windows-agent-variables)
  - [Step 3 — Deploy via Ansible](#step-3--deploy-via-ansible)
- [Part 3 — OSQuery Linux Agent Deployment](#part-3--osquery-linux-agent-deployment)
  - [Ubuntu 16.04](#ubuntu-1604-desktop--server)
  - [CentOS 7.4](#centos-74)
- [Part 4 — Kolide Web GUI Features](#part-4--kolide-web-gui-features)
  - [Creating an OSQuery Query](#creating-an-osquery-query)
  - [Creating an OSQuery Pack](#creating-an-osquery-pack)
- [Part 5 — Install Graylog on Ubuntu](#part-5--install-graylog-on-ubuntu)
  - [Step 1 — Deploy Graylog via Ansible](#step-1--deploy-graylog-via-ansible)
  - [Step 2 — Create Graylog Input](#step-2--create-graylog-input)
  - [Step 3 — Create Graylog Stream](#step-3--create-graylog-stream)
- [Part 6 — Install Filebeat on Kolide Server](#part-6--install-filebeat-on-kolide-server)
- [Useful OSQuery Queries](#useful-osquery-queries)
- [Troubleshooting](#troubleshooting)
- [References](#references)

---

## Overview

This guide deploys a complete **endpoint observability stack** using:

- **OSQuery** — exposes OS data as SQL-queryable tables on each endpoint
- **Kolide Fleet** — centrally manages OSQuery across all endpoints (scheduling queries, packs, distributed queries)
- **Filebeat** — ships OSQuery results from Kolide to Graylog
- **Graylog** — aggregates and indexes all endpoint telemetry for search and alerting

The result is a centralized platform for **threat hunting**, **incident response**, and **continuous endpoint monitoring** across Windows and Linux fleets.

---

## Architecture

```
Endpoints (Windows / Linux / macOS)
  │
  │  OSQuery agent → TLS (HTTPS)
  │
  ▼
Kolide Fleet Server (Ubuntu)
  ├── Manages queries, packs, schedules
  ├── Stores results in MySQL
  ├── Exposes web dashboard
  └── Writes OSQuery results to local log
          │
          │  Filebeat (Beats protocol → TCP 5044)
          ▼
Graylog Server (Ubuntu)
  ├── Beats Input (port 5044)
  ├── OSQuery Stream (filter: tool=osquery)
  └── Search / Alerting / Dashboards
```

### Data Flow

```
[Endpoint]                [Kolide Fleet]           [Graylog]
OSQuery agent  ──HTTPS──► Fleet Manager  ──Filebeat──► Beats Input
               (query     (schedules,     (ships logs)  │
               results)    packs, hosts)                └── OSQuery Stream
                                                            └── Search & Alert
```

---

## Kolide Terms Glossary

| Term | Description |
|---|---|
| **Node** | A single enrolled machine running OSQuery |
| **Fleet** | All machines controlled by the enterprise Kolide instance |
| **Query** | A SQL statement that runs against OSQuery tables on endpoints |
| **Distributed Query** | An ad-hoc, on-the-fly query run immediately against selected hosts |
| **Pack** | A group of scheduled queries bundled together for ongoing monitoring |
| **Enroll Secret** | A shared secret used by agents to authenticate and register with Kolide |

---

## Infrastructure Requirements

| Component | Server | OS | Notes |
|---|---|---|---|
| **Kolide Fleet** | Kolide Server | Ubuntu 16.04 | MySQL, Redis, Nginx |
| **Graylog** | Graylog Server | Ubuntu 16.04 | MongoDB, Elasticsearch, Nginx |
| **OSQuery Agent** | All Endpoints | Windows / Ubuntu / CentOS | Connects to Kolide via TLS |
| **Filebeat** | Kolide Server | Ubuntu 16.04 | Ships logs to Graylog |
| **Ansible Controller** | Management host | Linux / macOS | Runs all playbooks |

---

## Part 1 — Install Kolide Fleet on Ubuntu

### Step 1 — Clone & Configure Ansible

```bash
# Clone the deployment repository
git clone https://github.com/Benster900/BlogProjects/Kolide.git
cd Kolide

# Set up global variables
mv group_vars/all.example group_vars/all
nano group_vars/all
```

Set the following values in `group_vars/all`:

```yaml
# group_vars/all
timezone: America/New_York            # Your timezone
fleet_hostname: fleet                  # Kolide Fleet subdomain
graylog_hostname: graylog              # Graylog subdomain
base_domain: yourdomain.com            # Your base domain
```

---

### Step 2 — Generate JWT Key

```bash
# Generate a random 32-byte base64 JWT key
openssl rand -base64 32

# Example output:
# kX+9vKJz3mQwZ1h6yP8lN2tRfA0cBdEuGsH4jI7oVY=

# Copy this value — you'll need it in the next step
```

---

### Step 3 — Configure Kolide Variables

```bash
# Set up Kolide-specific variables
mv group_vars/kolide.example group_vars/kolide
nano group_vars/kolide
```

Set the following in `group_vars/kolide`:

```yaml
# group_vars/kolide

# JWT signing key (paste output from openssl above)
kolide_jwt_key: "kX+9vKJz3mQwZ1h6yP8lN2tRfA0cBdEuGsH4jI7oVY="

# MySQL configuration
mysql_db: kolide
mysql_user: kolide
mysql_password: StrongDBPassword123!

# SSL Certificate info
cert_country: US
cert_state: California
cert_city: San Francisco
cert_org: YourOrganization
cert_ou: SOC
cert_email: admin@yourdomain.com
```

---

### Step 4 — Set Inventory Hosts

```bash
nano hosts
```

```ini
[kolide]
kolide ansible_ssh_host=<KOLIDE_SERVER_IP>

[graylog]
graylog ansible_ssh_host=<GRAYLOG_SERVER_IP>

[linux_agents]
ubuntu ansible_ssh_host=<LINUX_AGENT_IP>

[win_agents]
windows ansible_ssh_host=<WINDOWS_AGENT_IP>
```

---

### Step 5 — Run Ansible Playbook

```bash
# Deploy Kolide Fleet (MySQL, Redis, Kolide, Nginx, SSL)
ansible-playbook -i hosts deploy_kolide.yml -u <your_ssh_username>

# Verify deployment
ssh <your_ssh_username>@<KOLIDE_SERVER_IP>
sudo systemctl status kolide-fleet
sudo systemctl status mysql
sudo systemctl status redis
sudo systemctl status nginx
```

---

### Step 6 — Kolide Web GUI Setup

Open your browser and navigate to:

```
https://<fleet_hostname>.<base_domain>
```

#### 6.1 — Create Admin User

```
1. Enter a username
2. Enter a secure password
3. Enter your email address
4. Click "Submit"
```

#### 6.2 — Setup Organization

```
1. Enter your organization name
2. Enter organization URL (NOT the Kolide URL — your company website)
3. Click "Submit"
```

#### 6.3 — Set Kolide URL

```
1. Enter: https://<fleet_hostname>.<base_domain>
2. Click "Submit"
```

#### 6.4 — Finish

```
1. Click "Finish"
2. You now have access to the Kolide Fleet dashboard
```

---

## Part 2 — OSQuery Windows Agent Deployment

### Step 1 — Get Enroll Secret from Kolide

```
1. Browse to https://<fleet_hostname>.<base_domain>
2. Click "Add new host" (top right corner)
3. Click "Reveal secret"
4. Copy the enroll secret string
```

### Step 2 — Configure Windows Agent Variables

```bash
# Set enroll secret
nano group_vars/agents
```

```yaml
# group_vars/agents
osquery_enroll_secret: "<PASTE_ENROLL_SECRET_HERE>"
```

```bash
# Copy Kolide SSL certificate for agent TLS verification
scp <your_user>@<KOLIDE_SERVER_IP>:/etc/nginx/ssl/kolide.crt /tmp/kolide.crt

# Place into agent config
mv conf/agents/certificate.example conf/agents/certificate.crt
cat /tmp/kolide.crt > conf/agents/certificate.crt
```

### Step 3 — Configure Windows Inventory

```bash
# Set Windows agent credentials
mv group_vars/win_agents.example group_vars/win_agents
nano group_vars/win_agents
```

```yaml
# group_vars/win_agents
ansible_user: Administrator
ansible_password: <WINDOWS_ADMIN_PASSWORD>
ansible_connection: winrm
ansible_winrm_transport: basic
ansible_winrm_server_cert_validation: ignore
```

```bash
# Set Windows host IP in inventory
nano hosts
# Under [win_agents]:
# windows ansible_ssh_host=<WINDOWS_MACHINE_IP>
```

### Step 4 — Deploy Windows OSQuery Agent

```bash
# Run Windows deployment playbook
ansible-playbook -i hosts deploy_windows_osquery_agents.yml

# Verify in Kolide dashboard:
# Hosts → your Windows machine should appear as Active
```

---

## Part 3 — OSQuery Linux Agent Deployment

### Ubuntu 16.04 Desktop / Server

```bash
# Step 1 — Set Linux host IP in inventory
nano hosts
# Under [linux_agents]:
# ubuntu ansible_ssh_host=<UBUNTU_MACHINE_IP>

# Step 2 — Deploy Ubuntu OSQuery agent
ansible-playbook -i hosts deploy_linux_osquery_agents.yml -u <your_user>

# Verify agent is running on the endpoint
ssh user@<UBUNTU_MACHINE_IP>
sudo systemctl status osqueryd
sudo osqueryi "SELECT * FROM osquery_info;"
```

### CentOS 7.4

```bash
# Step 1 — Set CentOS host IP in inventory
nano hosts
# Under [linux_agents]:
# centos ansible_ssh_host=<CENTOS_MACHINE_IP>

# Step 2 — Deploy CentOS OSQuery agent
ansible-playbook -i hosts deploy_linux_osquery_agents.yml -u <your_user>

# Verify agent is running
ssh user@<CENTOS_MACHINE_IP>
sudo systemctl status osqueryd
```

### Verify Agent Enrollment in Kolide

```
Kolide Dashboard → Hosts
→ Your enrolled endpoints should appear as "Online"
→ Click on a host to view system info, labels, and query history
```

---

## Part 4 — Kolide Web GUI Features

### Creating an OSQuery Query

```
1. In Kolide Dashboard → select "Query" (left sidebar)
2. Click "New Query"
3. Configure the query:

   Name:    Get host processes
   SQL:     SELECT * FROM processes;
   Targets: All hosts

4. (Optional) Click "Run" to test immediately against live hosts
5. Click "Save" → "Save as new"

6. View saved queries:
   Query → Manage Queries
```

#### Example Useful Queries

```sql
-- All running processes
SELECT pid, name, path, cmdline, uid FROM processes;

-- All listening network ports
SELECT pid, port, protocol, address FROM listening_ports;

-- Logged-in users
SELECT username, tty, host, time FROM logged_in_users;

-- Installed software
SELECT name, version, install_location FROM programs;

-- Scheduled tasks (Windows)
SELECT name, action, path, enabled FROM scheduled_tasks;

-- Startup items
SELECT name, path, status FROM startup_items;

-- Local users
SELECT username, uid, gid, directory, shell FROM users;

-- Failed logins
SELECT username, status, time FROM last WHERE status='failed';

-- Active USB devices
SELECT vendor, model, serial, removable FROM usb_devices;

-- Kernel modules (Linux)
SELECT name, size, status FROM kernel_modules WHERE status='Live';
```

---

### Creating an OSQuery Pack

```
1. Kolide Dashboard → "Packs" (left sidebar) → "New Pack"

2. Configure the pack:
   Query Pack Title: SOC-Monitoring
   Targets:          All hosts
   Click:            "Save query pack"

3. Add queries to the pack:
   a. Click "Select query" under "Choose Query"
   b. Select "Get host processes" (or any saved query)
   c. Configure schedule:
      Interval:               300 (seconds — runs every 5 minutes)
      Platform:               All
      Minimum OSQuery version: All
      Logging:                Differential

   NOTE: Differential = OSQuery only sends data when the
         query result CHANGES. Reduces log volume significantly.

   d. Click "Save"
```

#### Pack Logging Modes

| Mode | Description | Use Case |
|---|---|---|
| **Differential** | Only sends data when results change | Process monitoring, user changes |
| **Snapshot** | Sends full result set every interval | Compliance, inventory |
| **Event** | Event-driven data (process events, file events) | Real-time alerting |

---

## Part 5 — Install Graylog on Ubuntu

### Step 1 — Deploy Graylog via Ansible

```bash
# Configure Graylog variables
mv group_vars/graylog.example group_vars/graylog
nano group_vars/graylog
```

```yaml
# group_vars/graylog

# Admin password (NO special characters: ( ) ; — these break the config)
graylog_admin_password: GraylogAdmin2024

# Optional: customize ports, Elasticsearch cluster name, etc.
```

> ⚠️ `graylog_admin_password` must **not** contain: `(`, `)`, `;`

```bash
# Set Graylog host in inventory
nano hosts
# Under [graylog]:
# graylog ansible_ssh_host=<GRAYLOG_SERVER_IP>

# Deploy Graylog (MongoDB, Elasticsearch, Graylog, Nginx)
ansible-playbook -i hosts deploy_graylog.yml -u <your_user>

# Verify services
ssh <your_user>@<GRAYLOG_SERVER_IP>
sudo systemctl status graylog-server
sudo systemctl status mongodb
sudo systemctl status elasticsearch
```

```
Access Graylog Dashboard: https://<graylog_hostname>.<base_domain>
Username: admin
Password: <graylog_admin_password>
```

---

### Step 2 — Create Graylog Input

```
1. Graylog Dashboard → System → Inputs
2. Select "Beats" from the input type dropdown
3. Click "Launch new input"
4. Configure:
   Node:          <your graylog node>
   Title:         Beats input
   Bind address:  0.0.0.0 (default)
   Port:          5044 (default)
5. Click "Save"

Verify: The input should show "Running" status
```

---

### Step 3 — Create Graylog Stream

A stream routes incoming messages to separate buckets based on field matching.

```
1. Graylog Dashboard → Streams (top menu)
2. Click "Create stream"
3. Configure:
   Title:       OSQuery stream
   Description: OSQuery results from daemons
   Index set:   Default index set
4. Click "Save"
5. Click "Start stream" next to "OSQuery stream"
```

#### Add Stream Rule

```
1. Click "Manage Rules" for "OSQuery stream"
2. Click "Add stream rule"
3. Configure:
   Field: tool
   Type:  match exactly
   Value: osquery
4. Click "Save"

Result: All messages with field "tool=osquery" will route to this stream
```

---

## Part 6 — Install Filebeat on Kolide Server

Filebeat ships OSQuery results from the Kolide server to Graylog.

```bash
# Step 1 — Enable Filebeat in the Kolide playbook
nano deploy_kolide.yml

# Uncomment this line:
# - import_tasks: roles/kolide/filebeat.yml
# Change to:
- import_tasks: roles/kolide/filebeat.yml
```

### Filebeat Configuration

```bash
# Place your Filebeat config
nano conf/filebeat/filebeat.yml
```

```yaml
# conf/filebeat/filebeat.yml
filebeat.inputs:
  - type: log
    enabled: true
    paths:
      - /var/log/kolide/*.log
    fields:
      tool: osquery           # ← REQUIRED: Graylog stream rule matches on this
      environment: production
    fields_under_root: true

output.logstash:
  hosts: ["<GRAYLOG_SERVER_IP>:5044"]

logging.level: info
logging.to_files: true
logging.files:
  path: /var/log/filebeat
  name: filebeat
  keepfiles: 7
```

> ⚠️ The `tool: osquery` field is **required** — Graylog's stream rule uses it to route messages.

```bash
# Step 2 — Redeploy Kolide playbook with Filebeat enabled
ansible-playbook -i hosts deploy_kolide.yml -u <your_user>

# Step 3 — Verify Filebeat is running on Kolide server
ssh <your_user>@<KOLIDE_SERVER_IP>
sudo systemctl status filebeat
sudo tail -f /var/log/filebeat/filebeat

# Step 4 — Verify logs arriving in Graylog
# Graylog → Streams → OSQuery stream → Search
# Should show incoming messages from Kolide endpoints
```

---

## Useful OSQuery Queries

### Security Monitoring

```sql
-- Detect new user accounts
SELECT username, uid, gid, directory, shell, description
FROM users
WHERE uid >= 1000;

-- Detect SUID binaries (Linux privilege escalation risk)
SELECT path, permissions, uid, gid
FROM file
WHERE path LIKE '/usr/%' AND permissions LIKE '%s%';

-- Active network connections
SELECT pid, local_address, local_port, remote_address, remote_port, state
FROM process_open_sockets
WHERE state = 'ESTABLISHED' AND remote_address != '0.0.0.0';

-- Cron jobs (persistence check)
SELECT event, minute, hour, day_of_month, month, command, path
FROM crontab;

-- Processes with open network connections
SELECT p.pid, p.name, p.path, s.remote_address, s.remote_port
FROM processes p
JOIN process_open_sockets s ON p.pid = s.pid
WHERE s.remote_address != '0.0.0.0' AND s.state = 'ESTABLISHED';

-- Startup items (Windows)
SELECT name, path, status, username
FROM startup_items;

-- Recently installed software (Windows)
SELECT name, version, install_date
FROM programs
ORDER BY install_date DESC;

-- Loaded kernel modules (Linux)
SELECT name, size, status, address
FROM kernel_modules
WHERE status = 'Live';
```

### Threat Hunting Packs

```sql
-- Suspicious processes (common attacker tools)
SELECT pid, name, path, cmdline
FROM processes
WHERE name IN ('nc', 'ncat', 'netcat', 'socat', 'curl', 'wget', 'python', 'python3')
  AND path NOT LIKE '/usr/%'
  AND path NOT LIKE '/bin/%';

-- DNS requests to suspicious domains
SELECT pid, name, packet_type, dns_question_name
FROM dns_resolvers;

-- Files modified in /tmp (staging area)
SELECT path, size, mtime, uid
FROM file
WHERE directory = '/tmp/'
  AND mtime > (strftime('%s', 'now') - 3600);

-- Open file handles pointing to deleted files
SELECT pid, path, type
FROM process_open_files
WHERE path LIKE '%(deleted)%';
```

---

## Troubleshooting

| Issue | Cause | Fix |
|---|---|---|
| Kolide web UI not reachable | Nginx not running or SSL error | `sudo systemctl restart nginx` + check SSL cert |
| Agents not enrolling | Wrong enroll secret or cert | Verify `osquery_enroll_secret` matches Kolide UI + re-copy `kolide.crt` |
| Filebeat not sending logs | Wrong Graylog IP or port | Check `conf/filebeat/filebeat.yml` → verify `hosts` matches Graylog Beats input |
| Graylog stream empty | Missing `tool: osquery` field | Ensure `fields: tool: osquery` is set in `filebeat.yml` + `fields_under_root: true` |
| Ansible playbook fails | SSH key issue | Use `-u <username> --ask-pass` or add SSH key to target |
| OSQuery daemon not running | Config error | `sudo osqueryd --config_path /etc/osquery/osquery.conf --verbose` |
| Windows deployment fails | WinRM not configured | Enable WinRM on Windows: `winrm quickconfig` |
| MySQL connection refused | MySQL not started | `sudo systemctl start mysql && sudo systemctl enable mysql` |

### Debug Commands

```bash
# Check Kolide Fleet logs
sudo journalctl -u kolide-fleet -f

# Check OSQuery agent logs (Linux)
sudo journalctl -u osqueryd -f
sudo osqueryi --verbose

# Check Filebeat logs
sudo tail -f /var/log/filebeat/filebeat

# Check Graylog logs
sudo journalctl -u graylog-server -f

# Test OSQuery query manually on endpoint
sudo osqueryi "SELECT pid, name, path FROM processes LIMIT 10;"

# Test Graylog Beats port is open
nc -zv <GRAYLOG_SERVER_IP> 5044
```

---

## References

| Resource | Link |
|---|---|
| 📘 Original Blog Post | [holdmybeersecurity.com](https://holdmybeersecurity.com/2018/01/16/install-setup-kolide-fleet-graylog-osquery-with-windows-and-linux-deployment/) |
| 🐙 Ansible Playbooks | [github.com/Benster900/BlogProjects](https://github.com/Benster900/BlogProjects) |
| 🔍 Kolide Fleet Docs | [github.com/kolide/fleet/docs](https://github.com/kolide/fleet/tree/master/docs) |
| 🖥️ OSQuery Docs | [osquery.io/docs](https://osquery.readthedocs.io) |
| 📊 Graylog Docs | [docs.graylog.org](https://docs.graylog.org) |
| 🚀 FleetDM (modern Kolide successor) | [fleetdm.com](https://fleetdm.com) |
