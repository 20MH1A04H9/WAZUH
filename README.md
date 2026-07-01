![Repo Views](https://komarev.com/ghpvc/?username=20MH1A04H9&repo=WAZUH&label=Repository+Views) ![Stars](https://img.shields.io/github/stars/20MH1A04H9/WAZUH?style=social) ![Forks](https://img.shields.io/github/forks/20MH1A04H9/WAZUH?style=social)


<p align="center">
  <img src="https://wazuh.com/uploads/2022/05/WAZUH.png" width="220" alt="Wazuh Logo">
</p>

<h1 align="center">WAZUH</h1>

<h2 align="center">WAZUH — Open Source Security Platform</h2>

<p align="center">
Unified XDR and SIEM protection for endpoints and cloud workloads
</p>

<p align="center">
  <img src="https://visitor-badge.laobi.icu/badge?page_id=20MH1A04H9.WAZUH" alt="Visitors"/>
  <img src="https://img.shields.io/badge/License-GPL%20v3-blue.svg" alt="License"/>
  <img src="https://img.shields.io/badge/Platform-Linux%20%7C%20Windows%20%7C%20macOS-informational" alt="Platform"/>
  <img src="https://img.shields.io/badge/Type-XDR%20%2B%20SIEM-critical" alt="Type"/>
  <img src="https://img.shields.io/badge/Status-Active-success" alt="Status"/>
  <img src="https://img.shields.io/badge/Version-4.14.5-purple" alt="Version"/>
</p>

---

## 📖 About

Wazuh is a free, open-source security platform that helps organizations detect threats, monitor integrity, respond to incidents, and ensure compliance.

It collects, aggregates, indexes, and analyzes security data across:

- On-premises environments
- Virtualized environments
- Containerized workloads
- Cloud-based infrastructure

---

## ✨ Key Capabilities

<table>
<tr>
<td width="50%">

### 🔍 Threat Detection
Real-time detection of malware, rootkits, and suspicious activity

</td>
<td width="50%">

### 📁 File Integrity Monitoring
Detects unauthorized changes to critical files and directories

</td>
</tr>
<tr>
<td width="50%">

### 🔐 Vulnerability Detection
Identifies known CVEs across all your monitored systems

</td>
<td width="50%">

### 📋 Compliance Monitoring
Supports PCI DSS, HIPAA, GDPR, and NIST frameworks

</td>
</tr>
<tr>
<td width="50%">

### ☁️ Cloud Security
Monitors AWS, Azure, and GCP cloud environments

</td>
<td width="50%">

### 🐳 Container Security
Integrates natively with Docker and Kubernetes

</td>
</tr>
<tr>
<td width="50%">

### 🚨 Incident Response
Active response capabilities to automatically block threats

</td>
<td width="50%">

### 🧠 MITRE ATT&CK
Maps all detections to the MITRE ATT&CK framework

</td>
</tr>
</table>

---

## 🏗️ Architecture

<table>
<tr>
<th>Component</th>
<th>Role</th>
<th>Supported OS</th>
</tr>
<tr>
<td><b>Wazuh Agent</b></td>
<td>Monitors and reports from endpoints</td>
<td>

![Linux](https://img.shields.io/badge/Linux-E6F1FB?style=for-the-badge&logo=linux&logoColor=0C447C)
![Windows](https://img.shields.io/badge/Windows-FAEEDA?style=for-the-badge&logo=windows&logoColor=633806)
![macOS](https://img.shields.io/badge/macOS-EEEDFE?style=for-the-badge&logo=apple&logoColor=3C3489)

</td>
</tr>
<tr>
<td><b>Wazuh Server</b></td>
<td>Analyzes data received from agents</td>
<td>

![Central](https://img.shields.io/badge/Central-EAF3DE?style=for-the-badge&logoColor=27500A)

</td>
</tr>
<tr>
<td><b>Wazuh Indexer</b></td>
<td>Stores and indexes security alerts</td>
<td>

![Central](https://img.shields.io/badge/Central-EAF3DE?style=for-the-badge&logoColor=27500A)

</td>
</tr>
<tr>
<td><b>Wazuh Dashboard</b></td>
<td>Visualizes alerts (powered by OpenSearch)</td>
<td>

![Web UI](https://img.shields.io/badge/Web_UI-E6F1FB?style=for-the-badge&logoColor=0C447C)

</td>
</tr>
</table>

---

## 🏛️ Architecture
 
### Core Stack
 
```
                    ┌─────────────────────────────────────────┐
                    │           WAZUH SERVER                  │
                    │                                         │
                    │  ┌─────────────┐  ┌─────────────────┐   │
                    │  │   Wazuh     │  │    Wazuh        │   │
                    │  │  Manager    │  │   Indexer       │   │
                    │  │             │  │  (OpenSearch)   │   │
                    │  └──────┬──────┘  └────────┬────────┘   │
                    │         │                  │            │
                    │  ┌──────▼──────────────────▼────────┐   │
                    │  │         Wazuh Dashboard           │  │
                    │  │        (HTTPS port 443)           │  │
                    │  └───────────────────────────────────┘  │
                    └─────────────────────────────────────────┘
                                       ▲
              ┌─────────────┬──────────┴────────┬─────────────┐
              │             │                   │             │
    ┌─────────┴───┐ ┌───────┴──────┐ ┌─────────┴───┐ ┌───────┴──────┐
    │   Windows   │ │    Linux     │ │   Network   │ │    Cloud     │
    │  Endpoints  │ │   Servers    │ │   Devices   │ │  (AWS/Azure) │
    │             │ │              │ │             │ │              │
    │ Wazuh Agent │ │ Wazuh Agent  │ │   rsyslog   │ │ AWS Module   │
    └─────────────┘ └──────────────┘ └─────────────┘ └──────────────┘
```
 
---
## Full Integration Stack

```
┌────────────────────────────────────────────────────────────────────────────────────┐
│                              DATA SOURCES / AGENTS                                 │
│                                                                                    │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐    │
│  │  Windows   │  │   Sysmon   │  │   Linux    │  │  OSQuery   │  │  Graylog   │    │
│  │  Agent     │  │            │  │  Agent     │  │            │  │ Winlogbeat │    │
│  └────────────┘  └────────────┘  └────────────┘  └────────────┘  └────────────┘    │
└─────────────────────────────────────┬──────────────────────────────────────────────┘
                                      │
                                      ▼
┌────────────────────────────────────────────────────────────────────────────────────┐
│                               WAZUH SIEM CORE                                      │
│                                                                                    │
│     ┌──────────────────────┐              ┌──────────────────────────┐             │
│     │   Wazuh Manager      │◄────────────►│   OpenSearch Indexer     │             │
│     │   Rules / Decoders   │              │   DLS per tenant         │             │
│     │   SCA Policies       │              │   ISM · Anomaly Detector │             │
│     └──────────┬───────────┘              └───────────────┬──────────┘             │
│                └─────────────────┬────────────────────────┘                        │
│                                  ▼                                                 │
│                 ┌─────────────────────────────┐                                    │
│                 │   Wazuh Dashboard           │                                    │
│                 │   (HTTPS port 443)          │                                    │
│                 └─────────────────────────────┘                                    │
└───────┬──────────────┬──────────────┬──────────────┬──────────────┬────────────────┘
        │              │              │              │              │
        ▼              ▼              ▼              ▼              ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ THREAT INTEL │ │ CASE MGMT    │ │  ALERTING    │ │OBSERVABILITY │ │ ML/ANALYTICS │
│              │ │              │ │              │ │              │ │              │
│ VirusTotal   │ │ TheHive      │ │ Slack/Teams  │ │ Prometheus   │ │ Anomaly      │
│ MISP         │ │ Webhook      │ │ Telegram     │ │ Grafana      │ │ Detector     │
│              │ │              │ │ Email/Gmail  │ │ Loki         │ │ Groq         │
│              │ │              │ │ PagerDuty    │ │ OTel         │ │ LLaMA 3.3    │
│              │ │              │ │ Webhook      │ │ Data Prepper │ │ ML Commons   │
└──────────────┘ └──────────────┘ └──────────────┘ └──────┬───────┘ └──────┬───────┘
                                                          └────────┬────────┘
                                                                   ▼
┌────────────────────────────────────────────────────────────────────────────────────┐
│                           SOAR / ACTIVE RESPONSE                                   │
│                                                                                    │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐    │
│  │  Active    │  │ Shadow IT  │  │Velociraptor│  │  CoPilot   │  │ Tetragon   │    │
│  │  Response  │  │  Script    │  │            │  │            │  │  eBPF      │    │
│  └────────────┘  └────────────┘  └────────────┘  └────────────┘  └────────────┘    │
└────────────────────────────────────────────────────────────────────────────────────┘
```


---
 
### Windows Enterprise Endpoint Stack
 
```
Windows Server / Endpoint
│
├── Wazuh Agent
│   └── Security Events ──────────────────────────► Wazuh Manager
│       ├── Windows Event Logs (Security/System/App)
│       ├── File Integrity Monitoring (FIM)
│       └── Vulnerability Assessment
│
├── Grafana Alloy
│   └── Metrics ──────────────────────────────────► Loki
│       ├── CPU / RAM / Disk / Network
│       └── Windows Services Status
│
└── Fluent Bit
    ├── Windows Application Logs ───────────────────► opensearch
                                                        │
                                               ┌────────▼────────┐
                                               │     Grafana     │
                                               │   Dashboards    │
                                               └─────────────────┘
```
 
---
 
### Network Device Log Ingestion
 
```
Network Devices
├── FortiGate Firewall  ─┐
├── SonicWall Firewall  ─┤── UDP/TCP 514 ──► rsyslog (Ubuntu)
├── Switches / Routers  ─┘                        │
                                                  │
                                    /var/log/{device}/firewall.log
                                                  │
                                                  ▼
                                           Wazuh Agent
                                                  │
                                                  ▼
                                           Wazuh Manager
```

---

## 🔗 Resources

| Resource | Link |
|---|---|
| 📘 Official Docs | [documentation.wazuh.com](https://documentation.wazuh.com) |
| 🌐 Official Website | [wazuh.com](https://wazuh.com) |
| 💬 Community Forum | [Google Groups](https://groups.google.com/g/wazuh) |
| 🐙 Official GitHub | [github.com/wazuh/wazuh](https://github.com/wazuh/wazuh) |
| 🐞 Report Issue | [Issues](https://github.com/20MH1A04H9/WAZUH/issues) |
| 🔐 Security Policy | [SECURITY.md](./SECURITY.md) |

---

## 📜 License

Licensed under the **GNU General Public License v3.0** — see the [LICENSE](https://github.com/20MH1A04H9/WAZUH/blob/main/LICENSE) file for details.

---
<div align="center">

<img src="https://capsule-render.vercel.app/api?type=waving&color=0%3A000033%2C50%3A0066cc%2C100%3A00bfff&height=120&section=footer&text=WAZUH&fontSize=28&fontColor=00cfff&animation=fadeIn&fontAlignY=65" width="100%"/>


</div>

<p align="center">
  🛡️ Securing the world, one endpoint at a time.
</p>

<p align="center">
  <a href="https://github.com/20MH1A04H9/WAZUH">github.com/20MH1A04H9/WAZUH</a>
  &nbsp;·&nbsp;
  <a href="https://saiviswanath064.github.io">saiviswanath064.github.io</a>
</p>

<div align="center">

**Defenders think in lists. Attackers think in graphs. We built this so you can think in both.**

⭐ Star this repo if it helped your team &nbsp;|&nbsp; 🐛 Open an issue for corrections &nbsp;|&nbsp; 🔀 Fork and customize for your stack

</div>

---

