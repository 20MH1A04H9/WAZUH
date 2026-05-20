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

# Install Java

```bash
sudo apt update
sudo apt install -y openjdk-21-jre-headless
```

Verify Java:

```bash
java -version 2>&1
```

---

# Download Data Prepper

```bash
wget https://artifacts.opensearch.org/data-prepper/2.15.1/opensearch-data-prepper-jdk-2.15.1-linux-x64.tar.gz -P /opt/
ls -lh /opt/opensearch-data-prepper*.tar.gz
sudo tar -xzf /opt/opensearch-data-prepper-jdk-2.15.1-linux-x64.tar.gz -C /opt/ && sudo ln -s /opt/opensearch-data-prepper-jdk-2.15.1-linux-x64 /opt/data-prepper
```

Create the config directory and system user::

```bash
sudo mkdir -p /opt/data-prepper/config && sudo useradd -r -s /bin/false -d /opt/data-prepper data-prepper

sudo tee /opt/data-prepper/config/data-prepper-config.yaml << 'EOF'
ssl: false
serverPort: 4900
circuit_breakers:
  heap:
    usage: 6gb
EOF

```

---

# Create Pipeline Configuration

Create the pipelines config:

```bash
sudo tee /opt/data-prepper/config/pipelines.yaml << 'EOF'
entry-pipeline:
  delay: "100"
  source:
    otel_trace_source:
      ssl: false
      port: 21890
  buffer:
    bounded_blocking:
      buffer_size: 1024
      batch_size: 256
  sink:
    - pipeline:
        name: "raw-pipeline"
    - pipeline:
        name: "service-map-pipeline"

raw-pipeline:
  source:
    pipeline:
      name: "entry-pipeline"
  buffer:
    bounded_blocking:
      buffer_size: 1024
      batch_size: 256
  processor:
    - otel_traces:
  sink:
    - opensearch:
        hosts: ["https://localhost:9200"]
        username: "admin"
        password: "Viswa@123."
        insecure: true
        index_type: trace-analytics-raw

service-map-pipeline:
  delay: "100"
  source:
    pipeline:
      name: "entry-pipeline"
  buffer:
    bounded_blocking:
      buffer_size: 1024
      batch_size: 256
  processor:
    - otel_apm_service_map:
  sink:
    - opensearch:
        hosts: ["https://localhost:9200"]
        username: "admin"
        password: "Viswa@123."
        insecure: true
        index_type: trace-analytics-service-map
EOF
```

Set ownership and create the log directory:

```bash
sudo chown -R data-prepper:data-prepper /opt/opensearch-data-prepper-jdk-2.15.1-linux-x64 /opt/data-prepper && sudo mkdir -p /opt/data-prepper/log/data-prepper && sudo chown -R data-prepper:data-prepper /opt/data-prepper/log
```

---

# Configure Systemd Service

Create the systemd service file:

```bash
sudo tee /etc/systemd/system/data-prepper.service << 'EOF'
[Unit]
Description=OpenSearch Data Prepper
After=network.target wazuh-indexer.service

[Service]
Type=simple
User=data-prepper
Group=data-prepper
WorkingDirectory=/opt/data-prepper
ExecStart=/opt/data-prepper/bin/data-prepper /opt/data-prepper/config/pipelines.yaml /opt/data-prepper/config/data-prepper-config.yaml
Restart=on-failure
RestartSec=10
LimitNOFILE=65536
Environment="JAVA_OPTS=-Xms512m -Xmx1g"

[Install]
WantedBy=multi-user.target
EOF
```

---

# Enable and Start Service and  Check status

```bash
sudo systemctl daemon-reload && sudo systemctl enable data-prepper && sudo systemctl start data-prepper && sleep 8 && sudo systemctl status data-prepper
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

Data Prepper is running. The WARNs about TLS are expected — we intentionally set ssl: false for the lab. The key lines confirm it's working:
Initialized OpenSearch sink ✅
Started otel_trace_source ✅

---


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
