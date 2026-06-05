# 🔥 SonicWall Syslog Integration

> Complete guide for collecting **SonicWall firewall logs** via a centralized **rsyslog server** on Ubuntu Linux. Covers UDP/TCP listener setup, log directory creation, per-host log routing, file permissions, log rotation, and SIEM field mapping.

<p align="center">
  <img src="https://img.shields.io/badge/SonicWall-Firewall-EF3829?style=for-the-badge&logo=sonicwall&logoColor=white"/>
  <img src="https://img.shields.io/badge/Ubuntu-24.04-E95420?style=for-the-badge&logo=ubuntu&logoColor=white"/>
  <img src="https://img.shields.io/badge/rsyslog-UDP%20%7C%20TCP%20514-4B8BBE?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/Protocol-Syslog-blue?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/Status-Active-brightgreen?style=for-the-badge"/>
</p>

---

## Table of Contents

- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Step 1 — Install rsyslog](#step-1--install-rsyslog)
- [Step 2 — Configure UDP & TCP Listeners](#step-2--configure-udp--tcp-listeners)
- [Step 3 — Organize Logs by Host](#step-3--organize-logs-by-host)
- [Step 4 — Open Firewall Ports](#step-4--open-firewall-ports)
- [Step 5 — Restart & Verify rsyslog](#step-5--restart--verify-rsyslog)
- [Step 6 — Configure Syslog Clients](#step-6--configure-syslog-clients)
- [Step 7 — Test the Setup](#step-7--test-the-setup)
- [File Permissions](#file-permissions)
- [Log Rotation](#log-rotation)
- [References](#references)

---

## Architecture

```
SonicWall Firewall
  │
  │  UDP/TCP 514 — Syslog
  │
  ▼
Ubuntu Linux — rsyslog (Centralized Syslog Server)
  │
  ├── /var/log/sonicwall/firewall.log      ← SonicWall logs
  └── /var/log/remote/%HOSTNAME%/          ← Per-host logs (optional)
```

---

## Prerequisites

| Component | Details |
|---|---|
| **Syslog Server OS** | Ubuntu 24.04 LTS |
| **Syslog Service** | rsyslog |
| **Log Path** | `/var/log/sonicwall/firewall.log` |
| **Protocol** | UDP 514 / TCP 514 |
| **SonicWall Device** | SonicWall TZ / NSA / NSsp series |

---

## Step 1 — Install rsyslog

Update and install rsyslog:

```bash
sudo apt update
sudo apt install rsyslog -y
```

Verify it is running:

```bash
systemctl status rsyslog
```

---

## Step 2 — Configure UDP & TCP Listeners

Edit the main rsyslog configuration file:

```bash
sudo nano /etc/rsyslog.conf
```

Uncomment or add the following lines to enable both **UDP** and **TCP** reception:

```conf
# For UDP (port 514) — fast, no delivery guarantee
module(load="imudp")
input(type="imudp" port="514")

# For TCP (port 514) — slower, but reliable delivery
module(load="imtcp")
input(type="imtcp" port="514")
```

> **Recommendation:** Use **TCP** for production environments where log integrity is important. Use **UDP** where performance is the priority.

---

## Step 3 — Organize Logs by Host

### Option A — Single Log File (SonicWall Dedicated)

Create the log directory:

```bash
sudo mkdir -p /var/log/sonicwall
```

Create a dedicated rsyslog config file:

```bash
sudo nano /etc/rsyslog.d/30-sonicwall.conf
```

Add the routing rule:

```conf
# Route all SonicWall logs to a dedicated file
template(name="Soniclogs" type="string" string="/var/log/sonicwall/firewall.log")
*.* ?Soniclogs
& stop
```

Set correct permissions:

```bash
sudo touch /var/log/sonicwall/firewall.log
sudo chmod 640 /var/log/sonicwall/firewall.log
sudo chown syslog:syslog /var/log/sonicwall/firewall.log
```

Verify:

```bash
ls -la /var/log/sonicwall/firewall.log
```

Expected output:

```
-rw-r----- 1 syslog syslog 0 Jan 15 10:00 firewall.log
```

---

### Option B — Per-Host Log Directories (Multi-Device)

Create the remote log root directory:

```bash
sudo mkdir -p /var/log/remote
```

Add the per-host template to `/etc/rsyslog.d/30-sonicwall.conf`:

```conf
# Store remote logs in separate directories per hostname
$template RemoteLogs,"/var/log/remote/%HOSTNAME%/%PROGRAMNAME%.log"
*.* ?RemoteLogs
& ~
```

This creates a structure like:

```
/var/log/remote/
  ├── sonicwall-tz570/
  │   └── kernel.log
  ├── sonicwall-nsa3700/
  │   └── kernel.log
  └── client-ubuntu/
      └── syslog.log
```

---

## Step 4 — Open Firewall Ports

Allow syslog traffic through the Ubuntu firewall:

```bash
sudo ufw allow 514/udp
sudo ufw allow 514/tcp
sudo ufw reload
```

Verify the rules are active:

```bash
sudo ufw status | grep 514
```

Expected output:

```
514/udp                    ALLOW IN    Anywhere
514/tcp                    ALLOW IN    Anywhere
```

---

## Step 5 — Restart & Verify rsyslog

Validate the rsyslog configuration:

```bash
sudo rsyslogd -N1
```

Expected output:

```
rsyslogd: version X.X.X, config validation run (level 1), master config /etc/rsyslog.conf
rsyslogd: End of config validation run. Bye.
```

Restart and enable rsyslog:

```bash
sudo systemctl restart rsyslog
sudo systemctl enable rsyslog
```

Verify rsyslog is listening on port 514:

```bash
sudo ss -tulnp | grep 514
```

Expected output:

```
udp   UNCONN  0   0   0.0.0.0:514   0.0.0.0:*   users:(("rsyslogd",...))
tcp   LISTEN  0   25  0.0.0.0:514   0.0.0.0:*   users:(("rsyslogd",...))
```

---

## Step 6 — Configure Syslog Clients

On each **client machine or device**, configure it to forward logs to the syslog server.

### Linux Clients

Edit `/etc/rsyslog.conf` and add one of the following:

```conf
# Send all logs to syslog server via UDP (fast)
*.* @<SERVER_IP>:514

# Send all logs via TCP (reliable)
*.* @@<SERVER_IP>:514
```

Restart rsyslog on the client:

```bash
sudo systemctl restart rsyslog
```

### SonicWall Device Configuration

Navigate in the SonicWall admin UI:

```
Log → Syslog → Add

  Name:          Ubuntu-Syslog
  Syslog Server: <SERVER_IP>
  Port:          514
  Protocol:      UDP (or TCP)
  Syslog Format: Default / Enhanced
  Facility:      local0 (or as preferred)
```

---

## Step 7 — Test the Setup

### Send a Test Message from a Linux Client

```bash
logger "Test syslog message from client $(hostname)"
```

### Monitor the Log File on the Server

```bash
sudo tail -f /var/log/sonicwall/firewall.log

# or per-host:
sudo tail -f /var/log/remote/<client-hostname>/syslog.log
```

### Capture Packets to Verify Traffic

```bash
sudo tcpdump -ni any port 514
```

Expected output:

```
IP <SONICWALL_IP> > <SERVER_IP>: SYSLOG local0.info
```

---

## File Permissions

### ⚠️ Common Issue — Execute Bit on Log Files

A log file with permissions `rwxr-xr-x` (`755`) is **incorrect**. Log files should never have the execute bit set.

### Permission Breakdown (755 — Wrong)

```
rwx r-x r-x
 │   │   │
 │   │   └── Others : read + execute  ← Not needed for logs
 │   └────── Group  : read + execute  ← Not needed for logs
 └────────── Owner  : read + write + execute ← Execute not needed
```

### Fix — Set Correct Permissions

```bash
sudo chmod 640 /var/log/sonicwall/firewall.log
sudo chown syslog:syslog /var/log/sonicwall/firewall.log
```

### Permission Comparison

| Permission | Octal | Suitable For |
|---|---|---|
| `rw-r-----` | `640` | ✅ Log files (recommended) |
| `rw-r--r--` | `644` | ✅ Log files (if public read needed) |
| `rwxr-xr-x` | `755` | ❌ Executables/scripts — NOT log files |

---

## Log Rotation

### ⚠️ Monitor Log File Size

Log files can grow very large without rotation. A `239GB` log file is a real risk:

```
239825661949 bytes ≈ 223 GB  ← Critical — immediate action required
```

### Free Space Immediately (Truncate)

```bash
sudo truncate -s 0 /var/log/sonicwall/firewall.log
```

> This instantly reclaims disk space without deleting the file (keeps file handle open for rsyslog).

### Configure logrotate

Create a logrotate configuration file:

```bash
sudo nano /etc/logrotate.d/sonicwall
```

Add the following:

```conf
/var/log/sonicwall/firewall.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 640 syslog syslog
    sharedscripts
    postrotate
        systemctl restart rsyslog
    endscript
}
```

### logrotate Options Explained

| Option | Description |
|---|---|
| `daily` | Rotate the log file once per day |
| `rotate 7` | Keep the last 7 rotated files |
| `compress` | Gzip compress rotated files |
| `delaycompress` | Delay compression by one rotation cycle |
| `missingok` | No error if log file is missing |
| `notifempty` | Don't rotate if file is empty |
| `create 640 syslog syslog` | Create new log file with correct permissions |
| `postrotate` | Commands to run after rotation |

### Test logrotate

```bash
# Dry run (shows what would happen)
sudo logrotate --debug /etc/logrotate.d/sonicwall

# Force rotation now
sudo logrotate -f /etc/logrotate.d/sonicwall
```

### Verify Rotated Files

```bash
ls -lah /var/log/sonicwall/
```

Expected output:

```
-rw-r----- 1 syslog syslog  1.2M Jan 15 firewall.log
-rw-r----- 1 syslog syslog  45M  Jan 14 firewall.log.1
-rw-r----- 1 syslog syslog  38M  Jan 13 firewall.log.2.gz
-rw-r----- 1 syslog syslog  41M  Jan 12 firewall.log.3.gz
```

---

## Protocol Reference

| Symbol | Protocol | Port | Reliability | Use Case |
|---|---|---|---|---|
| `@` | UDP | 514 | Fast — no delivery guarantee | High-volume, low-latency |
| `@@` | TCP | 514 | Slower — reliable delivery | Production, audit logs |

### rsyslog Client Syntax

```conf
# UDP (single @)
*.* @192.168.1.100:514

# TCP (double @@)
*.* @@192.168.1.100:514

# TCP with queuing (production recommended)
*.* action(type="omfwd"
    target="192.168.1.100"
    port="514"
    protocol="tcp"
    action.resumeRetryCount="100"
    queue.type="linkedList"
    queue.size="10000")
```

---


## References

| Resource | Link |
|---|---|
| 📘 SonicWall Syslog Guide | [docs.sonicwall.com](https://www.sonicwall.com/support/knowledge-base/) |
| 🛠️ Ubuntu UFW Guide | [ubuntu.com/ufw](https://ubuntu.com/server/docs/firewalls) |
