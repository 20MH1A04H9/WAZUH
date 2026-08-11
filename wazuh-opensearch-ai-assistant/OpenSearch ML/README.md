<h1 align="center">Groq LLaMA & Ollama AI Integration with Wazuh (OpenSearch ML)</h1>

<p align="center"> Connect <strong>Groq's LLaMA models</strong> or a <strong>local Ollama model</strong> to <strong>Wazuh</strong> through <strong>OpenSearch ML Commons</strong> and perform AI-powered security analysis directly from <strong>Wazuh Dashboard → Dev Tools</strong>. </p>

<p align="center"> <img src="https://img.shields.io/badge/Wazuh-4.14.x-blue"/> <img src="https://img.shields.io/badge/OpenSearch-2.19.x-green"/> <img src="https://img.shields.io/badge/Groq-LLaMA%203.3%2070B-orange"/> <img src="https://img.shields.io/badge/Ollama-Local-purple"/> <img src="https://img.shields.io/badge/ML%20Commons-Enabled-success"/> <img src="https://img.shields.io/badge/License-MIT-lightgrey"/> </p>


---

## Overview

This integration allows Wazuh to use either a Groq-hosted LLaMA model (cloud) or a locally-running Ollama model for AI-powered SOC analysis — directly inside OpenSearch via the ML Commons plugin.

```
Wazuh Dashboard (Dev Tools)
        │
        │  REST API
        ▼
OpenSearch ML Commons
        │
        ├── HTTP Connector ──► Groq API  →  LLaMA 3.3 70B (cloud)
        │
        └── HTTP Connector ──► Ollama  →  http://localhost:11434 (local)
```

---

## Prerequisites

- Wazuh 4.x with OpenSearch (Wazuh Indexer) running
- **For Groq:** an API key — get one free at [console.groq.com](https://console.groq.com)
- **For Ollama:** Ollama installed on the same host as the Wazuh Indexer (or a host reachable from it), with a model pulled
- Access to **Wazuh Dashboard → Dev Tools**

---

## Recommended Models

| Model | Backend | Best For |
|---|---|---|
| `llama-3.3-70b-versatile` | Groq (cloud) | Best balance — recommended |
| `meta-llama/llama-4-scout-17b-16e-instruct` | Groq (cloud) | Highest token limit |
| `llama3-8b-8192` | Groq (cloud) | Fastest / lightweight |
| `llama3.1:8b` | Ollama (local) | No API key, no rate limits, runs offline |

> ⚠️ Local models are meaningfully weaker than Groq's hosted 70B model on structured tasks (e.g. generating query DSL/PPL syntax). Good for general chat, keep expectations modest for anything requiring precise syntax generation.

---

# Part A — Groq (Cloud)

## Step 1 — Add Groq to Trusted Endpoints

```json
PUT /_cluster/settings
{
  "persistent": {
    "plugins.ml_commons.trusted_connector_endpoints_regex": [
      "^https://api\\.groq\\.com/.*$",
      "^https://api\\.openai\\.com/.*$",
      "^https://api\\.anthropic\\.com/.*$",
      "^https://api\\.deepseek\\.com/.*$"
    ]
  }
}
```

---

## Step 2 — Enable Remote Inference

```json
PUT /_cluster/settings
{
  "persistent": {
    "plugins.ml_commons.only_run_on_ml_node": false,
    "plugins.ml_commons.allow_registering_model_via_url": true,
    "plugins.ml_commons.native_memory_threshold": 99
  }
}
```

---

## Step 3 — Create the Connector

Replace `YOUR_GROQ_API_KEY` with your actual key:

```json
POST /_plugins/_ml/connectors/_create
{
  "name": "Groq LLaMA",
  "description": "Groq API - LLaMA 3 70B",
  "version": 1,
  "protocol": "http",
  "parameters": {
    "model": "llama-3.3-70b-versatile",
    "max_tokens": 4096
  },
  "credential": {
    "groq_key": "YOUR_GROQ_API_KEY"
  },
  "actions": [
    {
      "action_type": "predict",
      "method": "POST",
      "url": "https://api.groq.com/openai/v1/chat/completions",
      "headers": {
        "Authorization": "Bearer ${credential.groq_key}",
        "content-type": "application/json"
      },
      "request_body": "{\"model\":\"${parameters.model}\",\"max_tokens\":${parameters.max_tokens},\"messages\":[{\"role\":\"user\",\"content\":\"${parameters.prompt}\"}]}"
    }
  ]
}
```

> 📋 **Save the `connector_id`** from the response — you need it in the next step.

---

## Step 4 — Register the Model

Replace `YOUR_CONNECTOR_ID` with the value from Step 3:

```json
POST /_plugins/_ml/models/_register
{
  "name": "Groq LLaMA 3.3 70B",
  "function_name": "remote",
  "description": "LLaMA via Groq API",
  "connector_id": "YOUR_CONNECTOR_ID"
}
```

> 📋 **Save the `model_id`** from the response — you need it in the next steps.

---

## Step 5 — Deploy the Model

Replace `YOUR_MODEL_ID` with the value from Step 4:

```json
POST /_plugins/_ml/models/YOUR_MODEL_ID/_deploy
```

Expected response:
```json
{
  "status": "DEPLOYED"
}
```

---

## Step 6 — Test the Integration

```json
POST /_plugins/_ml/models/YOUR_MODEL_ID/_predict
{
  "parameters": {
    "prompt": "You are a SOC analyst. A Wazuh level 10 alert fired for SSH brute force from IP 92.118.39.23. What actions should be taken?"
  }
}
```

✅ If you receive AI-generated text in the response, the Groq LLaMA integration is working inside Wazuh.

---

# Part B — Ollama (Local)

Running a model locally via Ollama avoids API keys and cloud rate limits, at the cost of model quality. Good for general Q&A; not recommended for anything requiring precise query-syntax generation (see note above).

## Step 1 — Install Ollama and Pull a Model

On the OpenSearch Indexer host (or a host reachable from it):

```bash
curl -fsSL https://ollama.com/install.sh | sh
ollama pull llama3.1:8b
```

Confirm it's serving on `localhost:11434`:

```bash
curl http://localhost:11434/api/tags
```

---

## Step 2 — Trust the Local Endpoint

`localhost` is not trusted by default — you must explicitly allow it. **Always paste back the full existing list, plus the new entry — a PUT with only the new entry silently wipes every other provider's trust config.**

```json
PUT /_cluster/settings
{
  "persistent": {
    "plugins.ml_commons.trusted_connector_endpoints_regex": [
      "^https://api\\.groq\\.com/.*$",
      "^https://api\\.openai\\.com/.*$",
      "^https://api\\.anthropic\\.com/.*$",
      "^https://api\\.deepseek\\.com/.*$",
      "^http://localhost:11434/.*$"
    ]
  }
}
```

> Verify what's currently trusted before overwriting, so you don't drop existing entries:
> ```json
> GET /_cluster/settings?include_defaults=true&filter_path=**.trusted_connector_endpoints_regex
> ```

---

## Step 3 — Allow Private/Loopback IPs

ML Commons blocks connections to private IPs (SSRF protection) by default. `localhost` is a private address, so this must be relaxed:

```json
PUT /_cluster/settings
{
  "persistent": {
    "plugins.ml_commons.connector.private_ip_enabled": true
  }
}
```

> ⚠️ This is a **cluster-wide** relaxation of SSRF protection for all ML connectors, not just Ollama. Fine on a single-node box you control; reconsider before doing this on a multi-tenant or externally-exposed cluster.

---

## Step 4 — Create the Ollama Connector

Ollama needs no real authentication, but ML Commons requires a non-empty `credential` block regardless — a dummy value is fine:

```json
POST /_plugins/_ml/connectors/_create
{
  "name": "Ollama Local",
  "description": "Local Ollama - llama3.1:8b",
  "version": 1,
  "protocol": "http",
  "parameters": {
    "model": "llama3.1:8b"
  },
  "credential": {
    "dummy_key": "not_required_for_local_ollama"
  },
  "actions": [
    {
      "action_type": "predict",
      "method": "POST",
      "url": "http://localhost:11434/api/generate",
      "headers": {
        "content-type": "application/json"
      },
      "request_body": "{\"model\":\"${parameters.model}\",\"prompt\":\"${parameters.prompt}\",\"stream\":false}"
    }
  ]
}
```

> 📋 **Save the `connector_id`** from the response.

---

## Step 5 — Register the Model

Replace `YOUR_OLLAMA_CONNECTOR_ID` with the value from Step 4:

```json
POST /_plugins/_ml/models/_register
{
  "name": "Ollama LLaMA 3.1 8B",
  "function_name": "remote",
  "description": "LLaMA 3.1 8B via local Ollama",
  "connector_id": "YOUR_OLLAMA_CONNECTOR_ID"
}
```

> 📋 **Save the `model_id`** from the response.

---

## Step 6 — Deploy the Model

```json
POST /_plugins/_ml/models/YOUR_OLLAMA_MODEL_ID/_deploy
```

---

## Step 7 — Test the Integration

```json
POST /_plugins/_ml/models/YOUR_OLLAMA_MODEL_ID/_predict
{
  "parameters": {
    "prompt": "hello, are you working?"
  }
}
```

✅ A 200 response with generated text confirms the connector and model are wired correctly.

> **Note:** a 200 OK confirms the plumbing works — it is not proof the answer is *correct*. Smaller local models can return confident, plausible-looking, factually wrong output. Spot-check responses on a couple of known-answer prompts before trusting the model for anything SOC-facing.

---

## Cleanup — Delete Connector and Model

If you need to recreate a connector (e.g. to fix config, rotate an API key, or switch the Ollama model), run these in order:

**1 — Undeploy the model first:**
```json
POST /_plugins/_ml/models/YOUR_MODEL_ID/_undeploy
```

**2 — Delete the model:**
```json
DELETE /_plugins/_ml/models/YOUR_MODEL_ID
```

**3 — Delete the connector:**
```json
DELETE /_plugins/_ml/connectors/YOUR_CONNECTOR_ID
```

Then repeat the Create Connector → Register → Deploy steps to recreate (Groq: Steps 3–6, Ollama: Steps 4–7).

---

## Troubleshooting

**`trusted_connector_endpoints_regex` error:**
Ensure the regex uses `\\.` (escaped dot) — a plain `.` matches any character and may be rejected.

**Connector creation succeeds but predict fails:**
Check the `request_body` field — the content must be a plain JSON string. Avoid double-escaping. Use the exact format shown above.

**Model stuck in DEPLOYING state:**
```json
GET /_plugins/_ml/models/YOUR_MODEL_ID
```
If status is not `DEPLOYED` after 30 seconds, undeploy and redeploy.

**401 Unauthorized from Groq:**
Your API key is invalid or expired. Generate a new one at [console.groq.com](https://console.groq.com) and recreate the connector.

**`only_run_on_ml_node: true` error:**
Run Part A, Step 2 first to enable remote inference on all nodes.

**Ollama: `Connector credential is null or empty list`:**
Add a non-empty (even dummy) `credential` block — see Part B, Step 4.

**Ollama: `Connector URL is not matching the trusted connector endpoint regex`:**
You skipped Part B, Step 2 — `localhost` isn't trusted by default.

**Ollama: `Remote inference host name has private ip address: localhost`:**
You skipped Part B, Step 3 — private/loopback IPs are blocked by default (SSRF protection).

**Ollama: connection refused:**
Ollama isn't running or isn't listening on `11434`. Check with `curl http://localhost:11434/api/tags` and `systemctl status ollama` (if installed as a service).

---

## Key IDs to Track

Keep a note of these after each deployment:

| Item | Value |
|---|---|
| Groq Connector ID | *(save from Part A, Step 3 response)* |
| Groq Model ID | *(save from Part A, Step 4 response)* |
| Groq Model Name | `llama-3.3-70b-versatile` |
| Groq API Endpoint | `https://api.groq.com/openai/v1/chat/completions` |
| Ollama Connector ID | *(save from Part B, Step 4 response)* |
| Ollama Model ID | *(save from Part B, Step 5 response)* |
| Ollama Model Name | `llama3.1:8b` |
| Ollama API Endpoint | `http://localhost:11434/api/generate` |
