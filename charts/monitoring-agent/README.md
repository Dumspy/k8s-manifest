# Monitoring Agent Chart

Wrapper chart for deploying Grafana Alloy and Kube-state-metrics on spoke clusters to push metrics and logs to the central monitoring hub.

## Overview

This chart deploys:
- **Grafana Alloy**: Unified collector for metrics and logs
- **Kube-state-metrics**: Kubernetes API object metrics

These components collect data from the local cluster and push it to the central monitoring hub via Tailscale VPN.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    SPOKE CLUSTER                          │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Grafana Alloy (DaemonSet)                         │   │
│  │  - prometheus.exporter.unix (node metrics)        │   │
│  │  - loki.source.kubernetes (pod logs)             │   │
│  │  - prometheus.scrape (collect metrics)            │   │
│  │  - prometheus.remote_write → HUB via Tailscale   │   │
│  │  - loki.write → HUB via Tailscale               │   │
│  └─────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Kube-state-metrics                               │   │
│  │  - Exposes K8s API object metrics               │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ Tailscale VPN (push)
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    MONITORING HUB                          │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Prometheus + Loki (receive and store)              │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Values Hierarchy

Values are merged in the following order (later values override earlier ones):

1. **Base Values** (`values.yaml`)
   - Default configuration for all clusters
   - Resource limits, scrape intervals, common settings

2. **Stage Values** (`values-stages/<stage>.yaml`)
   - Environment-specific overrides (production, staging, dev)
   - Resource scaling, retention policies, feature flags

3. **Cluster-Specific Values** (`values-clusters/<cluster>.yaml`)
   - Per-cluster customizations
   - Unique endpoints, cluster-specific exporters

4. **ArgoCD Inline Values**
   - Final override in ArgoCD Application
   - Used for sensitive or cluster-specific data

### Example Override Chain

```yaml
# values.yaml (base)
alloy:
  resources:
    limits:
      memory: 512Mi

# values-stages/production.yaml (stage override)
alloy:
  resources:
    limits:
      memory: 1Gi  # More memory for production

# values-clusters/euw1-production.yaml (cluster override)
alloy:
  resources:
    limits:
      memory: 1.5Gi  # Even more for this large cluster

# ArgoCD Application (inline final override)
alloy:
  resources:
    limits:
      memory: 2Gi  # Maximum for this specific deployment
```

## Configuration

### Global Settings

```yaml
global:
  clusterName: "spoke-cluster"      # Unique cluster identifier
  environment: "production"          # Environment label
  hubEndpoint: "100.64.0.2"        # Hub Tailscale IP
```

### Grafana Alloy

```yaml
alloy:
  enabled: true
  resources:
    requests:
      memory: "512Mi"
      cpu: "250m"
    limits:
      memory: "1Gi"
      cpu: "500m"
```

### Kube-state-metrics

```yaml
kube-state-metrics:
  enabled: true
  resources:
    requests:
      memory: "128Mi"
      cpu: "100m"
    limits:
      memory: "256Mi"
      cpu: "200m"
```

## Deployment

### Via ArgoCD (Recommended)

Create an ArgoCD Application for each spoke cluster:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: monitoring-agent-homelab-k8s
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/Dumspy/k8s-manifest
    path: charts/monitoring-agent
    targetRevision: HEAD
    helm:
      valueFiles:
        - values.yaml
        - values-stages/production.yaml
        - values-clusters/homelab-k8s.yaml
      values: |
        global:
          clusterName: "homelab-k8s"
          hubEndpoint: "100.64.0.2"
  destination:
    name: homelab-cluster
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### Via Helm (Manual)

```bash
# Install to a specific cluster
helm install monitoring-agent \
  ./charts/monitoring-agent \
  --namespace monitoring \
  --create-namespace \
  --set global.clusterName=homelab-k8s \
  --set global.hubEndpoint=100.64.0.2 \
  -f values-stages/production.yaml
```

## Pre-Deployment Checklist

Before deploying to a spoke cluster:

- [ ] Tailscale is installed and connected to the tailnet
- [ ] Hub Tailscale IP is known and reachable
- [ ] 1Password operator is installed on the cluster
- [ ] 1Password vault item `monitoring-spoke` exists (if using secrets)
- [ ] Cluster has sufficient resources for Alloy + Kube-state-metrics

## Post-Deployment Verification

```bash
# Check pods are running
kubectl get pods -n monitoring

# Check Alloy logs for connection errors
kubectl logs -n monitoring -l app.kubernetes.io/name=alloy

# Verify metrics are being sent to hub
# (from hub cluster)
curl http://prometheus.monitoring.svc:9090/api/v1/query?query=up

# Verify logs are being sent to hub
# (from hub cluster)
curl 'http://loki.monitoring.svc:3100/loki/api/v1/query?query={cluster="homelab-k8s"}'
```

## Troubleshooting

### Alloy not connecting to hub

Check if Tailscale is working:
```bash
# From spoke cluster node
ping <HUB_TAILSCALE_IP>

# From Alloy pod
kubectl exec -n monitoring -it <alloy-pod> -- ping <HUB_TAILSCALE_IP>
```

### Missing metrics

Check Alloy configuration:
```bash
kubectl get configmap -n monitoring -o yaml alloy-configmap
```

### High resource usage

Adjust resource limits in cluster-specific values:
```yaml
# values-clusters/my-cluster.yaml
alloy:
  resources:
    limits:
      memory: "2Gi"
```

## Requirements

- Kubernetes 1.23+
- Tailscale installed on all nodes
- 1Password operator (if using secrets)
- Sufficient CPU/RAM for Alloy (~1Gi max) + Kube-state-metrics (~256Mi max)

## License

Same as parent project.
