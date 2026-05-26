# Wazuh Internal Security Audit

Enable and configure the built-in OpenSearch security audit logging inside the Wazuh Indexer. This captures all authentication attempts, access control decisions, index operations, and admin actions — stored directly in OpenSearch for querying via the Wazuh Dashboard.

---

## What Gets Audited

| Category | Examples |
|---|---|
| **Authentication** | Login success, login failure, invalid credentials |
| **Authorization** | Permission denied, role-based access decisions |
| **Index operations** | Create, delete, search, bulk operations |
| **Admin actions** | Role changes, user management, config changes |
| **REST requests** | All API calls hitting the indexer |

---

## Folder Structure

```
wazuh-internal-security-audit/
├── README.md                        # This file
├── config/
│   └── opensearch-audit-snippet.yml # Config snippet to add to opensearch.yml
└── docs/
    └── query-examples.md            # Useful queries to search audit logs
```

---

## Step 1 — Open the Wazuh Indexer Config

```bash
sudo nano /etc/wazuh-indexer/opensearch.yml
```

---

## Step 2 — Add the Audit Config

Append the following at the bottom of the file:

```yaml
# ── Security Audit Logging ──────────────────────────────────────
plugins.security.audit.type: internal_opensearch
```

### Optional — Extended Audit Config

For more granular control, add these additional settings:

```yaml
plugins.security.audit.type: internal_opensearch

# Audit categories to enable
plugins.security.audit.config.enabled_rest_categories:
  - FAILED_LOGIN
  - MISSING_PRIVILEGES
  - GRANTED_PRIVILEGES
  - AUTHENTICATED
  - LOGOUT

# Audit categories for transport layer
plugins.security.audit.config.enabled_transport_categories:
  - FAILED_LOGIN
  - MISSING_PRIVILEGES

# Exclude internal system users from noise
plugins.security.audit.config.ignore_users:
  - kibanaserver
  - logstash

# Exclude internal indices from noise
plugins.security.audit.config.ignore_requests:
  - "indices:monitor/*"
  - "cluster:monitor/*"
```

---

## Step 3 — Restart and Verify

```bash
sudo systemctl restart wazuh-indexer
sudo systemctl status wazuh-indexer --no-pager
```

Expected output:
```
● wazuh-indexer.service - Wazuh Indexer
     Active: active (running)
```

---

## Step 4 — Verify Audit Index is Created

```bash
curl -sk -u admin:'YOUR_PASSWORD' https://localhost:9200/_cat/indices/.opendistro_security_audit* | grep -v "^$"
```

You should see an index like:
```
green  open  .opendistro_security_audit_<date>
```

---

## Step 5 — View Audit Logs

### Via curl

```bash
curl -sk -u admin:'YOUR_PASSWORD' \
  https://localhost:9200/.opendistro_security_audit*/_search?pretty \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 10,
    "sort": [{"audit_utc_timestamp": {"order": "desc"}}],
    "query": {"match_all": {}}
  }'
```

### Filter Failed Logins Only

```bash
curl -sk -u admin:'YOUR_PASSWORD' \
  https://localhost:9200/.opendistro_security_audit*/_search?pretty \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "match": {
        "audit_category": "FAILED_LOGIN"
      }
    }
  }'
```

### Via Wazuh Dashboard

1. Go to **Wazuh Dashboard → Discover**
2. Create index pattern: `.opendistro_security_audit*`
3. Set time field: `audit_utc_timestamp`
4. Search using filters:
   - `audit_category: FAILED_LOGIN`
   - `audit_category: MISSING_PRIVILEGES`
   - `audit_request_remote_address: <IP>`

---

## Key Audit Log Fields

| Field | Description |
|---|---|
| `audit_utc_timestamp` | When the event occurred |
| `audit_category` | Event type (FAILED_LOGIN, GRANTED_PRIVILEGES, etc.) |
| `audit_request_effective_user` | User who made the request |
| `audit_request_remote_address` | Source IP address |
| `audit_rest_request_path` | API endpoint accessed |
| `audit_rest_request_method` | HTTP method (GET, POST, DELETE, etc.) |
| `audit_trace_indices` | Indices that were accessed |
| `audit_node_name` | Cluster node that processed the request |

---

## Troubleshooting

**Indexer fails to start after config change:**
```bash
# Check for YAML syntax errors
sudo journalctl -u wazuh-indexer -n 50 --no-pager | grep -i error
```

**Audit index not appearing:**
```bash
# Verify the setting was applied
grep "audit" /etc/wazuh-indexer/opensearch.yml
```

**Too many audit logs (noisy):**

Add users and request patterns to the ignore lists in the extended config above. System users like `kibanaserver` generate a lot of internal traffic.

---

## Notes

- Audit logs are stored in `.opendistro_security_audit*` indices inside the Wazuh Indexer
- Logs persist across restarts as long as the index is not deleted
- For long-term retention, configure an ISM (Index State Management) policy to roll over and archive audit indices
- `internal_opensearch` stores logs locally — no external log shipper needed
