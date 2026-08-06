# Groq LLaMA AI Integration with Wazuh (OpenSearch ML Commons)

Connect Groq's LLaMA models to Wazuh via OpenSearch ML Commons. Run all commands in **Wazuh Dashboard → Dev Tools**.

---

## Overview

This integration allows Wazuh to use Groq-hosted LLaMA models for AI-powered SOC analysis — directly inside OpenSearch via the ML Commons plugin.

```
Wazuh Dashboard (Dev Tools)
        │
        │  REST API
        ▼
OpenSearch ML Commons
        │
        │  HTTP Connector
        ▼
Groq API  →  LLaMA 3.3 70B
```

---

## Prerequisites

- Wazuh 4.x with OpenSearch (Wazuh Indexer) running
- Groq API key — get one free at [console.groq.com](https://console.groq.com)
- Access to **Wazuh Dashboard → Dev Tools**

---

## Recommended Models

| Model | Best For |
|---|---|
| `llama-3.3-70b-versatile` | Best balance — recommended |
| `meta-llama/llama-4-scout-17b-16e-instruct` | Highest token limit |
| `llama3-8b-8192` | Fastest / lightweight |

---

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

## Cleanup — Delete Connector and Model

If you need to recreate the connector (e.g. to fix config or rotate API key), run these in order:

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

Then repeat Steps 3–6 to recreate.

---

## Troubleshooting

**`trusted_connector_endpoints_regex` error:**
Ensure the regex uses `\\.` (escaped dot) — a plain `.` matches any character and may be rejected.

**Connector creation succeeds but predict fails:**
Check the `request_body` field — the content must be a plain JSON string. Avoid double-escaping. Use the exact format in Step 3.

**Model stuck in DEPLOYING state:**
```json
GET /_plugins/_ml/models/YOUR_MODEL_ID
```
If status is not `DEPLOYED` after 30 seconds, undeploy and redeploy.

**401 Unauthorized from Groq:**
Your API key is invalid or expired. Generate a new one at [console.groq.com](https://console.groq.com) and recreate the connector.

**`only_run_on_ml_node: true` error:**
Run Step 2 first to enable remote inference on all nodes.

---

## Key IDs to Track

Keep a note of these after each deployment:

| Item | Value |
|---|---|
| Connector ID | *(save from Step 3 response)* |
| Model ID | *(save from Step 4 response)* |
| Groq Model Name | `llama-3.3-70b-versatile` |
| API Endpoint | `https://api.groq.com/openai/v1/chat/completions` |
