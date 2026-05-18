# Wazuh Multi-Tenant Lab

> Setup guide for running **two isolated organizations** on a single Wazuh instance using OpenSearch DLS, Wazuh RBAC, and Agent Group Labels.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Single Wazuh Instance                    │
│                                                             │
│  ┌──────────────────────┐    ┌──────────────────────────┐  │
│  │    Organization 1    │    │     Organization 2       │  │
│  │                      │    │                          │  │
│  │  Group: org1-group   │    │  Group: org2-group       │  │
│  │  Label: org=org1     │    │  Label: org=org2         │  │
│  │  User:  org1-user    │    │  User:  org2-user        │  │
│  │  DLS:   filters      │    │  DLS:   filters          │  │
│  │         org1 only    │    │         org2 only        │  │
│  └──────────────────────┘    └──────────────────────────┘  │
│                                                             │
│         OpenSearch Indexer  │  Wazuh Manager               │
└─────────────────────────────────────────────────────────────┘
```

**Isolation is enforced at two layers:**
- **OpenSearch DLS (Document Level Security)** — filters alert data at query time
- **Wazuh RBAC** — restricts which agent groups are visible via the API

---

## Prerequisites

- Wazuh 4.x all-in-one or distributed installation
- OpenSearch Security plugin enabled (default in Wazuh)
- Admin access to Wazuh Dashboard and Wazuh Manager CLI
- `run_as: true` enabled in `wazuh.yml`

---

## Step 1 — Create Wazuh Agent Groups

```bash
/var/ossec/bin/agent_groups -a -g org1-group
/var/ossec/bin/agent_groups -a -g org2-group
```

Verify:
```bash
/var/ossec/bin/agent_groups -l
```

Expected output:
```
Groups (2):
  org1-group (0)
  org2-group (0)
```

---

## Step 2 — Configure Agent Labels

Labels are the key that DLS filters on. Each group's `agent.conf` must declare the org label.

**Organization 1:**
```bash
nano /var/ossec/etc/shared/org1-group/agent.conf
```
```xml
<agent_config>
  <labels>
    <label key="org">org1</label>
  </labels>
</agent_config>
```

**Organization 2:**
```bash
nano /var/ossec/etc/shared/org2-group/agent.conf
```
```xml
<agent_config>
  <labels>
    <label key="org">org2</label>
  </labels>
</agent_config>
```

Restart the manager to push configs to agents:
```bash
systemctl restart wazuh-manager
```

Then restart the Wazuh agent on each endpoint to pick up the new label.

**Windows agents:**
```powershell
Restart-Service -Name WazuhSvc
```

**Linux agents:**
```bash
systemctl restart wazuh-agent
```

Verify the label is appearing in alerts (replace `<agent_id>` with actual ID):
```bash
curl -k -X GET "https://localhost:9200/wazuh-alerts-4.x-*/_search?pretty" \
  -u admin:<password> \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 1,
    "query": {"term": {"agent.id": "<agent_id>"}},
    "sort": [{"timestamp": {"order": "desc"}}],
    "_source": ["agent.name", "agent.labels", "timestamp"]
  }'
```

Expected output:
```json
"agent": {
  "name": "AGENT-NAME",
  "labels": {
    "org": "org1"
  }
}
```

---

## Step 3 — Create OpenSearch Internal Users

Navigate to **Wazuh Dashboard → OpenSearch Security → Internal Users → Create**

| Field    | Organization 1 | Organization 2 |
|----------|----------------|----------------|
| Username | org1-user      | org2-user      |
| Password | (strong)       | (strong)       |

---

## Step 4 — Create OpenSearch Roles with DLS

Navigate to **OpenSearch Security → Roles → Create Role**

### org1-role

**Index permissions:**

| Index Pattern      | Allowed Actions                                           |
|--------------------|-----------------------------------------------------------|
| `wazuh-alerts-*`   | `read`, `indices:admin/mappings/get`, `indices:admin/get` |
| `wazuh-archives-*` | `read`, `indices:admin/mappings/get`, `indices:admin/get` |
| `.kibana*`         | `read`, `write`, `indices:admin/create`                   |

**Document Level Security (DLS):**
```json
{
  "bool": {
    "filter": [
      { "match_all": {} },
      { "term": { "agent.labels.org": "org1" } }
    ]
  }
}
```

### org2-role

Same index permissions as above, different DLS:
```json
{
  "bool": {
    "filter": [
      { "match_all": {} },
      { "term": { "agent.labels.org": "org2" } }
    ]
  }
}
```

> **Note:** Use `term` (not `match_phrase`) for keyword fields — it is more precise and performant.

---

## Step 5 — Map OpenSearch Roles to Users

Navigate to **OpenSearch Security → Role Mappings**

| Role          | Users                |
|---------------|----------------------|
| org1-role     | org1-user            |
| org2-role     | org2-user            |
| kibana_user   | org1-user, org2-user |
| wazuh_ui_user | org1-user, org2-user |

> `kibana_user` is required to access the Global tenant.  
> `wazuh_ui_user` is required to use the Wazuh app panels.

---

## Step 6 — Enable `run_as` in Wazuh Config

```bash
nano /usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml
```

Set:
```yaml
run_as: true
```

---

## Step 7 — Enable Multitenancy in OpenSearch Dashboards

```bash
nano /etc/wazuh-dashboard/opensearch_dashboards.yml
```

Add or update:
```yaml
opensearch_security.multitenancy.enabled: true
opensearch_security.multitenancy.tenants.enable_global: true
opensearch_security.multitenancy.tenants.enable_private: true
opensearch_security.multitenancy.tenants.preferred: ["Private", "Global"]
opensearch_security.readonly_mode.roles: ["kibana_read_only"]
```

Restart the dashboard:
```bash
systemctl restart wazuh-dashboard
```

---

## Step 8 — Create Wazuh RBAC Policies

Navigate to **Wazuh Dashboard → Management → Security → Policies → Create**

**org1-policy:**

| Field               | Value                  |
|---------------------|------------------------|
| Policy name         | org1-policy            |
| Action              | agent:read             |
| Resource identifier | agent:group:org1-group |
| Effect              | Allow                  |

**org2-policy:**

| Field               | Value                  |
|---------------------|------------------------|
| Policy name         | org2-policy            |
| Action              | agent:read             |
| Resource identifier | agent:group:org2-group |
| Effect              | Allow                  |

---

## Step 9 — Create Wazuh RBAC Roles

Navigate to **Management → Security → Roles → Create**

| Role Name       | Policy      |
|-----------------|-------------|
| org1-wazuh-role | org1-policy |
| org2-wazuh-role | org2-policy |

---

## Step 10 — Map Wazuh Roles to Users

Navigate to **Management → Security → Roles mapping**

| Wazuh Role      | User      |
|-----------------|-----------|
| org1-wazuh-role | org1-user |
| org2-wazuh-role | org2-user |

---

## Step 11 — Assign Agents to Groups

```bash
# List all agents and their IDs
/var/ossec/bin/agent_groups -l

# Assign agent to group (replace <agent_id> with actual ID)
/var/ossec/bin/agent_groups -a -i <agent_id> -g org1-group
/var/ossec/bin/agent_groups -a -i <agent_id> -g org2-group
```

Verify assignment:
```bash
/var/ossec/bin/agent_groups -l -g org1-group
/var/ossec/bin/agent_groups -l -g org2-group
```

---

## Verification

### 1. Confirm label in alerts (as admin)
```bash
curl -k -X GET "https://localhost:9200/wazuh-alerts-4.x-*/_search?pretty" \
  -u admin:<password> \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 1,
    "sort": [{"timestamp": {"order": "desc"}}],
    "_source": ["agent.name", "agent.labels", "timestamp"]
  }'
```

### 2. Login as org1-user
- Agents Summary shows only org1 agents
- Threat Hunting shows only `org1`-labeled alerts
- No org2 data visible

### 3. Login as org2-user
- Agents Summary shows only org2 agents
- Threat Hunting shows only `org2`-labeled alerts
- No org1 data visible

### 4. Cross-check isolation
Log in as each user and confirm that searching for the other org's agent name returns **zero results**.

---

## Quick Reference

```
Organization 1
  Agent Group:     org1-group
  Label:           agent.labels.org = org1
  OpenSearch Role: org1-role  (DLS filtered)
  OpenSearch User: org1-user
  Wazuh Policy:    org1-policy
  Wazuh Role:      org1-wazuh-role

Organization 2
  Agent Group:     org2-group
  Label:           agent.labels.org = org2
  OpenSearch Role: org2-role  (DLS filtered)
  OpenSearch User: org2-user
  Wazuh Policy:    org2-policy
  Wazuh Role:      org2-wazuh-role

Both users also need:
  kibana_user      (Global tenant access)
  wazuh_ui_user    (Wazuh app access)
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Global tenant greyed out | Missing `kibana_user` role mapping | Map user to `kibana_user` in OpenSearch Security |
| Agents Summary shows no agents | Wazuh RBAC not mapped | Map user to Wazuh role under Roles mapping |
| Alerts visible but wrong org data | DLS using `match_phrase` on keyword field | Switch to `term` query in DLS |
| `too_many_nested_clauses` shard error | SQL query typed in KQL search bar | Clear the search bar; use Dev Tools for SQL queries |
| Label missing from alerts | Agent hasn't synced group config | Restart Wazuh agent on endpoint |
| 3 of 6 shards failed | No documents match DLS filter yet | Assign agents to group and restart agent |

---

## References

- [Wazuh Multi-Tenant Setup (AhmadMavali)](https://github.com/AhmadMavali/wazuh_multi_tenant)
- [OpenSearch Document Level Security](https://docs.opensearch.org/latest/security/access-control/document-level-security/)
- [OpenSearch Default Action Groups](https://docs.opensearch.org/latest/security/access-control/default-action-groups/)
- [Wazuh RBAC Documentation](https://documentation.wazuh.com/current/user-manual/api/rbac/index.html)
