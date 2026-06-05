# 🔥 FortiGate Syslog Integration

> Complete guide for collecting **FortiGate firewall logs** via a centralized **rsyslog server** on Ubuntu Linux. Covers listener setup, log directory creation, rsyslog rules, log reception verification, traffic analysis, and SIEM field mapping.

<p align="center">
  <img src="https://img.shields.io/badge/FortiGate-X-EE3124?style=for-the-badge&logo=fortinet&logoColor=white"/>
  <img src="https://img.shields.io/badge/Ubuntu-24.04-E95420?style=for-the-badge&logo=ubuntu&logoColor=white"/>
  <img src="https://img.shields.io/badge/rsyslog-UDP%20514-4B8BBE?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/Protocol-Syslog-blue?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/Status-Active-brightgreen?style=for-the-badge"/>
</p>

---

## Table of Contents

- [Architecture](#architecture)
- [Environment](#environment)
- [Step 1 — Install rsyslog](#step-1--install-rsyslog)
- [Step 2 — Enable UDP Syslog Listener](#step-2--enable-udp-syslog-listener)
- [Step 3 — Create FortiGate Log Directory](#step-3--create-fortigate-log-directory)
- [Step 4 — Configure rsyslog Routing Rule](#step-4--configure-rsyslog-routing-rule)
- [Step 5 — Verify Log Reception](#step-5--verify-log-reception)
- [Step 6 — FortiGate Log Analysis](#step-6--fortigate-log-analysis)
- [Traffic Direction Logic](#traffic-direction-logic)

---

## Architecture

```
FortiGate
  │
  │  UDP 514 / Syslog / Facility: local7
  │
  ▼
Ubuntu Linux — rsyslog
  │
  │  Writes to
  ▼
/var/log/fortigate/firewall.log
  │
  ▼
SIEM / Dashboard (next integration)
```

---

## Environment

### Syslog Server

| Parameter | Value |
|---|---|
| **Operating System** | Ubuntu Linux |
| **Syslog Service** | rsyslog |
| **Log Storage Path** | `/var/log/fortigate/firewall.log` |
| **Protocol** | UDP |
| **Port** | 514 |

### FortiGate Firewall

| Parameter | Value |
|---|---|
| **Device** | FortiGate  |
| **Log Forwarding** | Syslog |
| **Protocol** | UDP |
| **Port** | 514 |
| **Facility** | local7 |

---

## Step 1 — Install rsyslog

Verify rsyslog is installed:

```bash
systemctl status rsyslog
```

Install if required:

```bash
sudo apt update
sudo apt install rsyslog -y
```

---

## Step 2 — Enable UDP Syslog Listener

Edit the rsyslog configuration:

```bash
sudo nano /etc/rsyslog.conf
```

Uncomment or add the following lines to enable UDP listener:

```conf
module(load="imudp")
input(type="imudp" port="514")
```

Restart the service:

```bash
sudo systemctl restart rsyslog
```

Verify the listener is active:

```bash
sudo ss -ulpn | grep 514
```

Expected output:

```
UNCONN  0  0  0.0.0.0:514   0.0.0.0:*
UNCONN  0  0     [::]:514      [::]:*
```

---

## Step 3 — Create FortiGate Log Directory

Create the log directory:

```bash
sudo mkdir -p /var/log/fortigate
```

Set correct ownership and permissions:

```bash
sudo chown -R syslog:adm /var/log/fortigate
sudo chmod 755 /var/log/fortigate
```

Create the log file with correct ownership:

```bash
sudo touch /var/log/fortigate/firewall.log
sudo chown syslog:adm /var/log/fortigate/firewall.log
```

Verify:

```bash
ls -la /var/log/fortigate
```

Expected output:

```
-rw-r--r-- 1 syslog adm firewall.log
```

---

## Step 4 — Configure rsyslog Routing Rule

Create a dedicated FortiGate rsyslog configuration file:

```bash
sudo nano /etc/rsyslog.d/30-fortigate.conf
```

Add the routing rule:

```conf
# Route all local7 facility logs to FortiGate log file
local7.*    /var/log/fortigate/firewall.log
& stop
```

> The `& stop` directive prevents the log from being duplicated in other log files (e.g. `/var/log/syslog`).

Validate the rsyslog configuration:

```bash
sudo rsyslogd -N1
```

Expected output:

```
rsyslogd: version X.X.X, config validation run (level 1), master config /etc/rsyslog.conf
rsyslogd: End of config validation run. Bye.
```

Restart rsyslog to apply changes:

```bash
sudo systemctl restart rsyslog
```

---

## Step 5 — Verify Log Reception

### Monitor the Log File

Watch for incoming FortiGate logs in real time:

```bash
sudo tail -f /var/log/fortigate/firewall.log
```

### Capture Network Packets

Verify FortiGate is sending UDP syslog packets:

```bash
sudo tcpdump -ni any port 514
```

Expected output:

```
IP 192.168.1.99 > <SYSLOG_SERVER_IP>: SYSLOG local7.notice
```

This confirms the FortiGate device is successfully forwarding logs to the syslog server.

---

## Step 6 — FortiGate Log Analysis

### Sample Log Event

```
date=2024-01-15 time=10:23:41 devname="FG" devid="FGXXXXXXXXXX"
type="traffic" subtype="local"
srcip=193.24.123.29 srcport=54321 srcintfrole="wan"
dstip=71.34.342.123 dstport=10443 dstintfrole="lan"
proto=6 action="server-rst" policyid=0
service="HTTPS" sentbyte=2048 rcvdbyte=1024
srccountry="Russian Federation" dstcountry="India"
```

### Event Interpretation

| Field | Value | Meaning |
|---|---|---|
| `type` | `traffic` | Firewall traffic log |
| `subtype` | `local` | Local firewall traffic |
| `srcip` | `193.24.123.29` | Source IP address |
| `dstip` | `71.34.342.123` | Destination IP address |
| `dstport` | `10443` | Destination port (custom HTTPS) |
| `action` | `server-rst` | Server sent TCP Reset |
| `srccountry` | `Russian Federation` | Source GeoIP |
| `dstcountry` | `India` | Destination GeoIP |

---

### Was Traffic Allowed?

**Yes.**

```
action="server-rst"
```

The connection was **accepted and established**. The FortiGate later terminated the session by sending a TCP Reset (RST) packet — this is a normal TCP session closure, not a block.

---

### Was Traffic Blocked?

**No.**

Blocked traffic contains one of the following action values:

```
action="deny"
action="blocked"
action="drop"
```

---

## Traffic Direction Logic

### Determining Direction from Log Fields

| Condition | Direction |
|---|---|
| `srcintfrole="wan"` + `dstintfrole="lan"` | **Inbound** (Internet → Internal) |
| `srcintfrole="lan"` + `dstintfrole="wan"` | **Outbound** (Internal → Internet) |
| `subtype="local"` + `srcintf="wan1"` | **Inbound to Firewall** |
| `subtype="local"` + `dstintf="root"` | **Inbound to Firewall** |

### Inbound Traffic Examples

```
# Interface-based detection
srcintfrole="wan"
dstintfrole="lan"

# Subtype-based detection
subtype="local"
srcintf="wan1"
dstintf="root"
```

### Outbound Traffic Examples

```
srcintfrole="lan"
dstintfrole="wan"
```

### Custom Field Logic

```
IF srcintfrole = "wan"  → traffic_direction = "inbound"
IF dstintfrole = "wan"  → traffic_direction = "outbound"
IF subtype     = "local" → traffic_direction = "inbound_to_firewall"
```

---

## Recommended SIEM Fields

The following fields should be extracted and parsed when ingesting FortiGate logs into any SIEM or log analysis platform:

### Core Fields

| Field | Type | Description |
|---|---|---|
| `time` | Timestamp | Log event timestamp |
| `devname` | String | FortiGate device name |
| `devid` | String | FortiGate device serial number |
| `type` | String | Log type (traffic, utm, event, etc.) |
| `subtype` | String | Log subtype (local, forward, etc.) |
| `action` | String | Firewall action (allow, deny, drop, server-rst) |
| `service` | String | Application service (HTTP, HTTPS, DNS, etc.) |
| `proto` | Integer | IP protocol number (6=TCP, 17=UDP, 1=ICMP) |
| `policyid` | Integer | Firewall policy rule ID |
| `policytype` | String | Type of policy matched |

### Network Fields

| Field | Type | Description |
|---|---|---|
| `srcip` | IP | Source IP address |
| `srcport` | Integer | Source port |
| `dstip` | IP | Destination IP address |
| `dstport` | Integer | Destination port |
| `srcintf` | String | Source interface name |
| `dstintf` | String | Destination interface name |

### Geo & Traffic Volume

| Field | Type | Description |
|---|---|---|
| `srccountry` | String | Source country (GeoIP) |
| `dstcountry` | String | Destination country (GeoIP) |
| `sentbyte` | Integer | Bytes sent |
| `rcvdbyte` | Integer | Bytes received |
| `sentpkt` | Integer | Packets sent |
| `rcvdpkt` | Integer | Packets received |

### Custom Enrichment Field

| Field | Logic | Values |
|---|---|---|
| `traffic_direction` | Derived from `srcintfrole` / `dstintfrole` / `subtype` | `inbound` / `outbound` / `inbound_to_firewall` |

---


## References

| Resource | Link |
|---|---|
| 📘 FortiGate Log Reference | [docs.fortinet.com](https://docs.fortinet.com/document/fortigate/7.4.0/log-message-reference) |
| 🔧 rsyslog Documentation | [rsyslog.com/doc](https://www.rsyslog.com/doc/) |
| 🌐 FortiGate Syslog Config | [docs.fortinet.com/syslog](https://docs.fortinet.com/document/fortigate/7.4.0/administration-guide/327603) |
| 📊 FortiGate Traffic Log Fields | [docs.fortinet.com/traffic](https://docs.fortinet.com/document/fortigate/7.4.0/log-message-reference/357866) |
