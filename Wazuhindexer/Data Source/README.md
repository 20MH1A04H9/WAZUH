# 🔍 Wazuh OpenSearch — Data Source Configuration

> End-to-end guide for enabling the **OpenSearch Data Source plugin** in the Wazuh Dashboard, connecting it to the local OpenSearch instance, and resolving index health issues on a single-node cluster.

<p align="center">
  <img src="https://img.shields.io/badge/Wazuh_Dashboard-4.14.5-006DFF?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/OpenSearch-2.x-005EB8?style=for-the-badge&logo=opensearch&logoColor=white"/>
  <img src="https://img.shields.io/badge/Status-Active-brightgreen?style=for-the-badge"/>
</p>

---

## 📋 Table of Contents

- [Overview](#-overview)
- [Prerequisites](#-prerequisites)
- [Step 1 — Enable OpenSearch Data Source Plugin](#step-1--enable-opensearch-data-source-plugin)
- [Step 2 — Connect Data Source via UI](#step-2--connect-data-source-via-ui)
- [Result Summary](#-result-summary)
- [References](#-references)

---

## 🧭 Overview

The default Wazuh Dashboard installation does **not** expose the OpenSearch data source option — it must be explicitly enabled via configuration.

This guide covers:

```
1. Enable data_source plugin in opensearch_dashboards.yml
2. Disable TLS verification for self-signed certificates
3. Connect OpenSearch as a named data source via the Dashboard UI
4. Fix Yellow index health on single-node clusters (replicas → 0)
5. Apply a default index template to prevent future Yellow indices
```

---

## ✅ Prerequisites

| Requirement | Detail |
|---|---|
| **Wazuh Dashboard** | Running (`systemctl status wazuh-dashboard`) |
| **OpenSearch** | Accessible at `https://127.0.0.1:9200` |
| **Credentials** | Admin username and password available |
| **Access** | Root or sudo access to the Wazuh server |

---

## Step 1 — Enable OpenSearch Data Source Plugin

### 1.1 Verify Existing Config

Check whether data source settings already exist:

```bash
cat /etc/wazuh-dashboard/opensearch_dashboards.yml | grep -i "data_source\|datasource"
```

If the command returns **no output** → the plugin is not yet enabled. Proceed to the next step.

---

### 1.2 Append Data Source Configuration

```bash
cat >> /etc/wazuh-dashboard/opensearch_dashboards.yml << 'EOF'

# OpenSearch Data Source
data_source.enabled: true
data_source.encryption.wrappingKeyName: 'changeme'
data_source.encryption.wrappingKeyNamespace: 'changeme'
data_source.encryption.wrappingKey: [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
EOF
```

Verify the lines were appended:

```bash
tail -8 /etc/wazuh-dashboard/opensearch_dashboards.yml
```

---

### 1.3 Disable TLS Verification

The data source plugin uses its own SSL context. Since the local OpenSearch uses a self-signed certificate, TLS verification must be disabled:

```bash
cat >> /etc/wazuh-dashboard/opensearch_dashboards.yml << 'EOF'

data_source.ssl.verificationMode: none
EOF
```

> [!WARNING]
> `verificationMode: none` disables certificate validation. Use only in trusted internal environments with self-signed certificates.

---

### 1.4 Restart the Dashboard Service

```bash
systemctl restart wazuh-dashboard && \
systemctl status wazuh-dashboard --no-pager
```

After restart the **OpenSearch** tile will appear under:

```
Dashboards Management → Data Sources → Create Data Source
```

---

## Step 2 — Connect Data Source via UI

Open the Wazuh Dashboard in your browser and follow these steps:

| # | Action |
|---|---|
| **1** | Navigate to: **Dashboards Management → Data Sources → Create Data Source** |
| **2** | Click the **OpenSearch** tile |
| **3** | Set **Title**: `Wazuh-Local` |
| **4** | Set **Endpoint URL**: `https://127.0.0.1:9200` |
| **5** | Set **Authentication Method**: `Username & Password` |
| **6** | Enter **Username**: `admin` and your admin password |
| **7** | Click **Test Connection** |
| **8** | Click the **Default ★** star (top-right) → **Save** |

### Expected Test Connection Result

```
✅ Connecting to the endpoint using the provided authentication method was successful.
```
---

## 🗂 Final Config State

The following lines are appended to `/etc/wazuh-dashboard/opensearch_dashboards.yml`:

```yaml
# OpenSearch Data Source
data_source.enabled: true
data_source.encryption.wrappingKeyName: 'changeme'
data_source.encryption.wrappingKeyNamespace: 'changeme'
data_source.encryption.wrappingKey: [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
data_source.ssl.verificationMode: none
```

---


## 📚 References

| Resource | Link |
|---|---|
| 📘 Wazuh Dashboard Config | [documentation.wazuh.com/dashboard](https://documentation.wazuh.com/current/user-manual/wazuh-dashboard/index.html) |
| 🔍 OpenSearch Data Sources | [opensearch.org/docs/datasources](https://opensearch.org/docs/latest/dashboards/management/data-sources/) |
| 🗂️ OpenSearch Index Management | [opensearch.org/docs/index-settings](https://opensearch.org/docs/latest/api-reference/index-apis/put-settings/) |
| 🔐 OpenSearch Security | [opensearch.org/docs/security](https://opensearch.org/docs/latest/security/) |
