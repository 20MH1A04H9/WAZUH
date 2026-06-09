# 🔌 Wazuh Dashboard Plugins
> MY Wazuh · Version 2.19.5 · Compatible with Wazuh Dashboard

This folder contains documentation and resources for optional Wazuh Dashboard plugins.

## Available Plugins

| Plugin | ID | Use Case |
|---|---|---|
| 🔭 Observability | `observabilityDashboards` | Monitor logs, traces, and metrics |
| 🔍 Query Workbench | `queryWorkbenchDashboards` | Run SQL/PPL queries from dashboards |
| 🤖 ML Commons | `mlCommonsDashboards` | Manage machine learning models |
| 📦 Logstash OpenSearch Output | `logstash-output-opensearch` | Ship Logstash data to OpenSearch |


## Install

```bash
# Observability
/usr/share/wazuh-dashboard/bin/opensearch-dashboards-plugin install observabilityDashboards --allow-root

# Query Workbench
/usr/share/wazuh-dashboard/bin/opensearch-dashboards-plugin install queryWorkbenchDashboards --allow-root

# ML Commons
/usr/share/wazuh-dashboard/bin/opensearch-dashboards-plugin install mlCommonsDashboards --allow-root

# Logstash OpenSearch output
/usr/share/logstash/bin/logstash-plugin install logstash-output-opensearch
```

## Verify & Restart

```bash
/usr/share/wazuh-dashboard/bin/opensearch-dashboards-plugin list
systemctl restart wazuh-dashboard
systemctl status wazuh-dashboard
```

---

> ⚠️ If install fails, download manually from [OpenSearch Plugins Docs](https://opensearch.org/docs/latest/install-and-configure/plugins/) and install via:
> ```bash
> /usr/share/wazuh-dashboard/bin/opensearch-dashboards-plugin install file:///tmp/<plugin-name>.zip --allow-root
> ```
