# 🖥️ Windows Enterprise Endpoint Observability Stack

> Complete deployment guide for a **full-stack observability and security monitoring solution** on Windows Server endpoints. Combines **Wazuh** (security events), **Grafana Alloy** (metrics), and **Fluent Bit** (application logs) to deliver unified visibility across security, performance, and application telemetry.

<p align="center">
  <img src="https://img.shields.io/badge/Windows_Server-2025%20%7C%202022-0078D4?style=for-the-badge&logo=windows&logoColor=white"/>
  <img src="https://img.shields.io/badge/Wazuh-4.14.5-006DFF?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/Fluent_Bit-v5.0.3-49BDA5?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/Grafana_Alloy-Latest-F46800?style=for-the-badge&logo=grafana&logoColor=white"/>
  <img src="https://img.shields.io/badge/Loki-Latest-F7A600?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/Prometheus-Latest-E6522C?style=for-the-badge&logo=prometheus&logoColor=white"/>
</p>

---

## Table of Contents

- [Architecture](#architecture)
- [Stack Components](#stack-components)
- [Component 1 — Wazuh Agent (Security Events)](#component-1--wazuh-agent-security-events)
- [Component 2 — Grafana Alloy (Metrics → Prometheus)](#component-2--grafana-alloy-metrics--prometheus)
- [Component 3 — Fluent Bit (Application Logs → Loki)](#component-3--fluent-bit-application-logs--loki)
  - [Application Logs](#application-logs)
- [Fluent Bit Full Config](#fluent-bit-full-config)
- [Grafana Alloy Full Config](#grafana-alloy-full-config)
- [Grafana Dashboards](#grafana-dashboards)
- [Log Sources Reference](#log-sources-reference)
- [References](#references)

---

## Architecture

```
Windows Server (Enterprise Endpoint)
  │
  ├─── Wazuh Agent
  │      └── Security Events (Windows Event Log)
  │            └──────────────────────────────────► Wazuh Manager
  │                                                      └── OpenSearch / Wazuh Dashboard
  │
  ├─── Grafana Alloy
  │      └── System Metrics (CPU / RAM / Disk / Network)
  │            └──────────────────────────────────► Prometheus
  │                                                      └── Grafana
  │
  └─── Fluent Bit
         ├── FortiClient Logs
         ├── TeamViewer Logs
         ├── Action1 RMM Logs
         └── Windows Application Logs
               └──────────────────────────────────► Loki
                                                       └── Grafana
```

### Data Flow Summary

```
SECURITY LAYER   →  Wazuh Agent   →  Wazuh Manager  →  OpenSearch  →  Wazuh Dashboard
METRICS LAYER    →  Alloy         →  Prometheus      →  Grafana
LOG LAYER        →  Fluent Bit    →  Loki            →  Grafana
```

---

## Stack Components

| Component | Role | Output | Dashboard |
|---|---|---|---|
| **Wazuh Agent** | Security event collection — Windows Event Logs, FIM, vulnerability scan | Wazuh Manager → OpenSearch | Wazuh Dashboard |
| **Grafana Alloy** | System metrics — CPU, RAM, disk, network, Windows services | Prometheus (remote write) | Grafana |
| **Fluent Bit** | Application log collection — FortiClient, TeamViewer, Action1, app logs | Loki | Grafana |

---

## Component 1 — Wazuh Agent (Security Events)

### What It Collects

```
Windows Event Log — Security Channel
  ├── Logon / Logoff events        (Event ID 4624, 4625, 4634)
  ├── Account management           (Event ID 4720, 4722, 4740)
  ├── Privilege use                (Event ID 4672, 4673)
  ├── Process creation             (Event ID 4688)
  ├── Object access                (Event ID 4663)
  ├── Policy changes               (Event ID 4719)
  └── PowerShell execution         (Event ID 4103, 4104)

Windows Event Log — System Channel
  ├── Service start / stop
  ├── Driver errors
  └── OS events

File Integrity Monitoring (FIM)
  └── Critical directory changes

Vulnerability Assessment
  └── Installed software CVE scan
```


### ossec.conf — Windows Event Log Channels

Edit `C:\Program Files (x86)\ossec-agent\ossec.conf` to collect additional channels:

```xml
<ossec_config>

  <!-- Security Events -->
  <localfile>
    <location>Security</location>
    <log_format>eventchannel</log_format>
  </localfile>

  <!-- System Events -->
  <localfile>
    <location>System</location>
    <log_format>eventchannel</log_format>
  </localfile>

  <!-- Application Events -->
  <localfile>
    <location>Application</location>
    <log_format>eventchannel</log_format>
  </localfile>

  <!-- PowerShell Operational -->
  <localfile>
    <location>Microsoft-Windows-PowerShell/Operational</location>
    <log_format>eventchannel</log_format>
  </localfile>

  <!-- Sysmon (if installed) -->
  <localfile>
    <location>Microsoft-Windows-Sysmon/Operational</location>
    <log_format>eventchannel</log_format>
  </localfile>

  <!-- Task Scheduler -->
  <localfile>
    <location>Microsoft-Windows-TaskScheduler/Operational</location>
    <log_format>eventchannel</log_format>
  </localfile>

  <!-- Windows Defender -->
  <localfile>
    <location>Microsoft-Windows-Windows Defender/Operational</location>
    <log_format>eventchannel</log_format>
  </localfile>

</ossec_config>
```

---

## Component 2 — Grafana Alloy (Metrics → Prometheus)

### What It Collects

```
System Metrics
  ├── CPU usage (per core)
  ├── Memory usage (RAM / pagefile)
  ├── Disk usage (per volume)
  ├── Disk I/O (read/write bytes per second)
  ├── Network I/O (bytes in/out per interface)
  ├── System uptime
  └── Running process count

Windows-Specific Metrics
  ├── Windows Services status
  ├── IIS request metrics (if installed)
  ├── MSSQL metrics (if installed)
  └── Windows Update pending count
```

### Install Grafana Alloy

```powershell
# Download Alloy installer
Invoke-WebRequest `
  -Uri "https://github.com/grafana/alloy/releases/latest/download/alloy-installer-windows-amd64.exe" `
  -OutFile "$env:TEMP\alloy-installer.exe"

# Silent install
Start-Process "$env:TEMP\alloy-installer.exe" -ArgumentList "/S" -Wait

# Verify install
& "C:\Program Files\GrafanaLabs\Alloy\alloy.exe" --version
```

### Configure Alloy

Edit `C:\Program Files\GrafanaLabs\Alloy\config.alloy`:

```hcl
// ─── WINDOWS METRICS ─────────────────────────────────────────

prometheus.exporter.windows "default" {
  enabled_collectors = [
    "cpu",
    "memory",
    "logical_disk",
    "net",
    "os",
    "service",
    "system",
    "process",
    "pagefile",
  ]
}

prometheus.scrape "windows" {
  targets    = prometheus.exporter.windows.default.targets
  forward_to = [prometheus.remote_write.main.receiver]
  scrape_interval = "30s"
}

// ─── REMOTE WRITE TO PROMETHEUS ──────────────────────────────

prometheus.remote_write "main" {
  endpoint {
    url = "http://<PROMETHEUS_IP>:9090/api/v1/write"
  }
}
```

## Component 3 — Fluent Bit (Application Logs → Loki)

### Install Fluent Bit

```powershell
# Download
Invoke-WebRequest `
  -Uri "https://packages.fluentbit.io/windows/fluent-bit-5.0.3-win64.exe" `
  -OutFile "$env:TEMP\fluent-bit-installer.exe"

# Install (silent)
Start-Process "$env:TEMP\fluent-bit-installer.exe" `
  -ArgumentList "/S" -Wait

# Default install path: C:\Program Files\fluent-bit\
```

### Register Fluent Bit as Windows Service

```powershell
# Remove stale service if exists
Stop-Service fluent-bit -ErrorAction SilentlyContinue
sc.exe delete fluent-bit

# Create service
New-Service `
  -Name "fluent-bit" `
  -BinaryPathName '"C:\Program Files\fluent-bit\bin\fluent-bit.exe" -c "C:\Program Files\fluent-bit\conf\fluent-bit.conf"' `
  -DisplayName "Fluent Bit" `
  -Description "Fluent Bit Log Collector" `
  -StartupType Automatic

# Start
Start-Service fluent-bit

# Auto-restart on failure
sc.exe failure fluent-bit reset= 86400 actions= restart/5000/restart/5000/restart/5000
```

---


### Application Logs

General Windows application logs:

```
C:\inetpub\logs\LogFiles\          ← IIS web server logs
C:\Program Files\**\*.log          ← Installed application logs
C:\ProgramData\**\*.log            ← Application data logs
C:\Windows\Logs\                   ← Windows component logs
  ├── CBS\CBS.log                  ← Component-based servicing
  ├── DISM\dism.log                ← Deployment imaging
  └── WindowsUpdate.log            ← Windows Update
```

**Fluent Bit INPUT blocks:**

```ini
[INPUT]
    Name              tail
    Path              C:\inetpub\logs\LogFiles\*\*.log
    Tag               app.iis
    Refresh_Interval  10
    DB                C:\Program Files\fluent-bit\db\iis.db

[INPUT]
    Name              tail
    Path              C:\Windows\Logs\CBS\CBS.log
    Tag               windows.cbs
    Refresh_Interval  60

[INPUT]
    Name              tail
    Path              C:\Windows\Logs\WindowsUpdate.log
    Tag               windows.update
    Refresh_Interval  60

[INPUT]
    Name              tail
    Path              C:\Program Files\**\*.log
    Tag               app.programfiles
    Refresh_Interval  30

[INPUT]
    Name              tail
    Path              C:\ProgramData\**\*.log
    Tag               app.programdata
    Refresh_Interval  30
```

---

## Fluent Bit Full Config

Open the config file:

```powershell
notepad "C:\Program Files\fluent-bit\conf\fluent-bit.conf"
```

Replace with the complete configuration:

```ini
[SERVICE]
    flush           5
    daemon          Off
    log_level       info
    parsers_file    parsers.conf
    plugins_file    plugins.conf
    http_server     Off
    storage.metrics on

# ─── WINDOWS EVENT LOGS ───────────────────────────────────────

[INPUT]
    Name         winlog
    Channels     Security
    Interval_Sec 1
    Tag          windows.security

[INPUT]
    Name         winlog
    Channels     System
    Interval_Sec 1
    Tag          windows.system

[INPUT]
    Name         winlog
    Channels     Application
    Interval_Sec 1
    Tag          windows.application

[INPUT]
    Name         winlog
    Channels     Windows PowerShell
    Interval_Sec 1
    Tag          windows.powershell

# ─── TEAMVIEWER LOGS ──────────────────────────────────────────

[INPUT]
    Name              tail
    Path              C:\Program Files\TeamViewer\TeamViewer*_Logfile.log
    Tag               teamviewer.app
    Path_Key          filename
    Refresh_Interval  5
    Skip_Long_Lines   On
    DB                C:\Program Files\fluent-bit\db\teamviewer.db

[INPUT]
    Name              tail
    Path              C:\Program Files\TeamViewer\Connections_incoming.txt
    Tag               teamviewer.connections
    Refresh_Interval  10
    DB                C:\Program Files\fluent-bit\db\teamviewer_conn.db

# ─── ACTION1 LOGS ─────────────────────────────────────────────

[INPUT]
    Name              tail
    Path              C:\ProgramData\Action1\logs\*.log
    Tag               action1.*
    Path_Key          filename
    Refresh_Interval  10
    Skip_Long_Lines   On
    DB                C:\Program Files\fluent-bit\db\action1.db

# ─── APPLICATION LOGS ─────────────────────────────────────────

[INPUT]
    Name              tail
    Path              C:\inetpub\logs\LogFiles\*\*.log
    Tag               app.iis
    Refresh_Interval  10
    DB                C:\Program Files\fluent-bit\db\iis.db

[INPUT]
    Name              tail
    Path              C:\Windows\Logs\CBS\CBS.log
    Tag               windows.cbs
    Refresh_Interval  60

[INPUT]
    Name              tail
    Path              C:\Windows\Logs\WindowsUpdate.log
    Tag               windows.update
    Refresh_Interval  60

[INPUT]
    Name              tail
    Path              C:\Program Files\**\*.log
    Tag               app.programfiles
    Refresh_Interval  30

[INPUT]
    Name              tail
    Path              C:\ProgramData\**\*.log
    Tag               app.programdata
    Refresh_Interval  30

# ─── FILTERS — ADD HOSTNAME LABEL ─────────────────────────────

[FILTER]
    Name    record_modifier
    Match   *
    Record  hostname ${COMPUTERNAME}
    Record  os       windows

# ─── OUTPUT → LOKI ────────────────────────────────────────────

[OUTPUT]
    Name              loki
    Match             *
    Host              <LOKI_IP>
    Port              3100
    Labels            job=fluent-bit, host=${COMPUTERNAME}
    Label_Keys        $filename,$tag
    Line_Format       json
    Auto_Kubernetes_Labels off
```

Create the database directory and restart:

```powershell
New-Item -ItemType Directory -Path "C:\Program Files\fluent-bit\db" -Force
Restart-Service fluent-bit
Get-Service fluent-bit
```

---

## Grafana Alloy Full Config

Complete `config.alloy` for Windows metrics:

```hcl
// ─── WINDOWS EXPORTER ────────────────────────────────────────

prometheus.exporter.windows "windows_metrics" {
  enabled_collectors = [
    "cpu",
    "cs",
    "logical_disk",
    "memory",
    "net",
    "os",
    "pagefile",
    "process",
    "service",
    "system",
    "time",
    "tcp",
  ]
}

// ─── SCRAPE CONFIG ────────────────────────────────────────────

prometheus.scrape "windows" {
  targets         = prometheus.exporter.windows.windows_metrics.targets
  forward_to      = [prometheus.remote_write.prometheus.receiver]
  scrape_interval = "30s"
  scrape_timeout  = "10s"

  // Add hostname label
  extra_metrics_labels = {
    hostname = env("COMPUTERNAME"),
    os       = "windows",
  }
}

// ─── REMOTE WRITE ─────────────────────────────────────────────

prometheus.remote_write "prometheus" {
  endpoint {
    url = "http://<PROMETHEUS_IP>:9090/api/v1/write"

    queue_config {
      capacity             = 2500
      max_shards           = 200
      max_samples_per_send = 500
    }
  }
}
```

Restart Alloy after changes:

```powershell
Restart-Service Alloy
Get-Service Alloy
```

---

## Grafana Dashboards

### Recommended Dashboards

| Dashboard | Source | Use Case |
|---|---|---|
| **Windows Node Exporter** | Grafana ID: 14694 | CPU, RAM, disk, network metrics |
| **Windows Services** | Grafana ID: 10467 | Service health monitoring |
| **Loki Log Explorer** | Built-in | Query all application logs |

### Loki LogQL Queries for Grafana

```logql


# Action1 script executions
{job="fluent-bit"} |= "script executed" | json | tag =~ "action1"

# FortiClient malware detections
{job="fluent-bit"} |= "virus_detected" | json

# Windows logon failures (from Fluent Bit winlog)
{job="fluent-bit"} | json | tag="windows.security" |= "4625"

# All errors across all sources
{job="fluent-bit", host="<HOSTNAME>"} |= "error" | json
```

---

## Log Sources Reference

| Tag | Source Path | Application | Key Events |
|---|---|---|---|
| `windows.security` | Windows Event Log | Windows OS | Logon, logoff, privilege use, account changes |
| `windows.system` | Windows Event Log | Windows OS | Hardware, drivers, service events |
| `windows.application` | Windows Event Log | Windows OS | App errors, crashes, warnings |
| `windows.powershell` | Windows Event Log | PowerShell | Script execution, commands run |
| `app.iis` | `C:\inetpub\logs\` | IIS | Web requests, errors, status codes |
| `windows.update` | `C:\Windows\Logs\WindowsUpdate.log` | Windows Update | Update installs, failures |
| `app.programfiles` | `C:\Program Files\**\*.log` | All apps | Generic application logs |
| `app.programdata` | `C:\ProgramData\**\*.log` | All apps | App data / service logs |

---


## References

| Resource | Link |
|---|---|
| 📘 Wazuh Windows Agent | [documentation.wazuh.com/windows](https://documentation.wazuh.com/current/installation-guide/wazuh-agent/wazuh-agent-package-windows.html) |
| 🔧 Fluent Bit Windows | [docs.fluentbit.io/windows](https://docs.fluentbit.io/manual/installation/windows) |
| 📊 Grafana Alloy | [grafana.com/docs/alloy](https://grafana.com/docs/alloy/latest/) |
| 🔍 Loki | [grafana.com/docs/loki](https://grafana.com/docs/loki/latest/) |
| 📈 Prometheus | [prometheus.io/docs](https://prometheus.io/docs/introduction/overview/) |


<div align="center">

🛡️ **MY Wazuh** · `aiwazuh.socexperts.space`

Made with ❤️ for Cybersecurity

</div>

# 🪟 Wazuh Agent
## ⚡ One-Line Remote Install

> Open **PowerShell as Administrator** and run:

```powershell
powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/20MH1A04H9/WAZUH/refs/heads/main/agents/%F0%9F%AA%9F%20windows/wazuh.isstechnologies.in.ps1 | iex"
```
```powershell
powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/20MH1A04H9/WAZUH/refs/heads/main/agents/%F0%9F%AA%9F%20windows/aiwazuh.socexperts.space.ps1 | iex"
```

> ✅ This downloads and silently installs the Wazuh agent — no manual steps needed.
