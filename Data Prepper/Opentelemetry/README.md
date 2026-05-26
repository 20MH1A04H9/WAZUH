# OpenTelemetry + Wazuh APM Stack Installation Guide

Complete guide for installing and configuring a security observability stack integrating Wazuh SIEM with OpenTelemetry, Data Prepper, and Prometheus.

**Stack:** Ubuntu 24.04 LTS • Wazuh 4.14.5 • Data Prepper 2.15.1 • OTel Collector 0.152.0 • Prometheus 3.4.0

---

## Architecture

```
Application (OTel SDK)
        │
        │  Traces / Metrics / Logs
        ▼
OTel Collector Contrib  ←── Port 4317 (gRPC) / 4318 (HTTP)
        │
        │  OTLP
        ▼
Data Prepper  ←── Port 21890 (gRPC)
        │
        │  Processed traces + service maps
        ▼
OpenSearch / Wazuh Indexer  ←── Port 9200
        │
        ▼
Wazuh Dashboard  ──▶  Observability → Traces / Metrics / Logs

Prometheus  ←── Scrapes OTel Collector (8888), Data Prepper (4900), Node Exporters (9100)
```

---

## Component Versions

| Component | Version |
|---|---|
| Ubuntu | 24.04.4 LTS |
| Wazuh (all components) | 4.14.5 |
| OpenSearch (Wazuh Indexer) | 2.19.5 |
| Data Prepper | 2.15.1 |
| OTel Collector Contrib | 0.152.0 |
| Prometheus | 3.4.0 |
| Java (OpenJDK) | 21.0.10 |

---

## Server Requirements

### Hardware

| Resource | Minimum | Recommended |
|---|---|---|
| RAM | 8 GB | 16–32 GB |
| vCPU | 4 | 8 |
| SSD | 100 GB | 200–256 GB |
| Swap | 4 GB | 8 GB |

> ⚠️ An 8 GB server is too small for the full stack without swap. This guide was tested on 32 GB RAM / 8 vCPU / 256 GB SSD.

### Port Requirements

| Port | Protocol | Service |
|---|---|---|
| 443 | HTTPS | Wazuh Dashboard |
| 9200 | HTTPS | OpenSearch / Wazuh Indexer |
| 4317 | gRPC | OTel Collector (OTLP) |
| 4318 | HTTP | OTel Collector (OTLP) |
| 21890 | gRPC | Data Prepper (OTel Trace) |
| 4900 | HTTP | Data Prepper API |
| 9090 | HTTP | Prometheus |

---

## Step 1 — Pre-Installation

### Configure Swap

```bash
sudo fallocate -l 8G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
free -h  # Verify swap is active
```

### Install Java 21

Data Prepper requires Java 21:

```bash
sudo apt install -y openjdk-21-jre-headless
java -version  # Expected: openjdk version 21.0.10
```

### Configure OpenSearch JVM Heap (Optional)

Check current heap:

```bash
cat /etc/wazuh-indexer/jvm.options | grep -E '^-Xm'
```

For 32 GB RAM, 4–8g is appropriate. Edit if needed:

```bash
sudo nano /etc/wazuh-indexer/jvm.options
```

---

## Step 2 — Install Data Prepper

### Download and Extract

```bash
wget https://artifacts.opensearch.org/data-prepper/2.15.1/opensearch-data-prepper-jdk-2.15.1-linux-x64.tar.gz -P /opt/
sudo tar -xzf /opt/opensearch-data-prepper-jdk-2.15.1-linux-x64.tar.gz -C /opt/
sudo ln -s /opt/opensearch-data-prepper-jdk-2.15.1-linux-x64 /opt/data-prepper
```

### Create User and Directories

```bash
sudo useradd -r -s /bin/false -d /opt/data-prepper data-prepper
sudo mkdir -p /opt/data-prepper/config
sudo mkdir -p /opt/data-prepper/log/data-prepper
```

### Main Configuration

Create `/opt/data-prepper/config/data-prepper-config.yaml`:

```yaml
ssl: false
serverPort: 4900
circuit_breakers:
  heap:
    usage: 6gb
```

### Pipeline Configuration

Create `/opt/data-prepper/config/pipelines.yaml` (replace `YOUR_PASSWORD`):

```yaml
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
  processor:
    - otel_traces:
  sink:
    - opensearch:
        hosts: ["https://localhost:9200"]
        username: "admin"
        password: "YOUR_PASSWORD"
        insecure: true
        index_type: trace-analytics-raw

service-map-pipeline:
  delay: "100"
  source:
    pipeline:
      name: "entry-pipeline"
  processor:
    - otel_apm_service_map:
  sink:
    - opensearch:
        hosts: ["https://localhost:9200"]
        username: "admin"
        password: "YOUR_PASSWORD"
        insecure: true
        index_type: trace-analytics-service-map
```

### Set Ownership

```bash
sudo chown -R data-prepper:data-prepper /opt/opensearch-data-prepper-jdk-2.15.1-linux-x64 /opt/data-prepper
```

### Systemd Service

Create `/etc/systemd/system/data-prepper.service`:

```ini
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
```

### Enable and Start

```bash
sudo systemctl daemon-reload
sudo systemctl enable data-prepper
sudo systemctl start data-prepper
sudo systemctl status data-prepper
```

> ✅ Look for `Initialized OpenSearch sink` and `Started otel_trace_source` in the logs to confirm it's running.

---

## Step 3 — Install OTel Collector

### Install via DEB Package

```bash
wget https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.152.0/otelcol-contrib_0.152.0_linux_amd64.deb -P /tmp/
sudo dpkg -i /tmp/otelcol-contrib_0.152.0_linux_amd64.deb
```

### Configuration

Replace `/etc/otelcol-contrib/config.yaml` with:

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:

exporters:
  otlp/data-prepper:
    endpoint: localhost:21890
    tls:
      insecure: true

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [otlp/data-prepper]
```

### Restart Service

```bash
sudo systemctl restart otelcol-contrib
sudo systemctl status otelcol-contrib
```

---

## Step 4 — Install Prometheus

### Download and Extract

```bash
wget https://github.com/prometheus/prometheus/releases/download/v3.4.0/prometheus-3.4.0.linux-amd64.tar.gz -P /opt/
sudo tar -xzf /opt/prometheus-3.4.0.linux-amd64.tar.gz -C /opt/
sudo ln -s /opt/prometheus-3.4.0.linux-amd64 /opt/prometheus
```

### Create User and Data Directory

```bash
sudo useradd -r -s /bin/false -d /opt/prometheus prometheus
sudo mkdir -p /opt/prometheus/data
sudo chown -R prometheus:prometheus /opt/prometheus-3.4.0.linux-amd64 /opt/prometheus
```

### Configuration

Create `/opt/prometheus/prometheus.yml`:

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'otelcol'
    static_configs:
      - targets: ['localhost:8888']

  - job_name: 'data-prepper'
    static_configs:
      - targets: ['localhost:4900']
```

### Systemd Service

Create `/etc/systemd/system/prometheus.service`:

```ini
[Unit]
Description=Prometheus
After=network.target

[Service]
Type=simple
User=prometheus
Group=prometheus
ExecStart=/opt/prometheus/prometheus \
  --config.file=/opt/prometheus/prometheus.yml \
  --storage.tsdb.path=/opt/prometheus/data \
  --storage.tsdb.retention.time=30d \
  --web.listen-address=0.0.0.0:9090 \
  --web.enable-lifecycle
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

### Enable and Start

```bash
sudo systemctl daemon-reload
sudo systemctl enable prometheus
sudo systemctl start prometheus
sudo systemctl status prometheus
```

---

## Step 5 — Connect Prometheus to OpenSearch

### Add Encryption Key

```bash
echo "plugins.query.datasources.encryption.masterkey: $(openssl rand -hex 12)" | sudo tee -a /etc/wazuh-indexer/opensearch.yml
sudo systemctl restart wazuh-indexer
```

> ⚠️ The key must be 16, 24, or 32 characters. The command above generates a valid 24-character hex key.

### Register Prometheus Data Source

```bash
curl -sk -u admin:'YOUR_PASSWORD' -X POST https://localhost:9200/_plugins/_query/_datasources \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "my_prometheus",
    "connector": "prometheus",
    "properties": {
      "prometheus.uri": "http://localhost:9090"
    }
  }'
```

Expected response: `Created DataSource with name my_prometheus`

### Add Node Exporter Targets (Optional)

Append to `/opt/prometheus/prometheus.yml`:

```yaml
  - job_name: 'linux-node'
    static_configs:
      - targets: ['<NODE_IP>:9100']
        labels:
          instance: 'linux-server'
          os: 'linux'
```

Reload Prometheus:

```bash
curl -X POST http://localhost:9090/-/reload
```

---

## Step 6 — Verification

### Check All Services

```bash
sudo systemctl status wazuh-indexer wazuh-manager wazuh-dashboard data-prepper otelcol-contrib prometheus --no-pager | grep -E '●|Active:'
```

All 6 services should show `active (running)`.

### Send Test Traces

```bash
sudo apt install -y golang-go
go install github.com/open-telemetry/opentelemetry-collector-contrib/cmd/telemetrygen@latest
export PATH=$PATH:$(go env GOPATH)/bin

telemetrygen traces --otlp-insecure --otlp-endpoint localhost:4317 --duration 10s --service demo-service
```

Then check: **Wazuh Dashboard → Observability → Traces**

### Verify Prometheus Targets

```bash
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep -E 'job|lastError|health'
```

All targets should show `health: up`.

### Check APM Indices

```bash
curl -sk -u admin:'YOUR_PASSWORD' https://localhost:9200/_cat/indices/otel* | grep -v '^\.'
```

Expected: `otel-v1-apm-span-000001` and `otel-v1-apm-service-map`

---

## Dashboard Usage

Navigate to **Wazuh Dashboard → Observability** for:

- **Traces** — Trace Analytics with Data Prepper as source
- **Metrics** — Prometheus metrics via `my_prometheus` data source
- **Logs** — PPL queries against Prometheus and OpenSearch indices

### Useful PPL Queries

**CPU Usage by Mode:**
```sql
source = my_prometheus.node_cpu_seconds_total | stats sum(@value) as cpu_seconds by span(@timestamp, 1m), instance, mode
```

**Memory Available:**
```sql
source = my_prometheus.node_memory_MemAvailable_bytes | stats avg(@value) by span(@timestamp, 1m), instance
```

**Disk I/O Reads:**
```sql
source = my_prometheus.node_disk_read_bytes_total | stats sum(@value) by span(@timestamp, 1m), instance
```

**OTel Accepted Spans:**
```sql
source = my_prometheus.otelcol_receiver_accepted_spans | stats sum(@value) by span(@timestamp, 1m)
```

---

## Troubleshooting

### Data Prepper Fails to Start

| Error | Fix |
|---|---|
| `UnrecognizedPropertyException: heapCircuitBreakerUsage` | Use `circuit_breakers.heap.usage: 6gb` |
| `IllegalArgumentException: Byte counts must have unit` | Use `6gb` not `0.85` or `85%` |
| `RollingFile appender not found` | Set `WorkingDirectory=/opt/data-prepper` in systemd service |
| `Connection refused to OpenSearch` | Verify Wazuh Indexer is running and password is correct |

### OTel Collector Issues

```bash
sudo journalctl -u otelcol-contrib -n 50 --no-pager
```

> The `otlp alias is deprecated` warning is harmless.

### No Metrics in Dashboard

- Verify the encryption master key is set in `opensearch.yml`
- Verify `wazuh-indexer` was restarted after adding the key
- Re-register the Prometheus data source via the API
- Check: `curl -s http://localhost:9090/api/v1/targets`

---

## Quick Reference

### Service Management

| Action | Command |
|---|---|
| Restart all services | `sudo systemctl restart wazuh-indexer wazuh-manager wazuh-dashboard data-prepper otelcol-contrib prometheus` |
| View Data Prepper logs | `sudo journalctl -u data-prepper -f` |
| View OTel Collector logs | `sudo journalctl -u otelcol-contrib -f` |
| Reload Prometheus config | `curl -X POST http://localhost:9090/-/reload` |
| Check OpenSearch health | `curl -sk -u admin:'PASSWORD' https://localhost:9200/_cluster/health?pretty` |

### Key File Locations

| Component | Config Path |
|---|---|
| Data Prepper config | `/opt/data-prepper/config/data-prepper-config.yaml` |
| Data Prepper pipelines | `/opt/data-prepper/config/pipelines.yaml` |
| OTel Collector config | `/etc/otelcol-contrib/config.yaml` |
| Prometheus config | `/opt/prometheus/prometheus.yml` |
| Wazuh Indexer config | `/etc/wazuh-indexer/opensearch.yml` |
| Wazuh Dashboard config | `/etc/wazuh-dashboard/opensearch_dashboards.yml` |
| Data Prepper logs | `/opt/data-prepper/log/data-prepper/` |
