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
  <img src="https://img.shields.io/badge/Version-4.14-purple" alt="Version"/>
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

## 📁 Repository Structure

```
WAZUH/
├── 📂 Data Prepper/          # OpenSearch Data Prepper pipeline configs
├── 📂 Rules/                
├── 📂 Wazuhindexer/          
├── 📂 plugins/               # Dashboard plugins (v4.14.5)
├── 📂 scripts/              
├── 📂 ssl/                  
├── 📂 wazuh-gpo-deploy/     
├── 📂 wazuh_multi_tenant/    
├── 📄 WAZUH_INSTALL_GUIDE.md 
├── 📄 SECURITY.md           
└── 📄 README.md             
```

---

## 📂 Module Details

### 🔗 Data Prepper
OpenSearch Data Prepper pipeline configurations for ingesting and processing Wazuh logs into OpenSearch/Elasticsearch clusters.

### 📜 Rules
Custom Wazuh detection rules for advanced threat detection beyond the default ruleset. Includes rules for:
- Custom application monitoring
- Suspicious behavior detection
- Compliance-related alerts

### 🗄️ Wazuh Indexer
Setup guides and configuration files for the Wazuh Indexer (OpenSearch-based). Covers index management, shard tuning, and retention policies.

### 🔌 Plugins
Dashboard plugin files for Wazuh **v4.14.5**, including installation steps and compatibility notes.

### ⚙️ Scripts
Automation scripts for:
- Custom rules installation
- Agent enrollment
- Service management
- Refactored Wazuh configuration workflows

### 🔒 SSL
SSL/TLS certificate generation and configuration for:
- Wazuh Manager ↔ Agent encryption
- Dashboard HTTPS setup
- Certificate rotation procedures

### 🖥️ Wazuh GPO Deploy
Group Policy Object (GPO) scripts and guides for deploying Wazuh agents across Windows domain environments silently at scale.

### 🏢 Wazuh Multi-Tenant
Complete lab setup guide for running Wazuh in a **multi-tenant** architecture — ideal for MSSPs and organizations managing multiple isolated environments.

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

<p align="center">
  🛡️ Securing the world, one endpoint at a time.
</p>

<p align="center">
  Made with ❤️ for Cybersecurity —
  <a href="https://github.com/20MH1A04H9/WAZUH">github.com/20MH1A04H9/WAZUH</a>
</p>
