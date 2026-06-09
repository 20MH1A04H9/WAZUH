# 🪟 Fluent Bit — Windows Installation & Log Collection

> Complete guide for installing **Fluent Bit** on Windows as a service, collecting Windows Event Logs, application logs, IIS logs, and forwarding them to OpenSearch/SIEM. Covers installation, service registration, failure recovery, and full Windows log collection config.

<p align="center">
  <img src="https://img.shields.io/badge/Fluent_Bit-v5.0.3-49BDA5?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/Windows-10%20%7C%2011%20%7C%20Server-0078D4?style=for-the-badge&logo=windows&logoColor=white"/>
  <img src="https://img.shields.io/badge/PowerShell-Admin%20Required-5391FE?style=for-the-badge&logo=powershell&logoColor=white"/>
  <img src="https://img.shields.io/badge/Status-Active-brightgreen?style=for-the-badge"/>
</p>

---

<p align="center">
  <img src="https://raw.githubusercontent.com/fluent/fluent-bit/master/documentation/fluentbit_ecosystem.png"
       alt="Fluent Bit Ecosystem"
       width="1000">
</p>

---

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Step 1 — Download Fluent Bit](#step-1--download-fluent-bit)
- [Step 2 — Install the EXE](#step-2--install-the-exe)
- [Step 3 — Test the Binary](#step-3--test-the-binary)
- [Step 4 — Register as Windows Service](#step-4--register-as-windows-service)
- [Step 5 — Start the Service](#step-5--start-the-service)
- [Step 6 — Verify Service Status](#step-6--verify-service-status)
- [Fixing a Stale / Broken Service](#fixing-a-stale--broken-service)
- [Configure Automatic Restart on Failure](#configure-automatic-restart-on-failure)
- [Verify Service Configuration](#verify-service-configuration)
- [Full Windows Log Collection Config](#full-windows-log-collection-config)
- [Log Sources Collected](#log-sources-collected)
- [References](#references)

---

## Overview

Fluent Bit is a lightweight, high-performance log processor and forwarder. On Windows it runs as a background service collecting:

- Windows Event Logs (System, Security, Application, PowerShell, Setup)
- Flat log files (IIS, Program Files, ProgramData)
- Any `.log` files from installed applications

```
Windows Machine
  │
  ├── Event Logs (winlog)      ─┐
  ├── IIS Logs (tail)           ├──→ Fluent Bit Service ──→ OpenSearch / SIEM
  ├── App Logs (tail)          ─┘
  └── ProgramData Logs (tail)
```

---

## Prerequisites

| Requirement | Details |
|---|---|
| **OS** | Windows 10 / 11 / Server 2016+ |
| **Architecture** | 64-bit |
| **Privileges** | PowerShell as Administrator |
| **Fluent Bit Version** | v5.0.3 |
| **Install Path** | `C:\Program Files\fluent-bit\` |

---

## Step 1 — Download Fluent Bit

Download the official installer:

| Architecture | Download Link |
|---|---|
| **64-bit** | [fluent-bit-5.0.3-win64.exe](https://packages.fluentbit.io/windows/fluent-bit-5.0.3-win64.exe) |

```powershell
# Or download via PowerShell
Invoke-WebRequest `
  -Uri "https://packages.fluentbit.io/windows/fluent-bit-5.0.3-win64.exe" `
  -OutFile "$env:TEMP\fluent-bit-5.0.3-win64.exe"
```

---

## Step 2 — Install the EXE

Double-click the downloaded `.exe` → click **Next** through the installer → click **Finish**.

Default installation path:

```
C:\Program Files\fluent-bit\
  ├── bin\
  │   └── fluent-bit.exe
  ├── conf\
  │   ├── fluent-bit.conf
  │   ├── parsers.conf
  │   └── plugins.conf
  └── log\
```

---

## Step 3 — Test the Binary

Open **PowerShell as Administrator** and run a quick test:

```powershell
& "C:\Program Files\fluent-bit\bin\fluent-bit.exe" -i dummy -o stdout
```

Expected output (dummy data streaming):

```
[0] dummy.0: [1704067200.000000000, {"message"=>"dummy"}]
[1] dummy.0: [1704067201.000000000, {"message"=>"dummy"}]
```

Press `Ctrl+C` to stop. If you see output → binary is working ✅

---

## Step 4 — Register as Windows Service

Open **PowerShell as Administrator** and run:

```powershell
New-Service `
  -Name "fluent-bit" `
  -BinaryPathName '"C:\Program Files\fluent-bit\bin\fluent-bit.exe" -c "C:\Program Files\fluent-bit\conf\fluent-bit.conf"' `
  -DisplayName "Fluent Bit" `
  -Description "Fluent Bit Log Collector" `
  -StartupType Automatic
```

---

## Step 5 — Start the Service

```powershell
Start-Service fluent-bit
```

---

## Step 6 — Verify Service Status

```powershell
Get-Service fluent-bit
```

Expected output:

```
Status   Name         DisplayName
------   ----         -----------
Running  fluent-bit   Fluent Bit
```

---

## Fixing a Stale / Broken Service

> If the service was previously created incorrectly or fails to start, delete and re-create it cleanly.

### Step 1 — Stop and Delete the Old Service

```powershell
Stop-Service fluent-bit -ErrorAction SilentlyContinue
sc.exe delete fluent-bit
```

Expected output:

```
[SC] DeleteService SUCCESS
```

Wait 3–5 seconds before proceeding.

### Step 2 — Re-Create the Service Cleanly

```powershell
New-Service `
  -Name "fluent-bit" `
  -BinaryPathName '"C:\Program Files\fluent-bit\bin\fluent-bit.exe" -c "C:\Program Files\fluent-bit\conf\fluent-bit.conf"' `
  -DisplayName "Fluent Bit" `
  -Description "Fluent Bit Log Collector" `
  -StartupType Automatic
```

### Step 3 — Start the Service

```powershell
Start-Service fluent-bit
```

### Step 4 — Confirm Running

```powershell
Get-Service fluent-bit
```

Expected:

```
Status   Name         DisplayName
------   ----         -----------
Running  fluent-bit   Fluent Bit
```

---

## Configure Automatic Restart on Failure

Configure the service to automatically restart if it crashes:

```powershell
sc.exe failure fluent-bit reset= 86400 actions= restart/5000/restart/5000/restart/5000
```

| Parameter | Value | Description |
|---|---|---|
| `reset=` | `86400` | Reset failure count after 24 hours (seconds) |
| `restart/5000` | First failure | Restart after 5 seconds |
| `restart/5000` | Second failure | Restart after 5 seconds |
| `restart/5000` | Third failure | Restart after 5 seconds |

---

## Verify Service Configuration

Confirm the service is using the correct binary path:

```powershell
(Get-CimInstance Win32_Service -Filter "Name='fluent-bit'").PathName
```

Expected output:

```
"C:\Program Files\fluent-bit\bin\fluent-bit.exe" -c "C:\Program Files\fluent-bit\conf\fluent-bit.conf"
```

---

## Full Windows Log Collection Config

Open the config file:

```powershell
notepad "C:\Program Files\fluent-bit\conf\fluent-bit.conf"
```

Replace the entire content with the following:

```ini
[SERVICE]
    flush           5
    daemon          Off
    log_level       info
    parsers_file    parsers.conf
    plugins_file    plugins.conf
    http_server     Off
    http_listen     0.0.0.0
    http_port       2020
    storage.metrics on

# ─── WINDOWS EVENT LOGS ───────────────────────────────────────

[INPUT]
    Name         winlog
    Channels     System
    Interval_Sec 1
    Tag          windows.system

[INPUT]
    Name         winlog
    Channels     Security
    Interval_Sec 1
    Tag          windows.security

[INPUT]
    Name         winlog
    Channels     Application
    Interval_Sec 1
    Tag          windows.application

[INPUT]
    Name         winlog
    Channels     Setup
    Interval_Sec 1
    Tag          windows.setup

[INPUT]
    Name         winlog
    Channels     Windows PowerShell
    Interval_Sec 1
    Tag          windows.powershell

# ─── FLAT LOG FILES ───────────────────────────────────────────

[INPUT]
    Name              tail
    Path              C:\Windows\System32\winevt\Logs\*.evtx
    Tag               windows.evtx
    Refresh_Interval  10

[INPUT]
    Name              tail
    Path              C:\inetpub\logs\LogFiles\*\*.log
    Tag               app.iis
    Refresh_Interval  10

[INPUT]
    Name              tail
    Path              C:\Program Files\**\*.log
    Tag               app.programfiles
    Refresh_Interval  10

[INPUT]
    Name              tail
    Path              C:\ProgramData\**\*.log
    Tag               app.programdata
    Refresh_Interval  10

# ─── OUTPUT ───────────────────────────────────────────────────

[OUTPUT]
    Name  stdout
    Match *
```
or Loki (Grafana dashbaord)
Replace the entire content with the following:
```
[SERVICE]
    Flush        5
    Log_Level    info
    Parsers_File parsers.conf

[INPUT]
    Name              tail
    Path              C:\Program Files (x86)\ossec-agent\ossec.log
    Tag               wazuh
    Read_from_Head    true
    Refresh_Interval  5
    Skip_Long_Lines   On

[OUTPUT]
    Name         loki
    Match        wazuh
    Host         20.80.106.31
    Port         3100
    Labels       job=windows,hostname=${COMPUTERNAME},service_name=wazuh

```

Save the file and restart the service:

```powershell
Restart-Service fluent-bit
Get-Service fluent-bit
```

Verify logs are streaming by running directly:

```powershell
& "C:\Program Files\fluent-bit\bin\fluent-bit.exe" `
  -c "C:\Program Files\fluent-bit\conf\fluent-bit.conf"
```

---

## Log Sources Collected

| Tag | Source | Description |
|---|---|---|
| `windows.system` | Windows Event Log — System | Hardware, driver, OS service events |
| `windows.security` | Windows Event Log — Security | Login events, audit, access control |
| `windows.application` | Windows Event Log — Application | App crashes, errors, warnings |
| `windows.setup` | Windows Event Log — Setup | Windows Update and setup events |
| `windows.powershell` | Windows Event Log — PowerShell | PowerShell script execution logs |
| `windows.evtx` | `.evtx` files on disk | Raw event log files |
| `app.iis` | `C:\inetpub\logs\` | IIS web server access logs |
| `app.programfiles` | `C:\Program Files\**\*.log` | Any log files under Program Files |
| `app.programdata` | `C:\ProgramData\**\*.log` | Any log files under ProgramData |

---

## Output — Forward to OpenSearch

To forward logs to **OpenSearch / Wazuh Indexer** instead of stdout, replace the `[OUTPUT]` block:

```ini
[OUTPUT]
    Name              opensearch
    Match             *
    Host              <OPENSEARCH_IP>
    Port              9200
    HTTP_User         admin
    HTTP_Passwd       <YOUR_PASSWORD>
    tls               On
    tls.verify        Off
    Index             ss4o_logs-windows-default
    Suppress_Type_Name On
```

Restart after updating:

```powershell
Restart-Service fluent-bit
```

---


## References

| Resource | Link |
|---|---|
| 📘 Fluent Bit Windows Docs | [docs.fluentbit.io/installation/windows](https://docs.fluentbit.io/manual/installation/windows) |
| 🔧 Fluent Bit Config Reference | [docs.fluentbit.io/configuration](https://docs.fluentbit.io/manual/administration/configuring-fluent-bit) |
| 🪟 Windows winlog Plugin | [docs.fluentbit.io/winlog](https://docs.fluentbit.io/manual/pipeline/inputs/windows-event-log) |
| 🔍 OpenSearch Output Plugin | [docs.fluentbit.io/opensearch](https://docs.fluentbit.io/manual/pipeline/outputs/opensearch) |
