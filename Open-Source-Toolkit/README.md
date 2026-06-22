<div align="center">

<img src="https://img.shields.io/badge/Open%20Source-Security%20Arsenal-00FF88?style=for-the-badge&logo=shield&logoColor=black" alt="Open Source Security Arsenal"/>

# 🛡️ Open-Source Cybersecurity Toolkit
### For SMBs & Enterprise Teams

**Battle-tested. Zero licensing fees. Production-ready.**

[![Tools](https://img.shields.io/badge/Tools-11%20Curated-00FF88?style=flat-square)](https://github.com/)
[![License](https://img.shields.io/badge/All%20Tools-Free%20%26%20Open%20Source-blue?style=flat-square)](https://github.com/)
[![Maintained](https://img.shields.io/badge/Actively-Maintained-success?style=flat-square)](https://github.com/)
[![PRs Welcome](https://img.shields.io/badge/PRs-Welcome-brightgreen?style=flat-square)](https://github.com/)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue?style=flat-square)](https://www.gnu.org/licenses/gpl-3.0)

</div>

---

## 💡 Why Open-Source Security?

> **Enterprise-grade protection doesn't have to cost enterprise-level money.**

Most SMBs and growing companies skip security tooling because of licensing costs — that's exactly what attackers count on. This curated stack gives your team **the same detection and hardening capabilities** used by Fortune 500 security operations centers, at **$0 in licensing fees**.

Whether you're a 10-person startup or a 10,000-person enterprise, this toolkit scales with you.

---

## ⚡ At a Glance — All 11 Tools

| # | Tool | Primary Use Case | Best For | Cost |
|---|------|-----------------|----------|------|
| 01 | [**Nmap**](#-nmap--network-scanner) | Network scanning & mapping | SMB + Enterprise | `Free` |
| 02 | [**OpenVAS**](#-openvas--vulnerability-scanner) | Vulnerability scanning | SMB + Enterprise | `Free` |
| 03 | [**Lynis**](#-lynis--linux-auditor) | Linux auditing & hardening | SMB + Enterprise | `Free` |
| 04 | [**Nikto**](#-nikto--web-scanner) | Web vulnerability scanning | SMB + Enterprise | `Free` |
| 05 | [**Fail2Ban**](#-fail2ban--brute-force-shield) | Brute-force attack prevention | SMB + Enterprise | `Free` |
| 06 | [**ClamAV**](#-clamav--malware-detector) | Malware detection | SMB | `Free` |
| 07 | [**Snort**](#-snort--network-ids) | Network intrusion detection | SMB + Enterprise | `Free` |
| 08 | [**Suricata**](#-suricata--threat-detection-engine) | Network threat detection | Enterprise | `Free` |
| 09 | [**OSSEC**](#-ossec--host-based-ids) | Host-based intrusion detection | SMB + Enterprise | `Free` |
| 10 | [**OSQuery**](#-osquery--endpoint-monitor) | Endpoint monitoring | Enterprise | `Free` |
| 11 | [**Wazuh**](#-wazuh--siem--threat-platform) | SIEM & threat monitoring | SMB + Enterprise | `Free` |

---

## 🗺️ Your Security Coverage Map

| Security Layer | Tools Covered |
|---|---|
| **Perimeter** | Nmap · Snort · Suricata · Fail2Ban |
| **Host** | Lynis · OSSEC · ClamAV · OSQuery |
| **Web** | Nikto · OpenVAS |
| **Visibility** | Wazuh *(aggregates everything above)* |

---

## 🔍 Nmap — Network Scanner

**"You can't protect what you can't see."**

Nmap is the gold standard for network discovery. It maps your entire infrastructure — open ports, running services, OS fingerprints — in minutes. Security teams use it for routine audits; attackers use it first. Beat them to it.

### Key Capabilities
- 🔎 Host discovery across subnets
- 🔌 Port scanning (TCP/UDP)
- 🖥️ OS and service version detection
- 📜 NSE scripting for automated checks
- 📊 Output in XML, JSON, grepable formats

### Ideal For
| Company Size | Use Case |
|---|---|
| SMB | Monthly network audits, asset discovery |
| Enterprise | Continuous scanning pipelines, compliance reporting |

🔗 [nmap.org](https://nmap.org) · [Documentation](https://nmap.org/docs.html) · [GitHub](https://github.com/nmap/nmap)

---

## 🧪 OpenVAS — Vulnerability Scanner

**"Find your vulnerabilities before attackers do."**

OpenVAS (Open Vulnerability Assessment System) is a full-featured vulnerability scanner with 50,000+ tests. It's the open-source answer to Nessus and Qualys — with daily CVE feed updates and a web UI for non-technical stakeholders.

### Key Capabilities
- 🔍 50,000+ network vulnerability tests (NVTs)
- 📅 Daily CVE and NVT feed updates
- 🌐 Web-based management UI (Greenbone)
- 📋 Compliance scanning (PCI-DSS, HIPAA)
- 📈 Risk-rated reports with remediation guidance

### Ideal For
| Company Size | Use Case |
|---|---|
| SMB | Quarterly vulnerability assessments |
| Enterprise | Continuous vulnerability management programs |

🔗 [greenbone.net](https://www.greenbone.net) · [Documentation](https://docs.greenbone.net) · [GitHub](https://github.com/greenbone/openvas-scanner)

---

## 🔒 Lynis — Linux Auditor

**"Harden your systems before they're in production, not after an incident."**

Lynis performs deep security audits of Linux/Unix systems. It checks 300+ security controls, flags misconfigurations, and gives you a hardening index score. Perfect for pre-deployment checklists and compliance evidence.

### Key Capabilities
- 🏆 Hardening score (0–100) with actionable items
- ⚙️ 300+ security control checks
- 🔐 SSH, file permissions, and kernel hardening
- 📑 Compliance mapping (CIS, ISO 27001, PCI-DSS)
- 🔄 Pluggable architecture for custom tests

### Ideal For
| Company Size | Use Case |
|---|---|
| SMB | Server hardening before launch |
| Enterprise | Baseline compliance audits, CIS benchmarking |

🔗 [cisofy.com/lynis](https://cisofy.com/lynis) · [GitHub](https://github.com/CISOfy/lynis)

---

## 🕸️ Nikto — Web Scanner

**"Your web apps are your largest attack surface."**

Nikto scans web servers for dangerous files, outdated software, and server misconfigurations. It checks for 6,700+ potential issues and runs in minutes. A must-run before any web app goes live.

### Key Capabilities
- 🌐 6,700+ potentially dangerous file/program checks
- 🔄 Checks for outdated server software
- 🍪 Cookie and HTTP header analysis
- 🔑 SSL/TLS configuration issues
- 📁 Directory traversal and file enumeration

### Ideal For
| Company Size | Use Case |
|---|---|
| SMB | Pre-launch web app security checks |
| Enterprise | CI/CD pipeline security gates |

🔗 [cirt.net/Nikto2](https://cirt.net/Nikto2) · [GitHub](https://github.com/sullo/nikto)

---

## 🚫 Fail2Ban — Brute-Force Shield

**"Block attackers after the first failed attempt — not the thousandth."**

Fail2Ban monitors log files and automatically bans IPs showing malicious behavior — brute-force SSH attacks, web login attempts, and more. Set it up once and it runs silently in the background, blocking thousands of attacks daily.

### Key Capabilities
- 🔐 SSH, FTP, HTTP brute-force protection
- ⏱️ Configurable ban duration and threshold
- 🌍 GeoIP-based blocking support
- 📨 Email alerts on bans
- 🔌 Pluggable for custom log formats

### Ideal For
| Company Size | Use Case |
|---|---|
| SMB | Protecting internet-facing servers (SSH, web) |
| Enterprise | Perimeter defense at scale with central log management |

🔗 [fail2ban.org](https://www.fail2ban.org) · [GitHub](https://github.com/fail2ban/fail2ban)

---

## 🦠 ClamAV — Malware Detector

**"Free antivirus that doesn't phone home."**

ClamAV is the leading open-source antivirus engine. It's widely used in email gateways and file servers to catch malware before it spreads. Lightweight, scriptable, and trusted across millions of deployments.

### Key Capabilities
- 🛡️ Detects trojans, viruses, malware, and threats
- 📧 Email gateway scanning integration
- 🗄️ File server and NAS scanning
- 🔄 Automatic signature database updates
- 🔌 Library API for integration into custom apps

### Ideal For
| Company Size | Use Case |
|---|---|
| SMB | Email server scanning, file share protection |
| Enterprise | Gateway scanning, SIEM integration |

🔗 [clamav.net](https://www.clamav.net) · [GitHub](https://github.com/Cisco-Talos/clamav)

---

## 📡 Snort — Network IDS

**"Three decades of catching attackers. Still the best."**

Snort is the world's most widely deployed network intrusion detection system with over 5 million downloads. Its rule-based engine lets you detect everything from port scans to zero-day exploits in real time.

### Key Capabilities
- 📦 Packet sniffer and logger
- 🔍 Real-time traffic analysis
- 🧠 Protocol analysis and content matching
- 📜 Community + registered rule sets (free)
- 🔔 Alerting via syslog, unified2, JSON

### Ideal For
| Company Size | Use Case |
|---|---|
| SMB | In-line IDS on edge network |
| Enterprise | Distributed sensor network with central management |

🔗 [snort.org](https://www.snort.org) · [GitHub](https://github.com/snort3/snort3)

---

## ⚡ Suricata — Threat Detection Engine

**"Snort's multi-threaded, GPU-accelerated successor."**

Suricata is a high-performance network security monitoring engine that does IDS, IPS, and network security monitoring simultaneously. It processes traffic at multi-gigabit speeds and integrates natively with the Elastic Stack and Wazuh.

### Key Capabilities
- 🚀 Multi-threaded for high-throughput networks
- 🔍 IDS + IPS + NSM in a single engine
- 🧠 Protocol detection and file extraction
- 📊 Native JSON EVE log output (Elastic-ready)
- 🔐 TLS/SSL inspection and certificate logging

### Ideal For
| Company Size | Use Case |
|---|---|
| SMB | Network monitoring for 100Mbps–1Gbps links |
| Enterprise | High-speed IDS/IPS at data center perimeters |

🔗 [suricata.io](https://suricata.io) · [GitHub](https://github.com/OISF/suricata)

---

## 🖥️ OSSEC — Host-Based IDS

**"Know the moment your servers are tampered with."**

OSSEC monitors your hosts in real time — log analysis, file integrity checking, rootkit detection, and active response. It's the server-side complement to network-based tools like Snort and Suricata.

### Key Capabilities
- 📁 File integrity monitoring (FIM)
- 📋 Log analysis and correlation
- 🦠 Rootkit and malware detection
- ⚡ Active response (block IPs, run scripts)
- 🌐 Centralized multi-host management

### Ideal For
| Company Size | Use Case |
|---|---|
| SMB | Server integrity monitoring for critical systems |
| Enterprise | Multi-site host monitoring with centralized alerting |

🔗 [ossec.net](https://www.ossec.net) · [GitHub](https://github.com/ossec/ossec-hids)

---

## 🔭 OSQuery — Endpoint Monitor

**"Query your entire fleet like a database."**

OSQuery exposes your operating system as a high-performance relational database. Write SQL to query running processes, open network connections, loaded kernel modules, user activity, and more — across thousands of endpoints simultaneously.

### Key Capabilities
- 🗄️ SQL interface to OS telemetry
- 🔍 Process, network, user, and file monitoring
- 🌐 Fleet-wide queries at scale
- 🔔 Scheduled queries as continuous monitoring
- 🔌 Integrates with Wazuh, Splunk, Elastic

### Ideal For
| Company Size | Use Case |
|---|---|
| SMB | Endpoint visibility for 10–500 machines |
| Enterprise | Threat hunting and fleet-wide incident response |

🔗 [osquery.io](https://osquery.io) · [GitHub](https://github.com/osquery/osquery)

---

## 🧠 Wazuh — SIEM & Threat Platform

**"The command center that ties everything together."**

Wazuh is the capstone of your security stack. It aggregates alerts from every tool in this list, correlates events across your entire infrastructure, and presents them in a unified dashboard. If you deploy only one tool from this list, make it Wazuh.

### Key Capabilities
- 🎛️ Unified SIEM dashboard (Elastic-powered)
- 🤝 Integrates with OSSEC, OSQuery, Suricata
- 🔐 FIM, log analysis, vulnerability detection
- ☁️ Cloud workload monitoring (AWS, Azure, GCP)
- 📋 Compliance: PCI-DSS, HIPAA, GDPR, NIST

### Ideal For
| Company Size | Use Case |
|---|---|
| SMB | All-in-one security monitoring + compliance |
| Enterprise | Enterprise SIEM replacing commercial alternatives (Splunk, QRadar) |

🔗 [wazuh.com](https://wazuh.com) · [Documentation](https://documentation.wazuh.com) · [GitHub](https://github.com/wazuh/wazuh)

---

## 🏗️ Recommended Stack by Company Size

### 🏢 SMB Starter Stack (≤ 100 employees)
**Fail2Ban + ClamAV + Lynis + Wazuh** — Block brute-force attacks, scan email and file servers for malware, run monthly hardening audits, and centralize all alerting in Wazuh.
**Estimated setup time:** 1–2 days | **Monthly maintenance:** ~4 hours

### 🏭 Growth Company Stack (100–500 employees)
**Everything above + Nmap + OpenVAS + Nikto + OSSEC** — Add quarterly network asset discovery, monthly vulnerability scanning, web app security gates, and server-side host intrusion detection.
**Estimated setup time:** 1 week | **Monthly maintenance:** ~8 hours

### 🏦 Enterprise Stack (500+ employees)
**Full Stack — All 11 tools** — Add Suricata for high-speed network IDS/IPS at data center perimeters, Snort for edge network monitoring, and OSQuery for fleet-wide endpoint monitoring — all feeding into Wazuh as the central SIEM.
**Estimated setup time:** 2–4 weeks | **Monthly maintenance:** ~20 hours (dedicated team)

---

## 💰 Cost Comparison

| Solution | Licensing Cost | This Stack |
|---|---|---|
| Splunk Enterprise | $150–$200K/year | **$0** |
| Nessus / Tenable | $5,000–$50K/year | **$0** (OpenVAS) |
| CrowdStrike Falcon | $8–$15/endpoint/month | **$0** (OSQuery + OSSEC) |
| Palo Alto Cortex XSIAM | $250K+/year | **$0** (Wazuh) |
| **Total Commercial Cost** | **$300K–$500K/year** | **$0/year** |

> ⚠️ **Note:** Open-source tools require internal expertise or managed services for setup and maintenance. Factor in engineering time when calculating total cost of ownership.

---

## 📚 Resources & Learning

| Resource | Description |
|---|---|
| [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework) | Foundation for building security programs |
| [CIS Controls](https://www.cisecurity.org/controls) | Prioritized security best practices |
| [OWASP Top 10](https://owasp.org/www-project-top-ten/) | Web application security risks |
| [CVE Database](https://cve.mitre.org) | Common vulnerabilities and exposures |
| [Shodan](https://www.shodan.io) | Check what attackers see about your org |

---

## 🤝 Contributing

Found a tool we missed? Have a better suggestion?

1. Fork this repository
2. Create a branch for your addition
3. Make your changes
4. Submit a Pull Request

All contributions welcome — corrections, new tools, use-case examples, or translations.

---

## 📄 License

This repository is licensed under the **[GNU General Public License v3.0](https://www.gnu.org/licenses/gpl-3.0)** — see the [LICENSE](LICENSE) file for details.

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue?style=flat-square)](https://www.gnu.org/licenses/gpl-3.0)

---

<div align="center">

**Built for security teams who believe open-source is not a compromise — it's a choice.**

⭐ Star this repo if it helped your team | 🐛 Open an issue for corrections | 🔀 Fork and customize for your stack

</div>
