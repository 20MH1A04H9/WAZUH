#!/usr/bin/env bash
# =============================================================================
# K8s Wazuh Demo — Deploy / Teardown Script
# Deploys the full OTel-instrumented demo stack into a Kubernetes cluster
# and wires it up to an external Wazuh server.
#
# Usage:
#   Deploy:   sudo ./deploy.sh --wazuh-ip 10.15.0.4
#   Teardown: sudo ./deploy.sh --teardown
# =============================================================================
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────
WAZUH_IP="${WAZUH_IP:-}"
WAZUH_DATA_PREPPER_PORT="21890"
PROMETHEUS_CONFIG="/opt/prometheus/prometheus.yml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()     { echo -e "${GREEN}[✔]${RESET} $*"; }
info()    { echo -e "${CYAN}[→]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[!]${RESET} $*"; }
error()   { echo -e "${RED}[✘]${RESET} $*" >&2; exit 1; }
section() { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════${RESET}"; \
            echo -e "${BOLD}${CYAN}  $*${RESET}"; \
            echo -e "${BOLD}${CYAN}══════════════════════════════════════${RESET}\n"; }

usage() {
  echo "Usage: $0 [--wazuh-ip <IP>] [--teardown] [--help]"
  echo ""
  echo "  --wazuh-ip <IP>   IP address of your Wazuh server (required for deploy)"
  echo "  --teardown        Remove all demo resources from the cluster"
  echo "  --help            Show this help"
  exit 0
}

# ── Parse args ────────────────────────────────────────────────────────────────
TEARDOWN=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --wazuh-ip) WAZUH_IP="$2"; shift 2 ;;
    --teardown) TEARDOWN=true; shift ;;
    --help) usage ;;
    *) error "Unknown argument: $1" ;;
  esac
done

# ── Preflight ─────────────────────────────────────────────────────────────────
preflight() {
  section "Preflight Checks"

  command -v kubectl &>/dev/null || error "kubectl not found. Install kubectl first."
  kubectl cluster-info &>/dev/null || error "Cannot reach Kubernetes cluster. Check kubeconfig."

  K8S_VERSION=$(kubectl version --short 2>/dev/null | grep "Server" | awk '{print $3}')
  log "Kubernetes cluster reachable (${K8S_VERSION})"

  if [[ "${TEARDOWN}" == "false" ]] && [[ -z "${WAZUH_IP}" ]]; then
    echo -e "${YELLOW}Enter your Wazuh server IP address:${RESET}"
    read -rp "Wazuh IP: " WAZUH_IP
    [[ -z "${WAZUH_IP}" ]] && error "Wazuh IP cannot be empty."
  fi
}

# ── Teardown ──────────────────────────────────────────────────────────────────
teardown() {
  section "Tearing Down K8s Wazuh Demo"

  info "Deleting demo namespaces (this removes all resources within them)…"
  kubectl delete namespace wazuh-demo --ignore-not-found=true
  kubectl delete namespace monitoring --ignore-not-found=true

  info "Removing cluster-level RBAC…"
  kubectl delete clusterrole otel-collector-k8s-reader --ignore-not-found=true
  kubectl delete clusterrolebinding otel-collector-k8s-reader --ignore-not-found=true

  log "Teardown complete"
}

# ── Deploy ────────────────────────────────────────────────────────────────────
deploy() {
  section "Deploying K8s Wazuh OTel Demo"

  # ── 1. Patch secret with actual Wazuh IP ──
  info "Patching Wazuh connection secret (${WAZUH_IP}:${WAZUH_DATA_PREPPER_PORT})…"
  sed "s/YOUR_WAZUH_SERVER_IP/${WAZUH_IP}/" \
    "${SCRIPT_DIR}/base/01-wazuh-secret.yaml" > /tmp/wazuh-secret-patched.yaml

  # ── 2. Apply in order ──
  info "Applying namespaces and RBAC…"
  kubectl apply -f "${SCRIPT_DIR}/base/00-namespace-rbac.yaml"

  info "Applying Wazuh connection secret…"
  kubectl apply -f /tmp/wazuh-secret-patched.yaml

  info "Applying OTel Collector (DaemonSet)…"
  kubectl apply -f "${SCRIPT_DIR}/otel/01-otel-collector.yaml"

  info "Applying kube-state-metrics…"
  kubectl apply -f "${SCRIPT_DIR}/prometheus/02-kube-state-metrics.yaml"

  info "Applying NodePort services…"
  kubectl apply -f "${SCRIPT_DIR}/prometheus/05-nodeport-services.yaml"

  info "Applying demo microservices…"
  kubectl apply -f "${SCRIPT_DIR}/demo-apps/03-demo-services.yaml"

  # ── 3. Wait for pods to be ready ──
  section "Waiting for Pods to be Ready"
  info "Waiting for monitoring namespace…"
  kubectl wait --for=condition=ready pod -l app=otel-collector \
    -n monitoring --timeout=180s || warn "OTel Collector pods not ready yet"
  kubectl wait --for=condition=ready pod -l app=kube-state-metrics \
    -n monitoring --timeout=120s || warn "kube-state-metrics not ready yet"

  info "Waiting for demo apps…"
  kubectl wait --for=condition=ready pod -l tier=cache \
    -n wazuh-demo --timeout=120s || warn "Redis not ready yet"
  kubectl wait --for=condition=ready pod -l tier=frontend \
    -n wazuh-demo --timeout=180s || warn "Frontend pods not ready yet"

  # ── 4. Get node IP for Prometheus patch ──
  NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null || \
            kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || \
            echo "UNKNOWN")

  # ── 5. Patch external Prometheus on Wazuh server ──
  section "Updating Wazuh Server Prometheus Config"

  if [[ -f "${PROMETHEUS_CONFIG}" ]]; then
    info "Adding K8s scrape targets to ${PROMETHEUS_CONFIG}…"
    if grep -q "k8s-otelcol" "${PROMETHEUS_CONFIG}"; then
      warn "K8s scrape targets already present in Prometheus config — skipping"
    else
      cat >> "${PROMETHEUS_CONFIG}" <<PROMPATCH

  # ── K8s cluster metrics (added by k8s-wazuh-demo deploy script) ──
  - job_name: 'k8s-otelcol'
    static_configs:
      - targets: ['${NODE_IP}:30888']
    relabel_configs:
      - target_label: cluster
        replacement: wazuh-demo

  - job_name: 'k8s-metrics'
    static_configs:
      - targets: ['${NODE_IP}:30889']
    relabel_configs:
      - target_label: cluster
        replacement: wazuh-demo

  - job_name: 'kube-state-metrics'
    static_configs:
      - targets: ['${NODE_IP}:30880']
    relabel_configs:
      - target_label: cluster
        replacement: wazuh-demo
PROMPATCH
      curl -s -X POST http://localhost:9090/-/reload && log "Prometheus reloaded" || \
        warn "Prometheus reload failed — run: curl -X POST http://localhost:9090/-/reload"
    fi
  else
    warn "Prometheus config not found at ${PROMETHEUS_CONFIG}"
    warn "Manually add the K8s scrape targets from: ${SCRIPT_DIR}/prometheus/04-prometheus-patch.yaml"
    warn "Replace K8S_NODE_IP with: ${NODE_IP}"
  fi

  # ── 6. Summary ──
  print_summary "${NODE_IP}"
}

# ── Summary ───────────────────────────────────────────────────────────────────
print_summary() {
  local NODE_IP="${1:-UNKNOWN}"

  echo ""
  echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════${RESET}"
  echo -e "${BOLD}${GREEN}  K8s Demo Deployed!${RESET}"
  echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════${RESET}"
  echo ""
  echo -e "  ${BOLD}Demo Frontend${RESET}         →  http://${NODE_IP}:30080"
  echo -e "  ${BOLD}OTel Collector gRPC${RESET}   →  ${NODE_IP}:4317 (from pods: otel-collector.monitoring:4317)"
  echo -e "  ${BOLD}OTel Self-Metrics${RESET}     →  http://${NODE_IP}:30888/metrics"
  echo -e "  ${BOLD}K8s Metrics (Prom)${RESET}    →  http://${NODE_IP}:30889/metrics"
  echo -e "  ${BOLD}kube-state-metrics${RESET}    →  http://${NODE_IP}:30880/metrics"
  echo ""
  echo -e "  ${BOLD}Wazuh Dashboard${RESET}       →  https://${WAZUH_IP}:443"
  echo -e "    Observability → Traces  (demo app traces)"
  echo -e "    Observability → Metrics (K8s + OTel metrics via Prometheus)"
  echo ""
  echo -e "${CYAN}  Check pod status:${RESET}"
  echo -e "    kubectl get pods -n monitoring"
  echo -e "    kubectl get pods -n wazuh-demo"
  echo ""
  echo -e "${CYAN}  View OTel Collector logs:${RESET}"
  echo -e "    kubectl logs -n monitoring -l app=otel-collector -f"
  echo ""
  echo -e "${CYAN}  Verify traces reaching Wazuh:${RESET}"
  echo -e "    curl -sk -u admin:'PASSWORD' https://${WAZUH_IP}:9200/_cat/indices/otel* "
  echo ""
  echo -e "${CYAN}  Teardown:${RESET}"
  echo -e "    $0 --teardown"
  echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
echo -e "${BOLD}${CYAN}"
cat <<'BANNER'
  ╔══════════════════════════════════════════════════════╗
  ║   K8s → Wazuh OTel Demo                             ║
  ║   OTel Collector DaemonSet | kube-state-metrics     ║
  ║   opentelemetry-demo microservices | Prometheus      ║
  ╚══════════════════════════════════════════════════════╝
BANNER
echo -e "${RESET}"

preflight

if [[ "${TEARDOWN}" == "true" ]]; then
  teardown
else
  deploy
fi
