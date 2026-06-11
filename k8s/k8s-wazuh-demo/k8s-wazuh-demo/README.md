# K8s → Wazuh OTel Demo

Complete Kubernetes demo that wires K8s metrics, traces, and service maps
into your existing Wazuh + OpenTelemetry stack.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Kubernetes Cluster                                  │
│                                                      │
│  namespace: wazuh-demo                               │
│    frontend  ──┐                                     │
│    cartservice ┤── OTLP traces ──┐                   │
│    productcatalog                │                   │
│    recommendationservice         │                   │
│    currencyservice               │                   │
│    loadgenerator (synthetic) ────┘                   │
│                                  │                   │
│  namespace: monitoring           ▼                   │
│    OTel Collector (DaemonSet) ◄──┘                   │
│      ├── kubeletstats receiver (node/pod metrics)    │
│      ├── k8s_cluster receiver (deployments etc.)     │
│      ├── prometheus receiver (kube-state-metrics)    │
│      │                                               │
│    kube-state-metrics ──────────►┘                   │
│                                                      │
│    NodePorts: 30888 / 30889 / 30880                  │
└──────────────────┬──────────────────────────────────┘
                   │
        ┌──────────┴───────────┐
        │  Traces (OTLP gRPC)  │  Metrics (Prometheus scrape)
        │  port 21890           │  ports 30888/30889/30880
        ▼                       ▼
┌─────────────────────────────────────────┐
│  Wazuh Server (10.15.0.4)               │
│                                         │
│  Data Prepper :21890                    │
│    └── otel-v1-apm-span-*               │
│    └── otel-v1-apm-service-map          │
│                                         │
│  Prometheus :9090                       │
│    └── k8s-otelcol (30888)              │
│    └── k8s-metrics  (30889)             │
│    └── kube-state-metrics (30880)       │
│                                         │
│  Wazuh Dashboard :443                   │
│    → Observability → Traces             │
│    → Observability → Metrics            │
└─────────────────────────────────────────┘
```

## Prerequisites

- Kubernetes cluster (minikube, k3s, EKS, GKE, AKS — any works)
- `kubectl` configured and pointing at the cluster
- Wazuh stack running (from `install-otel-wazuh-stack.sh`)
- The Wazuh server must be reachable from K8s nodes on port `21890`

## Quick Start

```bash
# 1. Clone / copy this directory to a machine with kubectl access

# 2. Deploy everything
chmod +x scripts/deploy.sh
./scripts/deploy.sh --wazuh-ip 10.15.0.4

# 3. Watch pods come up
kubectl get pods -n monitoring -w
kubectl get pods -n wazuh-demo -w

# 4. Verify traces are arriving in Wazuh
curl -sk -u admin:'PASSWORD' https://10.15.0.4:9200/_cat/indices/otel*
```

## File Structure

```
k8s-wazuh-demo/
├── base/
│   ├── 00-namespace-rbac.yaml     Namespaces + ClusterRole for OTel collector
│   └── 01-wazuh-secret.yaml       Wazuh server connection (patched by deploy.sh)
├── otel/
│   └── 01-otel-collector.yaml     OTel Collector DaemonSet + ConfigMap + Service
├── prometheus/
│   ├── 02-kube-state-metrics.yaml kube-state-metrics deployment
│   ├── 04-prometheus-patch.yaml   Manual Prometheus config snippet (reference)
│   └── 05-nodeport-services.yaml  NodePort services for external Prometheus scraping
├── demo-apps/
│   └── 03-demo-services.yaml      OTel-instrumented demo microservices
└── scripts/
    └── deploy.sh                  One-command deploy / teardown
```

## What You See in Wazuh Dashboard

### Observability → Traces
- Distributed traces across frontend, cart, product catalog, recommendations
- Service map showing inter-service calls
- Latency, error rate per service

### Observability → Metrics (via Prometheus `my_prometheus` datasource)
PPL queries for K8s data:

```sql
-- CPU by node
source = my_prometheus.k8s_node_cpu_usage_seconds_total
| stats sum(@value) by span(@timestamp, 1m), k8s_node_name

-- Pod memory
source = my_prometheus.k8s_pod_memory_working_set_bytes
| stats avg(@value) by span(@timestamp, 1m), k8s_pod_name, k8s_namespace_name

-- Deployments available replicas
source = my_prometheus.kube_deployment_status_replicas_available
| stats avg(@value) by span(@timestamp, 1m), deployment

-- Pod restarts
source = my_prometheus.kube_pod_container_status_restarts_total
| stats sum(@value) by span(@timestamp, 1m), pod, namespace
```

## Teardown

```bash
./scripts/deploy.sh --teardown
```

This removes the `wazuh-demo` and `monitoring` namespaces and all cluster-level RBAC.
The K8s scrape jobs added to `/opt/prometheus/prometheus.yml` on the Wazuh server
should be removed manually if no longer needed.

## Troubleshooting

| Issue | Check |
|---|---|
| OTel Collector CrashLoopBackOff | `kubectl logs -n monitoring -l app=otel-collector` |
| No traces in Wazuh | Verify port 21890 reachable from cluster nodes: `telnet 10.15.0.4 21890` |
| Prometheus targets down | Check NodePort reachability: `curl http://NODE_IP:30888/metrics` |
| Pods stuck Pending | Check node resources: `kubectl describe nodes` |
| kubeletstats 403 | Verify ClusterRole is bound: `kubectl get clusterrolebinding otel-collector-k8s-reader` |
