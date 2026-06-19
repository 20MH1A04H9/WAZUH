#!/bin/bash
# =============================================================================
# install_otel_stack.sh
# OpenTelemetry + Data Prepper + Prometheus Stack Installer for Wazuh 4.14.5
# Stack: Data Prepper 2.15.1 | OTel Collector Contrib 0.152.0 | Prometheus 3.4.0
# =============================================================================

set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*"; exit 1; }
info() { echo -e "${CYAN}[i]${NC} $*"; }

# ─── Versions ─────────────────────────────────────────────────────────────────
DATA_PREPPER_VERSION="2.15.1"
OTEL_VERSION="0.152.0"
PROMETHEUS_VERSION="3.4.0"

# ─── Require root ─────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && err "Run as root: sudo bash $0"

# ─── Prompt for OpenSearch admin password ─────────────────────────────────────
echo ""
read -rsp "$(echo -e "${CYAN}[?]${NC} Enter Wazuh Indexer admin password: ")" ADMIN_PASS
echo ""
[[ -z "$ADMIN_PASS" ]] && err "Password cannot be empty."

# ─── Pre-flight checks ────────────────────────────────────────────────────────
log "Running pre-flight checks..."

# Check wazuh-indexer is running
systemctl is-active --quiet wazuh-indexer || err "wazuh-indexer is not running. Start it first."

# Test OpenSearch connectivity
HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" -u "admin:${ADMIN_PASS}" https://localhost:9200/)
[[ "$HTTP_CODE" == "200" ]] || err "Cannot connect to OpenSearch (HTTP $HTTP_CODE). Check password."
log "OpenSearch connection OK."

# ─── Step 0: Swap ─────────────────────────────────────────────────────────────
log "Step 0: Checking swap..."
SWAP_TOTAL=$(free -m | awk '/^Swap:/ {print $2}')
if [[ "$SWAP_TOTAL" -lt 4096 ]]; then
    warn "Swap is ${SWAP_TOTAL}MB (< 4GB). Configuring 8G swapfile..."
    if [[ ! -f /swapfile ]]; then
        fallocate -l 8G /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
        log "Swapfile created and enabled."
    else
        warn "/swapfile already exists, skipping creation."
    fi
else
    info "Swap OK: ${SWAP_TOTAL}MB"
fi

# ─── Step 1: Java 21 ──────────────────────────────────────────────────────────
log "Step 1: Checking Java 21..."
if java -version 2>&1 | grep -q 'version "21'; then
    info "Java 21 already installed."
else
    log "Installing OpenJDK 21..."
    apt-get update -qq
    apt-get install -y openjdk-21-jre-headless
    java -version 2>&1 | grep -q 'version "21' || err "Java 21 installation failed."
    log "Java 21 installed."
fi

# ─── Step 2: Data Prepper ─────────────────────────────────────────────────────
log "Step 2: Installing Data Prepper ${DATA_PREPPER_VERSION}..."

DP_TARBALL="opensearch-data-prepper-jdk-${DATA_PREPPER_VERSION}-linux-x64.tar.gz"
DP_URL="https://artifacts.opensearch.org/data-prepper/${DATA_PREPPER_VERSION}/${DP_TARBALL}"
DP_DIR="/opt/opensearch-data-prepper-jdk-${DATA_PREPPER_VERSION}-linux-x64"

if [[ -d "$DP_DIR" ]]; then
    warn "Data Prepper directory already exists at $DP_DIR, skipping download."
else
    log "Downloading Data Prepper..."
    wget -q --show-progress "$DP_URL" -O "/opt/${DP_TARBALL}"
    tar -xzf "/opt/${DP_TARBALL}" -C /opt/
    rm -f "/opt/${DP_TARBALL}"
fi

[[ -L /opt/data-prepper ]] && rm /opt/data-prepper
ln -s "$DP_DIR" /opt/data-prepper

# Create user
id data-prepper &>/dev/null || useradd -r -s /bin/false -d /opt/data-prepper data-prepper

# Directories
mkdir -p /opt/data-prepper/config
mkdir -p /opt/data-prepper/log/data-prepper

# Main config
cat > /opt/data-prepper/config/data-prepper-config.yaml <<'EOF'
ssl: false
serverPort: 4900
circuit_breakers:
  heap:
    usage: 6gb
EOF

# Pipeline config
cat > /opt/data-prepper/config/pipelines.yaml <<EOF
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
        password: "${ADMIN_PASS}"
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
        password: "${ADMIN_PASS}"
        insecure: true
        index_type: trace-analytics-service-map
EOF

# Ownership
chown -R data-prepper:data-prepper "$DP_DIR" /opt/data-prepper

# Systemd service
cat > /etc/systemd/system/data-prepper.service <<EOF
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

systemctl daemon-reload
systemctl enable data-prepper
systemctl restart data-prepper
sleep 5

systemctl is-active --quiet data-prepper && log "Data Prepper running." || warn "Data Prepper may still be starting — check: journalctl -u data-prepper -n 30"

# ─── Step 3: OTel Collector ───────────────────────────────────────────────────
log "Step 3: Installing OTel Collector Contrib ${OTEL_VERSION}..."

OTEL_DEB="otelcol-contrib_${OTEL_VERSION}_linux_amd64.deb"
OTEL_URL="https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${OTEL_VERSION}/${OTEL_DEB}"

if dpkg -l otelcol-contrib &>/dev/null; then
    warn "otelcol-contrib already installed, skipping download."
else
    wget -q --show-progress "$OTEL_URL" -O "/tmp/${OTEL_DEB}"
    dpkg -i "/tmp/${OTEL_DEB}"
    rm -f "/tmp/${OTEL_DEB}"
fi

# Config
cat > /etc/otelcol-contrib/config.yaml <<'EOF'
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
EOF

systemctl enable otelcol-contrib
systemctl restart otelcol-contrib
sleep 3

systemctl is-active --quiet otelcol-contrib && log "OTel Collector running." || warn "OTel Collector may still be starting — check: journalctl -u otelcol-contrib -n 30"

# ─── Step 4: Prometheus ───────────────────────────────────────────────────────
log "Step 4: Installing Prometheus ${PROMETHEUS_VERSION}..."

PROM_TARBALL="prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
PROM_URL="https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/${PROM_TARBALL}"
PROM_DIR="/opt/prometheus-${PROMETHEUS_VERSION}.linux-amd64"

if [[ -d "$PROM_DIR" ]]; then
    warn "Prometheus directory already exists, skipping download."
else
    wget -q --show-progress "$PROM_URL" -O "/opt/${PROM_TARBALL}"
    tar -xzf "/opt/${PROM_TARBALL}" -C /opt/
    rm -f "/opt/${PROM_TARBALL}"
fi

[[ -L /opt/prometheus ]] && rm /opt/prometheus
ln -s "$PROM_DIR" /opt/prometheus

id prometheus &>/dev/null || useradd -r -s /bin/false -d /opt/prometheus prometheus
mkdir -p /opt/prometheus/data
chown -R prometheus:prometheus "$PROM_DIR" /opt/prometheus

# Prometheus config
cat > /opt/prometheus/prometheus.yml <<'EOF'
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
EOF

# Systemd service
cat > /etc/systemd/system/prometheus.service <<'EOF'
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
EOF

systemctl daemon-reload
systemctl enable prometheus
systemctl restart prometheus
sleep 3

systemctl is-active --quiet prometheus && log "Prometheus running." || warn "Prometheus may still be starting — check: journalctl -u prometheus -n 30"

# ─── Step 5: Connect Prometheus to OpenSearch ─────────────────────────────────
log "Step 5: Connecting Prometheus data source to OpenSearch..."

# Check if encryption key already exists
if grep -q 'plugins.query.datasources.encryption.masterkey' /etc/wazuh-indexer/opensearch.yml; then
    warn "Encryption master key already present in opensearch.yml, skipping."
else
    MASTER_KEY=$(openssl rand -hex 12)
    echo "plugins.query.datasources.encryption.masterkey: ${MASTER_KEY}" >> /etc/wazuh-indexer/opensearch.yml
    log "Encryption key added: ${MASTER_KEY}"
    log "Restarting wazuh-indexer..."
    systemctl restart wazuh-indexer
    log "Waiting 30s for indexer to come back up..."
    sleep 30
    # Recheck connectivity
    HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" -u "admin:${ADMIN_PASS}" https://localhost:9200/)
    [[ "$HTTP_CODE" == "200" ]] || err "OpenSearch did not come back up (HTTP $HTTP_CODE). Check: journalctl -u wazuh-indexer -n 50"
fi

# Register Prometheus datasource
DATASOURCE_RESPONSE=$(curl -sk -u "admin:${ADMIN_PASS}" -X POST https://localhost:9200/_plugins/_query/_datasources \
    -H 'Content-Type: application/json' \
    -d '{
        "name": "my_prometheus",
        "connector": "prometheus",
        "properties": {
            "prometheus.uri": "http://localhost:9090"
        }
    }' 2>&1)

if echo "$DATASOURCE_RESPONSE" | grep -qi "created\|already exists\|200"; then
    log "Prometheus data source registered."
else
    warn "Data source registration response: $DATASOURCE_RESPONSE"
    warn "You may need to register it manually — see README Step 5."
fi

# ─── Step 6: Fix APM Index Replicas ──────────────────────────────────────────
log "Step 6: Applying 0-replica template for otel-v1-apm-* indices..."

# Index template — ensures all future otel APM indices are green on single-node
TMPL_RESPONSE=$(curl -sk -u "admin:${ADMIN_PASS}" -X PUT https://localhost:9200/_index_template/otel-replicas \
    -H 'Content-Type: application/json' \
    -d '{
        "index_patterns": ["otel-v1-apm-*"],
        "template": {
            "settings": {
                "number_of_replicas": 0
            }
        },
        "priority": 100
    }' 2>&1)

if echo "$TMPL_RESPONSE" | grep -qi '"acknowledged":true'; then
    log "otel-replicas index template applied."
else
    warn "Template response: $TMPL_RESPONSE"
fi

# Fix any already-existing otel APM indices
for INDEX in otel-v1-apm-span-000001 otel-v1-apm-service-map; do
    EXISTS=$(curl -sk -o /dev/null -w "%{http_code}" -u "admin:${ADMIN_PASS}" "https://localhost:9200/${INDEX}")
    if [[ "$EXISTS" == "200" ]]; then
        FIX_RESP=$(curl -sk -u "admin:${ADMIN_PASS}" -X PUT "https://localhost:9200/${INDEX}/_settings" \
            -H 'Content-Type: application/json' \
            -d '{"index": {"number_of_replicas": 0}}' 2>&1)
        if echo "$FIX_RESP" | grep -qi '"acknowledged":true'; then
            log "${INDEX} → replicas set to 0."
        else
            warn "${INDEX} settings response: $FIX_RESP"
        fi
    else
        info "${INDEX} does not exist yet — template will handle it on creation."
    fi
done

# ─── Step 7: Verification ─────────────────────────────────────────────────────
echo ""
log "Step 7: Final verification..."
echo ""

echo -e "${CYAN}─── Service Status ──────────────────────────────────────────${NC}"
for svc in wazuh-indexer wazuh-manager wazuh-dashboard data-prepper otelcol-contrib prometheus; do
    if systemctl is-active --quiet "$svc"; then
        echo -e "  ${GREEN}✔${NC} $svc"
    else
        echo -e "  ${RED}✗${NC} $svc  ← NOT running"
    fi
done

echo ""
echo -e "${CYAN}─── Prometheus Targets ──────────────────────────────────────${NC}"
sleep 5
curl -s http://localhost:9090/api/v1/targets 2>/dev/null | python3 -m json.tool 2>/dev/null | grep -E '"job"|"health"' || warn "Could not reach Prometheus targets API."

echo ""
echo -e "${CYAN}─── APM Indices ─────────────────────────────────────────────${NC}"
curl -sk -u "admin:${ADMIN_PASS}" "https://localhost:9200/_cat/indices/otel*?v" 2>/dev/null || warn "No otel-* indices yet (expected until first traces are sent)."

echo ""
log "Installation complete."
echo ""
info "Next steps:"
info "  1. Send test traces:  telemetrygen traces --otlp-insecure --otlp-endpoint localhost:4317 --duration 10s --service demo-service"
info "  2. View traces:       Wazuh Dashboard → Observability → Traces"
info "  3. View metrics:      Wazuh Dashboard → Observability → Metrics (source: my_prometheus)"
info ""
info "Logs:"
info "  Data Prepper:   journalctl -u data-prepper -f"
info "  OTel Collector: journalctl -u otelcol-contrib -f"
info "  Prometheus:     journalctl -u prometheus -f"
