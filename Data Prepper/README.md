# Wazuh + Data Prepper Integration

This project integrates **Wazuh**, **OpenSearch**, and **Data Prepper** for log processing, enrichment, routing, and observability pipelines.

---

# Architecture

```text
Wazuh Agents
      ↓
Wazuh Manager
      ↓
Wazuh Indexer (OpenSearch)
      ↓
Data Prepper
      ↓
OpenSearch / External Destinations
```

---

# Requirements

| Component | Version |
|---|---|
| Wazuh | 4.x |
| OpenSearch | 2.x |
| Data Prepper | 2.x |
| Ubuntu | 22.04 / 24.04 |

---

# Install Java

```bash
sudo apt update
sudo apt install openjdk-17-jdk -y
```

Verify Java:

```bash
java -version
```

---

# Download Data Prepper

```bash
wget https://github.com/opensearch-project/data-prepper/releases/latest/download/data-prepper.tar.gz
```

Extract:

```bash
tar -xzf data-prepper.tar.gz
cd data-prepper-*
```

---

# Create Pipeline Configuration

Create the pipeline file:

```bash
nano pipelines.yaml
```

Add the following configuration:

```yaml
wazuh-pipeline:
  source:
    opensearch:
      hosts:
        - https://YOUR-WAZUH-INDEXER:9200
      username: admin
      password: admin
      index: wazuh-alerts-*
      insecure: true

  processor:
    - grok:
        match:
          log: [ "%{GREEDYDATA:message}" ]

    - date:
        from_time_received: true
        destination: "@timestamp"

  sink:
    - opensearch:
        hosts:
          - https://YOUR-OPENSEARCH:9200
        username: admin
        password: admin
        index: wazuh-processed-alerts
        insecure: true
```

---

# Configure Data Prepper

Edit:

```bash
nano config/data-prepper-config.yaml
```

Add:

```yaml
ssl: false

serverPort: 4900
```

---

# Run Data Prepper

```bash
./bin/data-prepper pipelines.yaml
```

---

# Configure Systemd Service

Create service file:

```bash
sudo nano /etc/systemd/system/data-prepper.service
```

Add:

```ini
[Unit]
Description=Data Prepper
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/data-prepper

ExecStart=/opt/data-prepper/bin/data-prepper pipelines.yaml

Restart=always

[Install]
WantedBy=multi-user.target
```

---

# Enable and Start Service

```bash
sudo systemctl daemon-reload
sudo systemctl enable data-prepper
sudo systemctl start data-prepper
```

Check status:

```bash
sudo systemctl status data-prepper
```

---

# Open Firewall Ports

```bash
sudo ufw allow 4900/tcp
sudo ufw allow 9200/tcp
```

---

# View Logs

```bash
journalctl -u data-prepper -f
```

---

# Advanced Enrichment Pipeline

```yaml
wazuh-enrichment:
  source:
    opensearch:
      hosts:
        - https://localhost:9200
      username: admin
      password: admin
      index: wazuh-alerts-*

  processor:
    - add_entries:
        entries:
          environment: production
          soc: ISS-SOC

    - delete_entries:
        with_keys:
          - agent.ip

  sink:
    - stdout:

    - opensearch:
        hosts:
          - https://localhost:9200
        username: admin
        password: admin
        index: wazuh-enriched
```

---

# Troubleshooting

## Validate Pipelines

```bash
./bin/data-prepper validate-pipelines pipelines.yaml
```

## Check Running Ports

```bash
ss -tulnp | grep 4900
```

## Restart Service

```bash
sudo systemctl restart data-prepper
```

## Stop Service

```bash
sudo systemctl stop data-prepper
```

---

# Security Recommendations

- Change default admin credentials
- Enable SSL/TLS
- Restrict firewall access
- Use dedicated OpenSearch users
- Enable authentication and authorization

---

# References

- https://opensearch.org/docs/latest/data-prepper/
- https://documentation.wazuh.com/
- https://opensearch.org/docs/latest/

---
