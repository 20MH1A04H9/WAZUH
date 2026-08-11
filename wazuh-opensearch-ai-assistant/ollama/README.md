# Wazuh OpenSearch Assistant — Setup & Troubleshooting Log

**Host:** wazuh-host (`wazuh-host.example.com`)
**Wazuh version:** 4.14.6
**OpenSearch (indexer) version:** 2.19.5
**Dashboard:** OpenSearch Dashboards fork bundled with Wazuh

---

## 1. Overview

This document records the full process of enabling the built-in **OpenSearch Assistant** (AI chat) inside the Wazuh dashboard, backed by a Groq-hosted LLaMA 3.3 70B model, with tool access into live Wazuh alert data. It includes every issue hit along the way and the exact fix applied, so future changes (or a rebuild) don't require re-discovering the same problems.

**End state:** A working "Ask a question" chat panel in the Wazuh dashboard, backed by an ML Commons `conversational` agent (`app_type: os_chat`), with three tools:
- `MLModelTool` — general chat, no data access
- `WazuhAlertStats` (SearchIndexTool) — accurate precomputed alert counts/severity breakdown, refreshed every 5 minutes via cron
- `WazuhAlertsSearch` (SearchIndexTool) — retrieves real individual alert documents

---

## 2. Plugin Installation (Indexer Side)

OpenSearch plugin installs require an **exact patch-version match** with the running core. Initial attempts using `2.19.0.0` failed because the indexer runs `2.19.5`.

```bash
cd /usr/share/wazuh-indexer/bin
./opensearch-plugin install org.opensearch.plugin:opensearch-flow-framework:2.19.5.0
./opensearch-plugin install org.opensearch.plugin:opensearch-skills:2.19.5.0
systemctl restart wazuh-indexer
```

Verify:
```bash
/usr/share/wazuh-indexer/bin/opensearch-plugin list
```

**How to find the exact required version if unsure:**
```bash
cat /usr/share/wazuh-indexer/plugins/opensearch-security/plugin-descriptor.properties | grep opensearch.version
```

---

## 3. Dashboard Plugin Installation

The indexer-side plugins (`opensearch-flow-framework`, `opensearch-skills`) are **not** the same as the dashboard UI plugins. The chat panel itself lives in separate Dashboards plugins that must be pulled from a matching OpenSearch Dashboards release bundle.

```bash
cd /tmp
curl -O https://artifacts.opensearch.org/releases/bundle/opensearch-dashboards/2.19.5/opensearch-dashboards-2.19.5-linux-x64.tar.gz
tar -xvzf opensearch-dashboards-2.19.5-linux-x64.tar.gz
ls /tmp/opensearch-dashboards-2.19.5/plugins/
```

**Naming note:** older blog posts/tutorials reference `opensearch-observability` and `opensearch-ml` — in the 2.19.5 bundle these are named differently:
- `observabilityDashboards` (not `opensearch-observability`)
- `mlCommonsDashboards` (not `opensearch-ml`)
- `assistantDashboards` (correct name, was already present from an earlier partial attempt)

```bash
systemctl stop wazuh-dashboard
rm -rf /usr/share/wazuh-dashboard/plugins/assistantDashboards   # remove suspect partial copy
cp -r /tmp/opensearch-dashboards-2.19.5/plugins/assistantDashboards /usr/share/wazuh-dashboard/plugins/
cp -r /tmp/opensearch-dashboards-2.19.5/plugins/observabilityDashboards /usr/share/wazuh-dashboard/plugins/
cp -r /tmp/opensearch-dashboards-2.19.5/plugins/mlCommonsDashboards /usr/share/wazuh-dashboard/plugins/
chown -R wazuh-dashboard:wazuh-dashboard \
  /usr/share/wazuh-dashboard/plugins/assistantDashboards \
  /usr/share/wazuh-dashboard/plugins/observabilityDashboards \
  /usr/share/wazuh-dashboard/plugins/mlCommonsDashboards
```

## 4. Dashboard Config

```bash
cat >> /etc/wazuh-dashboard/opensearch_dashboards.yml << 'EOF'
assistant.chat.enabled: true
observability.query_assist.enabled: true
EOF
systemctl start wazuh-dashboard
```

---

## 5. LLM Backend — Groq Connector & Model

An external connector to Groq (`llama-3.3-70b-versatile`) was already registered and confirmed **Responding** in *Machine Learning → Overview*.

- **Model ID:** `<groq_model_id>` (Groq LLaMA 3.3 70B — current, in use)
- Earlier model IDs `<superseded_model_id>` were superseded during setup — no longer referenced by the active agent.

---

## 6. Agent Registration — Version History

Agents cannot be edited in place in ML Commons; each fix required registering a new agent version and repointing the `os_chat` config. Kept here for traceability.

| Version | agent_id | Change | Result |
|---|---|---|---|
| v1 | `<agent_id_v1>` | Initial conversational agent, `MLModelTool` only | Worked but returned raw Groq JSON (no response_filter) |
| v2 | `<agent_id_v2>` | Added `response_filter: $.choices[0].message.content` | Clean text output confirmed |
| v3 | `<agent_id_v3>` | Added `PPLTool` + `SearchIndexTool` for `wazuh-alerts-*` | Agent didn't invoke tools — see §8 |
| v4 | `<agent_id_v4>` | Removed custom `llm.parameters.prompt` override | **Fixed tool-invocation** — ReAct reasoning restored |
| v5 | (superseded quickly) | Scoped PPLTool/SearchIndexTool to single-day index | Reduced but didn't fix PPLTool token overrun |
| v6 | `<agent_id_v6>` | Same, re-tested after Groq TPM window reset | PPLTool still exceeded 12K TPM on full-day index |
| v7 | `<agent_id_v7>` | Fixed `SearchIndexTool` description with `index`+`query` example | Wrong contract — see §9 |
| v8 | `<agent_id_v8>` | Corrected `SearchIndexTool` to real single `input` JSON-string schema | Schema now correct but **`size:0` returns empty always** |
| **v9** | *(register per §11)* | Added `WazuhAlertStats` tool pointed at precomputed stats doc | Accurate counts without any LLM query generation |

**Current live config:**
```bash
curl -k --cert /etc/wazuh-indexer/certs/admin.pem --key /etc/wazuh-indexer/certs/admin-key.pem \
  https://localhost:9200/.plugins-ml-config/_doc/os_chat
```

---

## 7. Registering `os_chat` Root Agent (requires cert auth, not basic auth)

The `.plugins-ml-config` system index rejects basic auth (`403 no permissions`) even for the `admin` user — it requires the **admin mTLS client cert**, configured separately from the dashboard/API login.

```bash
curl -k --cert /etc/wazuh-indexer/certs/admin.pem --key /etc/wazuh-indexer/certs/admin-key.pem \
  -X PUT "https://localhost:9200/.plugins-ml-config/_doc/os_chat" \
  -H "Content-Type: application/json" \
  -d '{"type":"os_chat_root_agent","configuration":{"agent_id":"<agent_id>"}}'
```

---

## 8. Bug — Agent Not Invoking Tools (v3)

**Symptom:** Agent responded conversationally to data questions instead of calling `PPLTool`/`SearchIndexTool`. `verbose:true` showed no `Thought:`/`Action:` trace at all.

**Root cause:** A custom `llm.parameters.prompt` string was set at registration time. The `conversational` agent type relies on an internal ReAct-style prompt scaffold (`Thought: / Action: / Action Input:`) to know when to call tools — supplying a custom `prompt` overrides that scaffold entirely, so the model never learns it should use that format.

**Fix:** Remove the custom `prompt` field from `llm.parameters` and let the agent's built-in ReAct template do its job. (v4)

---

## 9. Bug — `SearchIndexTool` Wrong Parameter Schema

**Symptom:** Tool executed without error but always returned an **empty string**, regardless of query content.

**Root cause:** `SearchIndexTool` does **not** accept separate `index` and `query` keys in `action_input`. Per official OpenSearch docs, it takes exactly **one parameter, `input`**, whose value is a single JSON *string* containing both `index` and `query` nested inside:
```json
{"input": "{\"index\": \"my-index\", \"query\": {...}}"}
```
Our earlier tool description told the model an incorrect two-key contract — the model produced plausible-looking JSON that the tool silently couldn't parse.

**Fix:** Corrected tool description to specify the real single-string `input` schema. (v8)

---

## 10. Bug — `SearchIndexTool` Always Empty With `size:0` / Aggregations

**Symptom:** Even with the schema fixed, count-style queries (`size:0` + `track_total_hits` or aggregations) still returned empty. Isolated with a **flow agent** (no LLM involved) to rule out prompt issues — confirmed the tool itself, not the agent, was the cause.

**Root cause:** `SearchIndexTool` only ever formats and returns `hits.hits[]` (actual documents). It does not surface `hits.total` or aggregation results. With `size:0`, there are no hits to format, so it always returns empty — this is a hard limitation of the tool, not a query bug. Confirmed working correctly for real document retrieval (`size:3` returned real alert docs with full field data).

**Fix / workaround:** Do not use `SearchIndexTool` (or `PPLTool`) for counting. Built a separate precomputed-stats pipeline instead — see §12.

---

## 11. Bug — Groq Token-Per-Minute (TPM) Rate Limit on `PPLTool`

**Symptom:**
```
Request too large for model llama-3.3-70b-versatile ... TPM Limit 12000, Requested 17505-18434
```

**Root cause:** `PPLTool` sends the target index's full field mapping to the LLM so it can write valid PPL against real field names. Wazuh alert documents are extremely wide (`rule.*`, `decoder.*`, `agent.*`, `GeoLocation.*`, `syscheck.*`, MITRE fields, compliance tags, etc. — 200+ fields). This alone exceeds Groq's free-tier 12,000 TPM cap in a single call, regardless of document count or date-scoping the index.

**Not fixed** — remaining open item. Options, not yet implemented:
1. Upgrade Groq to Dev Tier (raises TPM cap) — `https://console.groq.com/settings/billing`
2. Point `PPLTool`'s `model_id` at a different, higher-limit provider
3. Avoid `PPLTool` entirely for structured/known query types (see §12 approach)

---

## 12. Attempted Fix — Local Ollama for PPL Generation

**Goal:** Avoid Groq's TPM cap by running `PPLTool`'s model locally via Ollama.

### 12.1 System check (before installing)
```
CPU: AMD EPYC 7763, 8 vCPU
RAM: 31Gi total, 27Gi available
Disk: 42G free on /
GPU: none
```
Sufficient for a small quantized model on CPU (not latency-critical since PPL generation is a background tool call, not live chat).

### 12.2 Install
```bash
curl -fsSL https://ollama.com/install.sh | sh
ollama pull llama3.1:8b
```

### 12.3 Connector registration — issues hit, in order

**Issue A — missing credential block:**
```
illegal_argument_exception: Connector credential is null or empty list
```
Fix: added a dummy `credential` object (Ollama needs no real auth, but ML Commons requires the field to be non-empty):
```json
"credential": {"dummy_key": "not_required_for_local_ollama"}
```

**Issue B — untrusted endpoint:**
```
Connector URL is not matching the trusted connector endpoint regex, URL is: http://localhost:11434/api/generate
```
Fix: added `^http://localhost:11434/.*$` to `plugins.ml_commons.trusted_connector_endpoints_regex`.

> ⚠️ **Near-incident:** The first attempt at this fix used a literal placeholder (`"<existing entries...>"`) instead of the real existing values, which **overwrote the entire persistent allowlist** — silently dropping the working entries for Groq, OpenAI, Anthropic, and Deepseek. This was caught immediately by re-querying `_cluster/settings?include_defaults=true` and comparing against the AWS-only defaults that appeared. Recovered by explicitly reconstructing the full list (Groq/OpenAI/Anthropic/Deepseek + all AWS defaults + the new Ollama entry) in one PUT. **Verified the live Groq agent still worked immediately after** — no actual downtime occurred, but this is a reminder to always paste full literal values into cluster-settings PUTs, never placeholders.

Current full trusted list:
```
^https://api\.groq\.com/.*$
^https://api\.openai\.com/.*$
^https://api\.anthropic\.com/.*$
^https://api\.deepseek\.com/.*$
^https://runtime\.sagemaker\..*[a-z0-9-]\.amazonaws\.com/.*$
^https://api\.sagemaker\..*[a-z0-9-]\.amazonaws\.com/.*$
^https://api\.cohere\.ai/.*$
^https://bedrock-runtime\..*[a-z0-9-]\.amazonaws\.com/.*$
^https://bedrock-agent-runtime\..*[a-z0-9-]\.amazonaws\.com/.*$
^https://bedrock\..*[a-z0-9-]\.amazonaws\.com/.*$
^https://textract\..*[a-z0-9-]\.amazonaws\.com$
^https://comprehend\..*[a-z0-9-]\.amazonaws\.com$
^https://rekognition(-fips)?\..*[a-z0-9-]\.amazonaws\.com$
^http://localhost:11434/.*$
```

**Issue C — private IP blocked (SSRF protection):**
```
illegal_argument_exception: Remote inference host name has private ip address: localhost
```
Fix:
```bash
curl -k -u admin:<password> -X PUT "https://localhost:9200/_cluster/settings" \
  -H "Content-Type: application/json" \
  -d '{"persistent": {"plugins.ml_commons.connector.private_ip_enabled": true}}'
```
Note: this is a cluster-wide relaxation of SSRF protection for **all** ML connectors, not just this one. Acceptable on a single-node box under our control; would need reconsideration in a multi-tenant setup.

### 12.4 Connector / Model IDs
- **Connector ID:** `<ollama_connector_id>`
- **Model ID:** `<ollama_model_id>`

### 12.5 Result — Not adopted for PPL generation

`llama3.1:8b` predict test succeeded (200 OK) but the content was **factually wrong on both test prompts**:
- Asked to write a PPL query → returned invalid Elasticsearch **Painless** script syntax, not PPL.
- Asked what PPL stands for → confidently invented **"Per-Query Pricing Layer"** instead of the correct answer, "Piped Processing Language."

**Conclusion:** A bare `llama3.1:8b` has no real knowledge of OpenSearch PPL syntax and produces confident, plausible-looking wrong answers — worse for a SOC tool than an honest rate-limit error, since a wrong alert count looks legitimate. **Not wired into `PPLTool`.** Connector/model remain registered but unused; can be revisited with a larger/fine-tuned model later.

---

## 13. Working Fix — Precomputed Stats Pipeline (adopted approach)

Instead of relying on any LLM to write correct counting queries, alert statistics are computed by a plain shell script on a schedule and stored as a single document the agent can fetch directly (via `SearchIndexTool`, which — per §10 — works reliably for direct document retrieval).

### 13.1 Stats index
```bash
curl -k -u admin:<password> -X PUT "https://localhost:9200/assistant-daily-stats" \
  -H "Content-Type: application/json" \
  -d '{"mappings": {"properties": {
    "date": {"type": "keyword"},
    "total_alerts": {"type": "integer"},
    "critical": {"type": "integer"},
    "high": {"type": "integer"},
    "medium": {"type": "integer"},
    "low": {"type": "integer"},
    "updated_at": {"type": "date"}
  }}}'
```

### 13.2 Refresh script — `/usr/local/bin/wazuh_stats_refresh.sh`

**Important:** first version scoped only to the single calendar-day index (`wazuh-alerts-4.x-YYYY.MM.DD`), which undercounted vs. the dashboard's actual rolling 24h panel (dashboard spans midnight into the previous day's index too). Corrected to query the wildcard pattern with a real `now-24h` range filter on `timestamp`, matching the dashboard's own methodology.

```bash
#!/bin/bash
CRED="admin:<password>"
INDEX_PATTERN="wazuh-alerts-4.x-*"

get_count() {
  curl -sk -u "$CRED" -X POST "https://localhost:9200/${INDEX_PATTERN}/_count" \
    -H "Content-Type: application/json" -d "$1" | grep -o '"count":[0-9]*' | cut -d: -f2
}

RANGE='{"range":{"timestamp":{"gte":"now-24h"}}}'
TOTAL=$(get_count "{\"query\":${RANGE}}")
CRITICAL=$(get_count "{\"query\":{\"bool\":{\"filter\":[${RANGE},{\"range\":{\"rule.level\":{\"gte\":15}}}]}}}")
HIGH=$(get_count "{\"query\":{\"bool\":{\"filter\":[${RANGE},{\"range\":{\"rule.level\":{\"gte\":12,\"lt\":15}}}]}}}")
MEDIUM=$(get_count "{\"query\":{\"bool\":{\"filter\":[${RANGE},{\"range\":{\"rule.level\":{\"gte\":7,\"lt\":12}}}]}}}")
LOW=$(get_count "{\"query\":{\"bool\":{\"filter\":[${RANGE},{\"range\":{\"rule.level\":{\"gte\":0,\"lt\":7}}}]}}}")

curl -sk -u "$CRED" -X PUT "https://localhost:9200/assistant-daily-stats/_doc/current" \
  -H "Content-Type: application/json" \
  -d "{\"date\":\"$(date +%Y-%m-%d)\",\"total_alerts\":${TOTAL:-0},\"critical\":${CRITICAL:-0},\"high\":${HIGH:-0},\"medium\":${MEDIUM:-0},\"low\":${LOW:-0},\"updated_at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
```

### 13.3 Cron schedule (every 5 minutes)
```bash
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/wazuh_stats_refresh.sh") | crontab -
```

### 13.4 Validation
Compared against the dashboard's own "Last 24 Hours Alerts" panel:

| Metric | Dashboard panel | Script output | 
|---|---|---|
| Medium severity | 872 | 869 |
| Low severity | 12,944 | 12,903 |

Small variance is expected (few minutes of new alerts between screenshot and script run) — confirms the corrected logic is accurate.

---

## 14. Current Agent Tools (v9)

| Tool | Name | Purpose |
|---|---|---|
| `MLModelTool` | — | General Wazuh/security knowledge questions, no data access |
| `SearchIndexTool` | `WazuhAlertStats` | Fetches the precomputed `assistant-daily-stats/current` doc — accurate counts, no LLM query generation |
| `SearchIndexTool` | `WazuhAlertsSearch` | Retrieves real individual alert documents (e.g. "find alerts from IP X") — not for counting |

`PPLTool` **removed** from the active agent due to unresolved TPM limit (§11) and Ollama's demonstrated unreliability (§12.5). Can be reintroduced if Groq is upgraded to a paid tier.

---

## 15. Known Open Items / Next Steps

1. **Groq TPM limit unresolved** — `PPLTool` cannot be safely used until either Groq is upgraded (Dev Tier) or a properly PPL-capable model is sourced for it. Currently not wired into the agent.
2. **Ollama connector registered but unused** — `llama3.1:8b` proved unreliable for PPL/OpenSearch DSL generation (hallucinated syntax and wrong facts in testing). Left in place in case a better-suited local model is tried later.
3. **Daily index rollover** — the `assistant-daily-stats` approach is now rollover-safe (wildcard + time-range), but if any other tool/script later hardcodes a specific date-based index name (as early PPLTool/SearchIndexTool versions did), it will silently break at midnight. Audit for this before reusing older command history from this log.
4. **⚠️ Admin password exposure** — the indexer admin password (`<REDACTED_ROTATE_ME>`) was pasted in plaintext across this conversation/log more than once. **Rotate it** via:
   ```bash
   /usr/share/wazuh-indexer/plugins/opensearch-security/tools/hash.sh -p '<new_password>'
   # put hash into /etc/wazuh-indexer/opensearch-security/internal_users.yml
   export JAVA_HOME=/usr/share/wazuh-indexer/jdk
   bash /usr/share/wazuh-indexer/plugins/opensearch-security/tools/securityadmin.sh \
     -cd /etc/wazuh-indexer/opensearch-security/ \
     -icl -key /etc/wazuh-indexer/certs/admin-key.pem \
     -cert /etc/wazuh-indexer/certs/admin.pem -cacert /etc/wazuh-indexer/certs/root-ca.pem -nhnv
   ```
   Update this doc and any scripts (`wazuh_stats_refresh.sh`) with the new password after rotating.
5. **`private_ip_enabled: true`** is now a permanent cluster setting — revisit if this cluster ever becomes multi-tenant or exposed beyond trusted admins.

---

## 16. How To — Register a New Model & Agent (Reusable Procedure)

Reference procedure for registering any future LLM connector/model, or replacing the current agent. Follow in order — each step depends on the ID returned by the one before it.

### 16.1 Register a connector

A connector defines how OpenSearch talks to the LLM backend (URL, auth, request/response shape). Every remote model needs one first.

```bash
curl -k -u admin:<password> -X POST "https://localhost:9200/_plugins/_ml/connectors/_create" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "<connector name>",
    "description": "<what this connects to>",
    "version": 1,
    "protocol": "http",
    "parameters": { "endpoint": "<host>", "model": "<model name at provider>" },
    "credential": { "<key_name>": "<api_key_or_dummy_value>" },
    "actions": [
      {
        "action_type": "predict",
        "method": "POST",
        "url": "https://${parameters.endpoint}/<path>",
        "headers": { "Content-Type": "application/json" },
        "request_body": "{ \"model\": \"${parameters.model}\", \"messages\": ${parameters.messages} }"
      }
    ]
  }'
```
Returns a `connector_id`. Two things that block this step if skipped:
- **`credential` must be non-empty** even for connectors needing no real auth (§12.3, Issue A).
- **The target URL's host must match `plugins.ml_commons.trusted_connector_endpoints_regex`**, and if it's a private/loopback IP, `plugins.ml_commons.connector.private_ip_enabled` must also be `true` (§12.3, Issues B & C). Check/update via:
  ```bash
  curl -k -u admin:<password> "https://localhost:9200/_cluster/settings?include_defaults=true&filter_path=**.trusted_connector_endpoints_regex"
  ```
  **Always paste the full existing list back explicitly when updating this setting — never a placeholder — or you will silently wipe every other provider's access (see the near-incident in §12.3).**

### 16.2 Register the model against the connector

```bash
curl -k -u admin:<password> -X POST "https://localhost:9200/_plugins/_ml/models/_register" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "<model name>",
    "function_name": "remote",
    "description": "<description>",
    "connector_id": "<connector_id from 16.1>"
  }'
```
Returns a `task_id`.

### 16.3 Check registration status and get the model_id

```bash
curl -k -u admin:<password> "https://localhost:9200/_plugins/_ml/tasks/<task_id>"
```
Look for `"state":"COMPLETED"` and copy the `model_id`.

### 16.4 Deploy the model

```bash
curl -k -u admin:<password> -X POST "https://localhost:9200/_plugins/_ml/models/<model_id>/_deploy"
```

### 16.5 Test the model directly before building an agent on it

```bash
curl -k -u admin:<password> -X POST "https://localhost:9200/_plugins/_ml/models/<model_id>/_predict" \
  -H "Content-Type: application/json" \
  -d '{"parameters": {"prompt": "hello"}}'
```
Confirm the response actually makes sense (§12.5 — a 200 OK is not proof of correctness; the Ollama model returned clean-looking but factually wrong answers).

### 16.6 Register the conversational agent

```bash
curl -k -u admin:<password> -X POST "https://localhost:9200/_plugins/_ml/agents/_register" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "<agent name>",
    "type": "conversational",
    "description": "<description>",
    "llm": {
      "model_id": "<model_id>",
      "parameters": {
        "max_iteration": 5,
        "response_filter": "$.choices[0].message.content"
      }
    },
    "memory": { "type": "conversation_index" },
    "tools": [ /* tool definitions — see §14 for the current working set */ ],
    "app_type": "os_chat"
  }'
```
Returns an `agent_id`. **Do not add a custom `llm.parameters.prompt`** — it overrides the built-in ReAct scaffold the agent needs to decide when to call tools (§8). Agents cannot be edited in place; any change means registering a new version and repeating §16.7.

### 16.7 Point the dashboard chat panel at the new agent

This requires the **admin mTLS cert**, not basic auth (§7):
```bash
curl -k --cert /etc/wazuh-indexer/certs/admin.pem --key /etc/wazuh-indexer/certs/admin-key.pem \
  -X PUT "https://localhost:9200/.plugins-ml-config/_doc/os_chat" \
  -H "Content-Type: application/json" \
  -d '{"type":"os_chat_root_agent","configuration":{"agent_id":"<agent_id from 16.6>"}}'
```

### 16.8 Test the full agent before touching the dashboard UI

```bash
curl -k -u admin:<password> -X POST "https://localhost:9200/_plugins/_ml/agents/<agent_id>/_execute" \
  -H "Content-Type: application/json" \
  -d '{"parameters": {"question": "hello, are you working?", "verbose": true}}'
```
`verbose:true` shows the `Thought:`/`Action:` trace — use it to confirm tool selection is actually happening before assuming a fix worked. Only after this succeeds, hard-refresh the dashboard (`Ctrl+Shift+R`) and start a **new** conversation (old threads keep a `memory_id` tied to the previous agent version).

---
