<h1 align="center">WAZUH OpenSearch AI Assistant</h1>

<p align="center">
  AI-powered security analysis for Wazuh using OpenSearch ML Commons, Assistant, Claude, OpenAI, Gemini, and MCP.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Wazuh-4.14.x-blue"/>
  <img src="https://img.shields.io/badge/OpenSearch-2.19.x-green"/>
  <img src="https://img.shields.io/badge/AI-Claude%20%7C%20OpenAI%20%7C%20Gemini%20%7C%20groq -orange"/>
  <img src="https://img.shields.io/badge/License-MIT-lightgrey"/>
</p>

<img src="https://raw.githubusercontent.com/20MH1A04H9/WAZUH/main/assets/Aiwazuh.png" alt="Wazuh AI Banner" width="900"/>

## Overview

This repository contains a complete guide for integrating Wazuh with OpenSearch AI Assistant, ML Commons, Claude, OpenAI, and Gemini.

Production-ready setup guide for enabling **AI-powered security analysis inside Wazuh Dashboard** using **OpenSearch ML Commons**, **OpenSearch Assistant**, and an external LLM provider such as **Claude (AWS Bedrock)**, **OpenAI**, or **Gemini**.

This guide is designed for **Wazuh 4.14.x** with **OpenSearch 2.19.x**, and includes a complete installation workflow, architecture, verification, troubleshooting, and security recommendations.

---

## Architecture

```text
                   +----------------------+
                   |   Wazuh Dashboard    |
                   |  OpenSearch Dashboards |
                   +----------+-----------+
                              |
                              | Assistant UI
                              |
                   +----------v-----------+
                   |  ML Commons / Skills |
                   | Flow Framework       |
                   +----------+-----------+
                              |
                              | HTTP Connector
                              |
                   +----------v-----------+
                   |   MCP LLM Gateway    |
                   | FastAPI + LangChain  |
                   +----------+-----------+
                              |
        +---------------------+----------------------+
        |                     |                      |
        v                     v                      v
   Claude (Bedrock)       OpenAI API            Gemini API

                              |
                              |
                   +----------v-----------+
                   |   Wazuh Indexer      |
                   | wazuh-alerts-*       |
                   | vulnerabilities      |
                   | inventory indices    |
                   +----------------------+
```

---

# Components

| Component             | Purpose                                   |
| --------------------- | ----------------------------------------- |
| Wazuh Dashboard       | User interface                            |
| Wazuh Indexer         | Stores alerts, vulnerabilities, inventory |
| OpenSearch ML Commons | AI/ML framework                           |
| OpenSearch Skills     | Natural language skills                   |
| Flow Framework        | AI workflow orchestration                 |
| Assistant Dashboards  | Chat interface                            |
| MCP LLM Gateway       | Connects dashboard to external LLMs       |
| Claude/OpenAI/Gemini  | AI reasoning engine                       |

---

# Tested Versions

| Component             | Version         |
| --------------------- | --------------- |
| Wazuh                 | 4.14.3 - 4.14.6 |
| OpenSearch            | 2.19.4 - 2.19.5 |
| OpenSearch Dashboards | 2.19.5          |
| Ubuntu                | 22.04 / 24.04   |

---

# Install OpenSearch AI Plugins

## Verify OpenSearch Version

```bash
curl -k -u admin:<PASSWORD> https://localhost:9200
```

Expected:

```json
{
  "version": {
    "number": "2.19.x"
  }
}
```

---

## Install Flow Framework

```bash
cd /usr/share/wazuh-indexer/bin

sudo ./opensearch-plugin install \
org.opensearch.plugin:opensearch-flow-framework:2.19.5.0
```

---

## Install Skills Plugin

```bash
sudo ./opensearch-plugin install \
org.opensearch.plugin:opensearch-skills:2.19.5.0
```

---

## Restart Indexer

```bash
sudo systemctl restart wazuh-indexer
sudo systemctl status wazuh-indexer
```

---

## Verify Plugins

```bash
/usr/share/wazuh-indexer/bin/opensearch-plugin list
```

Expected:

```
opensearch-flow-framework
opensearch-skills
opensearch-security
opensearch-ml
```

---

# Install Dashboard AI Plugins

Download matching OpenSearch Dashboards package:

```bash
cd /tmp

curl -O https://artifacts.opensearch.org/releases/bundle/opensearch-dashboards/2.19.5/opensearch-dashboards-2.19.5-linux-x64.tar.gz

tar -xvzf opensearch-dashboards-2.19.5-linux-x64.tar.gz
```
or You can execute all of these commands in one step.
```bash
cd /tmp
curl -O https://artifacts.opensearch.org/releases/bundle/opensearch-dashboards/2.19.5/opensearch-dashboards-2.19.5-linux-x64.tar.gz
tar -xvzf opensearch-dashboards-2.19.5-linux-x64.tar.gz

# stop dashboard before touching plugin files
systemctl stop wazuh-dashboard

# remove the suspect/incomplete assistantDashboards and replace both cleanly
rm -rf /usr/share/wazuh-dashboard/plugins/assistantDashboards
cp -r /tmp/opensearch-dashboards-2.19.5/plugins/assistantDashboards /usr/share/wazuh-dashboard/plugins/
cp -r /tmp/opensearch-dashboards-2.19.5/plugins/opensearch-observability /usr/share/wazuh-dashboard/plugins/

chown -R wazuh-dashboard:wazuh-dashboard \
  /usr/share/wazuh-dashboard/plugins/assistantDashboards \
  /usr/share/wazuh-dashboard/plugins/opensearch-observability
```

---

## Stop Dashboard

```bash
sudo systemctl stop wazuh-dashboard
```

---

## Copy AI Plugins

```bash
sudo cp -r /tmp/opensearch-dashboards-2.19.5/plugins/assistantDashboards \
    /usr/share/wazuh-dashboard/plugins/

sudo cp -r /tmp/opensearch-dashboards-2.19.5/plugins/observabilityDashboards \
    /usr/share/wazuh-dashboard/plugins/

sudo cp -r /tmp/opensearch-dashboards-2.19.5/plugins/mlCommonsDashboards \
    /usr/share/wazuh-dashboard/plugins/
```

---

## Set Permissions

```bash
sudo chown -R wazuh-dashboard:wazuh-dashboard \
/usr/share/wazuh-dashboard/plugins/assistantDashboards \
/usr/share/wazuh-dashboard/plugins/observabilityDashboards \
/usr/share/wazuh-dashboard/plugins/mlCommonsDashboards
```

---

# Enable Assistant

Modify the /etc/wazuh-dashboard/opensearch_dashboards.yml configuration file.

```bash
cat >> /etc/wazuh-dashboard/opensearch_dashboards.yml << 'EOF'
assistant.chat.enabled: true
observability.query_assist.enabled: true
EOF

systemctl start wazuh-dashboard
journalctl -u wazuh-dashboard -n 80 --no-pager -f
```
or Modify the config settings manually 

Add:

```yaml
assistant.chat.enabled: true
observability.query_assist.enabled: true
```

Save and exit.

---

## Start Dashboard

```bash
sudo systemctl start wazuh-dashboard
sudo systemctl status wazuh-dashboard
```

---

# Install Wazuh AI Assistant

Clone official integration:

```bash
cd /opt

git clone https://github.com/wazuh/integrations.git /tmp/integrations

sudo cp -r /tmp/integrations/integrations/AI_assistant /opt/AI_assistant

rm -rf /tmp/integrations
```

---

# Configure MCP LLM Gateway

Example:

```bash
cd /opt/AI_assistant

cp .env.example .env
```

Example `.env`:

```env
LLM_PROVIDER=openai
OPENAI_API_KEY=YOUR_API_KEY

# Claude (Bedrock)
AWS_REGION=ap-south-1
BEDROCK_MODEL=anthropic.claude-3-5-haiku

# Gemini
GOOGLE_API_KEY=YOUR_KEY
```

---

## Start Gateway

```bash
docker compose up -d
```

Verify:

```bash
docker ps
```

---

# Configure ML Commons Connector

Create connector:

```bash
curl -k -u admin:<PASSWORD> \
-X PUT https://localhost:9200/.plugins-ml-config/_doc/os_chat \
-H 'Content-Type: application/json' \
-d '
{
  "type": "http",
  "name": "OpenAI Chat Connector",
  "description": "Connector for OpenAI GPT",
  "parameters": {
    "endpoint": "http://AI_GATEWAY:8000/chat"
  }
}'
```

---

# Verify Assistant

Open:

```
https://YOUR_WAZUH_SERVER
```

Navigate:

```
Wazuh Dashboard
    -> Assistant
```

Test prompt:

```
Summarize the last 10 critical security alerts.
```

Expected behavior:

* Reads `wazuh-alerts-*`
* Identifies critical events
* Groups by MITRE ATT&CK
* Returns natural language summary

Example:

> The environment generated 10 critical alerts in the last hour. The majority are brute-force SSH attempts targeting Linux servers. MITRE techniques observed include T1110 (Brute Force) and T1078 (Valid Accounts).

---

# Useful AI Queries

## Alert Analysis

```
Explain this Wazuh alert.
```

## MITRE Mapping

```
Map the latest alerts to MITRE ATT&CK techniques.
```

## Threat Hunting

```
Show all hosts communicating with suspicious IP addresses.
```

## Vulnerability Summary

```
Summarize critical vulnerabilities across all Linux servers.
```

## Agent Inventory

```
List Windows endpoints missing security patches.
```

---

# Validation Commands

## Cluster Health

```bash
curl -k -u admin:<PASSWORD> \
https://localhost:9200/_cluster/health?pretty
```

---

## Plugin List

```bash
curl -k -u admin:<PASSWORD> \
https://localhost:9200/_cat/plugins?v
```

---

## Dashboard Logs

```bash
journalctl -u wazuh-dashboard -f
```

---

## Indexer Logs

```bash
journalctl -u wazuh-indexer -f
```

---

# Troubleshooting

## Dashboard Fails to Start

Check logs:

```bash
journalctl -u wazuh-dashboard -n 100 --no-pager
```

Common causes:

### Duplicate YAML Keys

Incorrect:

```yaml
assistant.chat.enabled: true
assistant.chat.enabled: true
```

Remove duplicates.

---

### Wrong Plugin Version

Ensure plugin version exactly matches OpenSearch version.

For 2.19.5:

```
2.19.5.0
```

Not:

```
2.19.0.0
```

---

### Missing Plugin Dependencies

Verify:

```
assistantDashboards
observabilityDashboards
mlCommonsDashboards
```

---

# Security Hardening

## Use HTTPS Everywhere

* Wazuh Dashboard
* Wazuh Indexer
* MCP Gateway

---

## Store API Keys Securely

Avoid plain-text secrets.

Use:

* Docker secrets
* AWS Secrets Manager
* Azure Key Vault
* HashiCorp Vault

---

## Restrict AI Gateway Access

Firewall example:

```bash
ufw allow from WAZUH_DASHBOARD_IP to any port 8000
```

---

## Audit AI Requests

Log:

* Prompt
* User
* Timestamp
* LLM provider
* Response status

---

# Production Recommendations

| Deployment Size | CPU | RAM    |
| --------------- | --- | ------ |
| Lab             | 4   | 16 GB  |
| 300 endpoints   | 8   | 32 GB  |
| 1000 endpoints  | 16  | 64 GB  |
| 2000+ endpoints | 32+ | 128 GB |

---

# Community MCP Servers

Alternative external integrations:

| Project                      | Notes                     |
| ---------------------------- | ------------------------- |
| gbrigandi/mcp-server-wazuh   | Rust                      |
| gensecaihq/Wazuh-MCP-Server  | Python, 29 security tools |
| socfortress/wazuh-mcp-server | FastMCP                   |

These allow querying Wazuh directly from **Claude Desktop** or other MCP-compatible AI clients.

---

# References

* https://github.com/wazuh/integrations
* https://opensearch.org/docs/latest/ml-commons-plugin/
* https://opensearch.org/docs/latest/search-plugins/assistant/
* https://opensearch.org/docs/latest/search-plugins/flow-framework/

---

## Author

**VISWA**

Security Engineer | Wazuh | OpenSearch | Azure Databricks | AWS | Kubernetes | AI-assisted SOC Engineering

---
