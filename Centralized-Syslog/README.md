# 📡 Centralized Syslog Server — rsyslog on Ubuntu

> Complete guide for setting up a **centralized syslog server** using **rsyslog** on Ubuntu Linux. Collects logs from any network device or Linux/Windows client via UDP/TCP on port 514. Covers listener setup, per-host log routing, firewall rules, client configuration, file permissions, log rotation, and testing.

<p align="center">
  <img src="https://img.shields.io/badge/Ubuntu-24.04-E95420?style=for-the-badge&logo=ubuntu&logoColor=white"/>
  <img src="https://img.shields.io/badge/rsyslog-Latest-4B8BBE?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/Protocol-UDP%20%7C%20TCP%20514-blue?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/Status-Active-brightgreen?style=for-the-badge"/>
</p>

---
<p align="center">
  <a href="https://github.com/syslog-ng/syslog-ng">
    <img src="https://grafana.com/mw/_next/image/?url=https%3A%2F%2Fs3.amazonaws.com%2Fa-us.storyblok.com%2Ff%2F1022730%2Fe76e4f5522%2Fsyslogloki1.png&w=1152&q=75"
         alt="Syslog-NG"
         width="2500">
  </a>
</p>

## Table of Contents

- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Step 1 — Install rsyslog](#step-1--install-rsyslog)
- [Step 2 — Configure UDP & TCP Listeners](#step-2--configure-udp--tcp-listeners)
- [Step 3 — Organize Logs by Client](#step-3--organize-logs-by-client)
- [Step 4 — Open Firewall Ports](#step-4--open-firewall-ports)
- [Step 5 — Restart & Verify rsyslog](#step-5--restart--verify-rsyslog)
- [Step 6 — Configure Syslog Clients](#step-6--configure-syslog-clients)
- [Step 7 — Test the Setup](#step-7--test-the-setup)
- [File Permissions](#file-permissions)
- [Log Rotation](#log-rotation)
- [Protocol Reference](#protocol-reference)
- [References](#references)

---

## Architecture

```
Client Machines / Network Devices
  ├── Linux Servers
  ├── Windows Machines
  ├── Firewalls (SonicWall, FortiGate, pfSense)
  ├── Routers & Switches
  └── Any Syslog-capable Device
       │
       │  UDP/TCP port 514
       ▼
Ubuntu Linux — rsyslog (Centralized Syslog Server)
  │
  ├── /var/log/sonicwall/firewall.log       ← Dedicated device log
  └── /var/log/remote/%HOSTNAME%/           ← Per-host log directory
```

---

## Prerequisites

| Parameter | Value |
|---|---|
| **Syslog Server OS** | Ubuntu Linux (20.04 / 22.04 / 24.04) |
| **Syslog Service** | rsyslog |
| **Default Log Path** | `/var/log/syslog` |
| **Custom Log Path** | `/var/log/remote/%HOSTNAME%/` |
| **Protocols** | UDP 514 / TCP 514 |

---

## Step 1 — Install rsyslog

Update the package list and install rsyslog:

```bash
sudo apt update
sudo apt install rsyslog -y
```

Verify rsyslog is running:

```bash
systemctl status rsyslog
```

---

## Step 2 — Configure UDP & TCP Listeners

Edit the main rsyslog configuration file:

```bash
sudo nano /etc/rsyslog.conf
```

Uncomment or add the following lines to enable **UDP** and/or **TCP** reception:

```conf
# ── UDP (port 514) — fast, no delivery guarantee ──
module(load="imudp")
input(type="imudp" port="514")

# ── TCP (port 514) — slower, but reliable ──
module(load="imtcp")
input(type="imtcp" port="514")
```

> **Tip:** Enable both protocols to support the widest range of client devices.

---

## Step 3 — Organize Logs by Client

Choose one of the following routing strategies depending on your environment.

---

### Option A — Single Dedicated Log File (Per Device Type)

Best for a **single device** or device type (e.g. one SonicWall firewall).

Create the log directory:

```bash
sudo mkdir -p /var/log/sonicwall
sudo touch /var/log/sonicwall/firewall.log
sudo chmod 640 /var/log/sonicwall/firewall.log
sudo chown syslog:syslog /var/log/sonicwall/firewall.log
```

Create a dedicated rsyslog config file:

```bash
sudo nano /etc/rsyslog.d/30-firewall.conf
```

Add the routing rule:

```conf
# Route all incoming syslog to dedicated firewall log
template(name="Firewalllogs" type="string" string="/var/log/sonicwall/firewall.log")
*.* ?Firewalllogs
& stop
```

> The `& stop` directive prevents log duplication in `/var/log/syslog`.

---

### Option B — Per-Host Log Directories (Multi-Device)

Best for **multiple clients** — each device/host gets its own directory.

Create the remote log root:

```bash
sudo mkdir -p /var/log/remote
```

Create or edit the config file:

```bash
sudo nano /etc/rsyslog.d/30-remote.conf
```

Add the per-host template:

```conf
# Store remote logs in separate directories per hostname
$template RemoteLogs,"/var/log/remote/%HOSTNAME%/%PROGRAMNAME%.log"
*.* ?RemoteLogs
& ~
```

This creates a structure like:

```
/var/log/remote/
  ├── sonicwall-fw01/
  │   └── kernel.log
  ├── fortigate-60f/
  │   └── kernel.log
  ├── ubuntu-server01/
  │   └── sshd.log
  └── windows-dc01/
      └── security.log
```

---

## Step 4 — Open Firewall Ports

Allow syslog traffic through UFW:

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

Validate the configuration syntax:

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
udp  UNCONN  0  0  0.0.0.0:514  0.0.0.0:*  users:(("rsyslogd",...))
tcp  LISTEN  0  25 0.0.0.0:514  0.0.0.0:*  users:(("rsyslogd",...))
```

---

## Step 6 — Configure Syslog Clients

### Linux Clients

Edit `/etc/rsyslog.conf` on each client machine:

```bash
sudo nano /etc/rsyslog.conf
```

Add one of the following lines:

```conf
# Send all logs via UDP (fast)
*.* @<SERVER_IP>:514

# Send all logs via TCP (reliable — recommended)
*.* @@<SERVER_IP>:514
```

Restart rsyslog on the client:

```bash
sudo systemctl restart rsyslog
```

---

### Network Devices (Firewalls, Switches, Routers)

Configure syslog forwarding in the device admin UI:

```
Syslog Server IP:   <SERVER_IP>
Port:               514
Protocol:           UDP or TCP
Facility:           local0 to local7 (as preferred)
Severity:           Informational or higher
```

> Every vendor has a different UI path. Check your device documentation for the exact location of syslog settings.

---

## Step 7 — Test the Setup

### Send a Test Message from a Linux Client

```bash
logger "Test syslog message from $(hostname)"
```

### Monitor Logs on the Server

```bash
# Default syslog
sudo tail -f /var/log/syslog

# Dedicated device log (Option A)
sudo tail -f /var/log/sonicwall/firewall.log

# Per-host directory (Option B)
sudo tail -f /var/log/remote/<client-hostname>/syslog.log
```

### Capture Network Packets

```bash
sudo tcpdump -ni any port 514
```

Expected output when a client sends logs:

```
IP <CLIENT_IP>.<PORT> > <SERVER_IP>.514: SYSLOG local0.info, length: 87
```

---

## File Permissions

### ⚠️ Common Issue — Execute Bit on Log Files

Log files with permissions `755` (`rwxr-xr-x`) are **incorrect**. Log files should **never** have the execute bit set.

### Permission Breakdown (755 — Wrong ❌)

```
rwx  r-x  r-x
 │    │    └── Others : read + execute  ← unnecessary
 │    └─────── Group  : read + execute  ← unnecessary
 └──────────── Owner  : read + write + execute ← execute not needed
```

### Fix Permissions

```bash
sudo chmod 640 /var/log/sonicwall/firewall.log
sudo chown syslog:syslog /var/log/sonicwall/firewall.log
```

### Permission Reference

| Permission | Octal | Suitable For |
|---|---|---|
| `rw-r-----` | `640` | ✅ Log files (recommended) |
| `rw-r--r--` | `644` | ✅ Log files (if public read needed) |
| `rwxr-xr-x` | `755` | ❌ Executables only — not log files |

---

## Log Rotation

### ⚠️ Monitor Log File Size

Without rotation, log files can grow to hundreds of gigabytes:

```
239825661949 bytes ≈ 223 GB  ← Critical — requires immediate action
```

### Emergency — Truncate Immediately (Free Space Now)

```bash
sudo truncate -s 0 /var/log/sonicwall/firewall.log
```

> This instantly frees disk space without deleting the file or breaking the rsyslog file handle.

---

### Configure logrotate

Create a logrotate configuration:

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
| `daily` | Rotate once per day |
| `rotate 7` | Keep last 7 rotated files |
| `compress` | Gzip compress old files |
| `delaycompress` | Delay compression by one cycle |
| `missingok` | No error if log file is missing |
| `notifempty` | Skip rotation if file is empty |
| `create 640 syslog syslog` | Create new log file with correct permissions |
| `postrotate` | Restart rsyslog after rotation |

### Test logrotate

```bash
# Dry run — shows what would happen
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
-rw-r----- 1 syslog syslog   45M Jan 14 firewall.log.1
-rw-r----- 1 syslog syslog   38M Jan 13 firewall.log.2.gz
-rw-r----- 1 syslog syslog   41M Jan 12 firewall.log.3.gz
```

---

## Protocol Reference

| Symbol | Protocol | Port | Reliability | Best For |
|---|---|---|---|---|
| `@` | UDP | 514 | Fast — no delivery guarantee | High-volume, performance-critical |
| `@@` | TCP | 514 | Reliable — guaranteed delivery | Production, audit, compliance |

### Advanced TCP with Queue (Production)

For high-reliability production environments, add queue support:

```conf
*.* action(type="omfwd"
    target="<SERVER_IP>"
    port="514"
    protocol="tcp"
    action.resumeRetryCount="100"
    queue.type="linkedList"
    queue.size="10000")
```

This queues logs locally if the server is temporarily unreachable and retries automatically.

---

## References

| Resource | Link |
|---|---|
| 🔧 rsyslog Documentation | [rsyslog.com/doc](https://www.rsyslog.com/doc/) |
| 📘 rsyslog Templates | [rsyslog.com/templates](https://www.rsyslog.com/doc/v8-stable/configuration/templates.html) |
| 🔄 logrotate Manual | `man logrotate` |
| 🛡️ Ubuntu UFW Guide | [ubuntu.com/ufw](https://ubuntu.com/server/docs/firewalls) |
| 📋 Syslog RFC 5424 | [tools.ietf.org/rfc5424](https://tools.ietf.org/html/rfc5424) |
