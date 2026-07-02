#!/usr/bin/env bash
# =============================================================================
# OpenTelemetry + Wazuh APM Stack — Automated Install Script
# Stack: Ubuntu 24.04 LTS | Wazuh 4.14.5 | Data Prepper 2.16.0
#        OTel Collector Contrib 0.154.0 | Prometheus 3.12.0
# Updated: 2026-07-02
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION — Edit these before running
# ─────────────────────────────────────────────────────────────────────────────
WAZUH_ADMIN_PASSWORD="${WAZUH_ADMIN_PASSWORD:-}"          # Required — set via env or edit here
NODE_EXPORTER_TARGETS=()                                   # Optional: ("192.168.1.10" "192.168.1.11")

# Component versions
WAZUH_VERSION="4.14.5"
DATA_PREPPER_VERSION="2.16.0"
OTEL_VERSION="0.154.0"
PROMETHEUS_VERSION="3.12.0"

# Install paths
DATA_PREPPER_DIR="/opt/data-prepper"
PROMETHEUS_DIR="/opt/prometheus"
# ─────────────────────────────────────────────────────────────────────────────

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()     { echo -e "${GREEN}[✔]${RESET} $*"; }
info()    { echo -e "${CYAN}[→]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[!]${RESET} $*"; }
error()   { echo -e "${RED}[✘]${RESET} $*" >&2; }
section() { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${RESET}"; \
            echo -e "${BOLD}${CYAN}  $*${RESET}"; \
            echo -e "${BOLD}${CYAN}══════════════════════════════════════════${RESET}\n"; }

# ── Preflight ─────────────────────────────────────────────────────────────────
preflight() {
  section "Preflight Checks"

  if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (sudo $0)"
    exit 1
  fi

  # Require Ubuntu 24.04
  if ! grep -q "24.04" /etc/os-release 2>/dev/null; then
    warn "This script was tested on Ubuntu 24.04. Proceeding anyway…"
  fi

  # Prompt for password if not set
  if [[ -z "${WAZUH_ADMIN_PASSWORD}" ]]; then
    echo -e "${YELLOW}Enter the Wazuh admin password (used for OpenSearch):${RESET}"
    read -rsp "Password: " WAZUH_ADMIN_PASSWORD
    echo
    if [[ -z "${WAZUH_ADMIN_PASSWORD}" ]]; then
      error "Password cannot be empty."
      exit 1
    fi
  fi

  # RAM check
  TOTAL_RAM_GB=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
  if [[ ${TOTAL_RAM_GB} -lt 8 ]]; then
    error "Minimum 8 GB RAM required (detected: ${TOTAL_RAM_GB} GB)."
    exit 1
  fi
  if [[ ${TOTAL_RAM_GB} -lt 16 ]]; then
    warn "Less than 16 GB RAM detected (${TOTAL_RAM_GB} GB). Swap will be configured."
  fi

  log "Preflight checks passed (RAM: ${TOTAL_RAM_GB} GB)"
}

# ── Step 1 — Pre-Installation ─────────────────────────────────────────────────
step1_pre_install() {
  section "Step 1 — Pre-Installation"

  # Swap
  if ! swapon --show | grep -q '/swapfile'; then
    info "Configuring 8 GB swapfile…"
    if [[ ! -f /swapfile ]]; then
      fallocate -l 8G /swapfile
      chmod 600 /swapfile
      mkswap /swapfile
    fi
    swapon /swapfile
    grep -qxF '/swapfile none swap sw 0 0' /etc/fstab || \
      echo '/swapfile none swap sw 0 0' >> /etc/fstab
    log "Swapfile activated"
  else
    log "Swapfile already active — skipping"
  fi

  # Java 21
  info "Installing OpenJDK 21…"
  apt-get update -qq
  apt-get install -y -qq openjdk-21-jre-headless curl wget gnupg2 python3 golang-go
  JAVA_VER=$(java -version 2>&1 | head -1)
  log "Java installed: ${JAVA_VER}"
}

# ── Step 2 — Install Wazuh ────────────────────────────────────────────────────
step2_install_wazuh() {
  section "Step 2 — Install Wazuh ${WAZUH_VERSION}"

  if systemctl is-active --quiet wazuh-indexer 2>/dev/null; then
    log "Wazuh already installed and running — skipping"
    return
  fi

  info "Adding Wazuh repository…"
  curl -fsSL https://packages.wazuh.com/key/GPG-KEY-WazuhSecure | \
    gpg --dearmor -o /usr/share/keyrings/wazuh.gpg
  echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] \
https://packages.wazuh.com/4.x/apt/ stable main" \
    > /etc/apt/sources.list.d/wazuh.list
  apt-get update -qq

  info "Installing Wazuh Indexer…"
  apt-get install -y -qq wazuh-indexer

  info "Installing Wazuh Manager…"
  apt-get install -y -qq wazuh-manager

  info "Installing Wazuh Dashboard…"
  apt-get install -y -qq wazuh-dashboard

  info "Initialising Wazuh…"
  /usr/share/wazuh-indexer/bin/indexer-security-init.sh 2>/dev/null || true

  systemctl enable --now wazuh-indexer wazuh-manager wazuh-dashboard
  sleep 10

  info "Setting admin password…"
  /usr/share/wazuh-indexer/plugins/opensearch-security/tools/securityadmin.sh \
    -cd /etc/wazuh-indexer/opensearch-security/ \
    -icl -nhnv \
    -cacert /etc/wazuh-indexer/certs/root-ca.pem \
    -cert /etc/wazuh-indexer/certs/admin.pem \
    -key /etc/wazuh-indexer/certs/admin-key.pem 2>/dev/null || true

  info "Waiting for Wazuh Indexer to be ready…"
  for i in $(seq 1 30); do
    if curl -sk -u "admin:${WAZUH_ADMIN_PASSWORD}" \
        https://localhost:9200/_cluster/health \
        --max-time 5 | grep -q '"status"'; then
      log "Wazuh Indexer is ready"
      break
    fi
    sleep 5
    [[ $i -eq 30 ]] && { warn "Wazuh Indexer health check timed out — continuing"; }
  done
  log "Wazuh services started"
}

# ── Step 3 — Install Data Prepper ─────────────────────────────────────────────
step3_install_data_prepper() {
  section "Step 3 — Install Data Prepper ${DATA_PREPPER_VERSION}"

  local TARBALL="opensearch-data-prepper-jdk-${DATA_PREPPER_VERSION}-linux-x64.tar.gz"
  local EXTRACT_DIR="/opt/opensearch-data-prepper-jdk-${DATA_PREPPER_VERSION}-linux-x64"

  if systemctl is-active --quiet data-prepper 2>/dev/null; then
    log "Data Prepper already running — skipping install"
    return
  fi

  if [[ ! -d "${EXTRACT_DIR}" ]]; then
    info "Downloading Data Prepper ${DATA_PREPPER_VERSION}…"
    wget -q "https://artifacts.opensearch.org/data-prepper/${DATA_PREPPER_VERSION}/${TARBALL}" \
      -O "/opt/${TARBALL}"
    info "Extracting…"
    tar -xzf "/opt/${TARBALL}" -C /opt/
  fi

  [[ -L "${DATA_PREPPER_DIR}" ]] || ln -s "${EXTRACT_DIR}" "${DATA_PREPPER_DIR}"

  # Create user and dirs
  id data-prepper &>/dev/null || useradd -r -s /bin/false -d "${DATA_PREPPER_DIR}" data-prepper
  mkdir -p "${DATA_PREPPER_DIR}/config" "${DATA_PREPPER_DIR}/log/data-prepper"

  info "Writing Data Prepper config…"
  cat > "${DATA_PREPPER_DIR}/config/data-prepper-config.yaml" <<'DPCONFIG'
ssl: false
serverPort: 4900
circuit_breakers:
  heap:
    usage: 6gb
DPCONFIG

  info "Writing pipelines config…"
  cat > "${DATA_PREPPER_DIR}/config/pipelines.yaml" <<DPPIPELINES
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
        password: "${WAZUH_ADMIN_PASSWORD}"
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
        password: "${WAZUH_ADMIN_PASSWORD}"
        insecure: true
        index_type: trace-analytics-service-map
DPPIPELINES

  chown -R data-prepper:data-prepper "${EXTRACT_DIR}" "${DATA_PREPPER_DIR}"

  info "Creating systemd service…"
  cat > /etc/systemd/system/data-prepper.service <<DPSVC
[Unit]
Description=OpenSearch Data Prepper
After=network.target wazuh-indexer.service

[Service]
Type=simple
User=data-prepper
Group=data-prepper
WorkingDirectory=${DATA_PREPPER_DIR}
ExecStart=${DATA_PREPPER_DIR}/bin/data-prepper \\
  ${DATA_PREPPER_DIR}/config/pipelines.yaml \\
  ${DATA_PREPPER_DIR}/config/data-prepper-config.yaml
Restart=on-failure
RestartSec=10
LimitNOFILE=65536
Environment="JAVA_OPTS=-Xms512m -Xmx1g"

[Install]
WantedBy=multi-user.target
DPSVC

  systemctl daemon-reload
  systemctl enable data-prepper
  systemctl start data-prepper
  sleep 5

  if systemctl is-active --quiet data-prepper; then
    log "Data Prepper is running"
  else
    warn "Data Prepper may not have started yet — check: journalctl -u data-prepper -n 50"
  fi
}

# ── Step 4 — Install OTel Collector ──────────────────────────────────────────
step4_install_otel() {
  section "Step 4 — Install OTel Collector Contrib ${OTEL_VERSION}"

  if command -v otelcol-contrib &>/dev/null || systemctl is-active --quiet otelcol-contrib 2>/dev/null; then
    log "OTel Collector already installed — skipping"
  else
    local DEB="otelcol-contrib_${OTEL_VERSION}_linux_amd64.deb"
    info "Downloading OTel Collector Contrib ${OTEL_VERSION}…"
    wget -q "https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${OTEL_VERSION}/${DEB}" \
      -O "/tmp/${DEB}"
    dpkg -i "/tmp/${DEB}"
  fi

  info "Writing OTel Collector config…"
  cat > /etc/otelcol-contrib/config.yaml <<'OTELCONFIG'
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
  telemetry:
    metrics:
      address: 0.0.0.0:8888
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [otlp/data-prepper]
OTELCONFIG

  systemctl restart otelcol-contrib
  systemctl enable otelcol-contrib
  sleep 3

  if systemctl is-active --quiet otelcol-contrib; then
    log "OTel Collector is running"
  else
    warn "OTel Collector may not have started — check: journalctl -u otelcol-contrib -n 50"
  fi
}

# ── Step 5 — Install Prometheus ───────────────────────────────────────────────
step5_install_prometheus() {
  section "Step 5 — Install Prometheus ${PROMETHEUS_VERSION}"

  local TARBALL="prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
  local EXTRACT_DIR="/opt/prometheus-${PROMETHEUS_VERSION}.linux-amd64"

  if systemctl is-active --quiet prometheus 2>/dev/null; then
    log "Prometheus already running — skipping install"
    return
  fi

  if [[ ! -d "${EXTRACT_DIR}" ]]; then
    info "Downloading Prometheus ${PROMETHEUS_VERSION}…"
    wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/${TARBALL}" \
      -O "/opt/${TARBALL}"
    tar -xzf "/opt/${TARBALL}" -C /opt/
  fi

  [[ -L "${PROMETHEUS_DIR}" ]] || ln -s "${EXTRACT_DIR}" "${PROMETHEUS_DIR}"

  id prometheus &>/dev/null || useradd -r -s /bin/false -d "${PROMETHEUS_DIR}" prometheus
  mkdir -p "${PROMETHEUS_DIR}/data"

  info "Writing Prometheus config…"
  # Data Prepper exposes metrics at /metrics/sys on port 4900
  cat > "${PROMETHEUS_DIR}/prometheus.yml" <<PROMCFG
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
    metrics_path: '/metrics/sys'
    static_configs:
      - targets: ['localhost:4900']
PROMCFG

  # Append Node Exporter targets if configured
  if [[ ${#NODE_EXPORTER_TARGETS[@]} -gt 0 ]]; then
    info "Adding Node Exporter targets…"
    {
      echo ""
      echo "  - job_name: 'linux-node'"
      echo "    static_configs:"
      echo "      - targets:"
      for TARGET in "${NODE_EXPORTER_TARGETS[@]}"; do
        echo "          - '${TARGET}:9100'"
      done
    } >> "${PROMETHEUS_DIR}/prometheus.yml"
    log "Node Exporter targets added: ${NODE_EXPORTER_TARGETS[*]}"
  fi

  chown -R prometheus:prometheus "${EXTRACT_DIR}" "${PROMETHEUS_DIR}"

  info "Creating systemd service…"
  cat > /etc/systemd/system/prometheus.service <<PROMSVC
[Unit]
Description=Prometheus
After=network.target

[Service]
Type=simple
User=prometheus
Group=prometheus
ExecStart=${PROMETHEUS_DIR}/prometheus \\
  --config.file=${PROMETHEUS_DIR}/prometheus.yml \\
  --storage.tsdb.path=${PROMETHEUS_DIR}/data \\
  --storage.tsdb.retention.time=30d \\
  --web.listen-address=0.0.0.0:9090 \\
  --web.enable-lifecycle
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
PROMSVC

  systemctl daemon-reload
  systemctl enable prometheus
  systemctl start prometheus
  sleep 3

  if systemctl is-active --quiet prometheus; then
    log "Prometheus is running"
  else
    warn "Prometheus may not have started — check: journalctl -u prometheus -n 50"
  fi
}

# ── Step 6 — Connect Prometheus to OpenSearch ─────────────────────────────────
step6_connect_prometheus() {
  section "Step 6 — Connect Prometheus to OpenSearch"

  local OPENSEARCH_YML="/etc/wazuh-indexer/opensearch.yml"

  if grep -q "plugins.query.datasources.encryption.masterkey" "${OPENSEARCH_YML}" 2>/dev/null; then
    log "Encryption key already configured — skipping"
  else
    info "Adding encryption master key to opensearch.yml…"
    local KEY
    KEY=$(openssl rand -hex 12)
    echo "plugins.query.datasources.encryption.masterkey: ${KEY}" >> "${OPENSEARCH_YML}"
    log "Encryption key added"

    info "Restarting Wazuh Indexer…"
    systemctl restart wazuh-indexer
    sleep 15

    info "Waiting for Wazuh Indexer to be ready after restart…"
    for i in $(seq 1 30); do
      if curl -sk -u "admin:${WAZUH_ADMIN_PASSWORD}" \
          https://localhost:9200/_cluster/health --max-time 5 | grep -q '"status"'; then
        log "Wazuh Indexer ready"
        break
      fi
      sleep 5
    done
  fi

  info "Registering Prometheus data source in OpenSearch…"
  RESPONSE=$(curl -sk -u "admin:${WAZUH_ADMIN_PASSWORD}" \
    -X POST https://localhost:9200/_plugins/_query/_datasources \
    -H 'Content-Type: application/json' \
    -d '{
      "name": "my_prometheus",
      "connector": "prometheus",
      "properties": {
        "prometheus.uri": "http://localhost:9090"
      }
    }' 2>&1 || true)

  if echo "${RESPONSE}" | grep -q -i "created\|already exists\|my_prometheus"; then
    log "Prometheus data source registered (or already exists)"
  else
    warn "Unexpected response when registering data source: ${RESPONSE}"
    warn "You may need to register it manually — see the guide."
  fi
}

# ── Step 7 — Verification ─────────────────────────────────────────────────────
step7_verify() {
  section "Step 7 — Verification"

  local PASS=true

  info "Checking service status…"
  for SVC in wazuh-indexer wazuh-manager wazuh-dashboard data-prepper otelcol-contrib prometheus; do
    if systemctl is-active --quiet "${SVC}" 2>/dev/null; then
      log "${SVC} — active"
    else
      error "${SVC} — NOT running"
      PASS=false
    fi
  done

  info "Checking Prometheus targets…"
  sleep 5
  if curl -s http://localhost:9090/api/v1/targets 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
targets = data.get('data', {}).get('activeTargets', [])
for t in targets:
    status = '✔' if t.get('health') == 'up' else '✘'
    print(f'  [{status}] {t[\"labels\"].get(\"job\",\"?\")} — {t.get(\"health\")}')
" 2>/dev/null; then
    log "Prometheus target check complete"
  else
    warn "Could not query Prometheus targets yet (may need more time to start)"
  fi

  info "Checking OpenSearch APM indices…"
  INDICES=$(curl -sk -u "admin:${WAZUH_ADMIN_PASSWORD}" \
    https://localhost:9200/_cat/indices/otel* 2>/dev/null || true)
  if [[ -n "${INDICES}" ]]; then
    log "APM indices found:"
    echo "${INDICES}" | sed 's/^/    /'
  else
    warn "No APM indices yet — send test traces to create them (see below)"
  fi

  echo ""
  if ${PASS}; then
    log "All services are running!"
  else
    warn "Some services are not running. Check logs with: journalctl -u <service> -n 50"
  fi
}

# ── Summary ───────────────────────────────────────────────────────────────────
print_summary() {
  local SERVER_IP
  SERVER_IP=$(hostname -I | awk '{print $1}')

  echo ""
  echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════${RESET}"
  echo -e "${BOLD}${GREEN}  Installation Complete!${RESET}"
  echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════${RESET}"
  echo ""
  echo -e "  ${BOLD}Wazuh Dashboard${RESET}   →  https://${SERVER_IP}:443"
  echo -e "  ${BOLD}Prometheus${RESET}        →  http://${SERVER_IP}:9090"
  echo -e "  ${BOLD}OTel gRPC${RESET}         →  ${SERVER_IP}:4317"
  echo -e "  ${BOLD}OTel HTTP${RESET}         →  http://${SERVER_IP}:4318"
  echo -e "  ${BOLD}Data Prepper API${RESET}  →  http://${SERVER_IP}:4900"
  echo -e "  ${BOLD}Data Prepper Metrics${RESET} → http://${SERVER_IP}:4900/metrics/sys"
  echo ""
  echo -e "  ${BOLD}Dashboard login${RESET}: admin / <your password>"
  echo ""
  echo -e "${CYAN}  Send test traces:${RESET}"
  echo -e "    export PATH=\$PATH:\$(go env GOPATH)/bin"
  echo -e "    go install github.com/open-telemetry/opentelemetry-collector-contrib/cmd/telemetrygen@latest"
  echo -e "    telemetrygen traces --otlp-insecure --otlp-endpoint localhost:4317 \\"
  echo -e "      --duration 10s --service demo-service"
  echo ""
  echo -e "${CYAN}  Then view traces at:${RESET}"
  echo -e "    Wazuh Dashboard → Observability → Traces"
  echo ""
  echo -e "${CYAN}  Service management:${RESET}"
  echo -e "    sudo systemctl restart wazuh-indexer wazuh-manager wazuh-dashboard \\"
  echo -e "      data-prepper otelcol-contrib prometheus"
  echo ""
  echo -e "${CYAN}  Key config files:${RESET}"
  echo -e "    Data Prepper config   : ${DATA_PREPPER_DIR}/config/data-prepper-config.yaml"
  echo -e "    Data Prepper pipelines: ${DATA_PREPPER_DIR}/config/pipelines.yaml"
  echo -e "    OTel Collector config : /etc/otelcol-contrib/config.yaml"
  echo -e "    Prometheus config     : ${PROMETHEUS_DIR}/prometheus.yml"
  echo -e "    Wazuh Indexer config  : /etc/wazuh-indexer/opensearch.yml"
  echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  echo -e "${BOLD}${CYAN}"
  cat <<'BANNER'
  ╔═══════════════════════════════════════════════════════╗
  ║    OpenTelemetry + Wazuh APM Stack Installer          ║
  ║    Wazuh 4.14.5 | Data Prepper 2.16.0                 ║
  ║    OTel Collector 0.154.0 | Prometheus 3.12.0         ║
  ╚═══════════════════════════════════════════════════════╝
BANNER
  echo -e "${RESET}"

  preflight
  step1_pre_install
  step2_install_wazuh
  step3_install_data_prepper
  step4_install_otel
  step5_install_prometheus
  step6_connect_prometheus
  step7_verify
  print_summary
}

main "$@"
