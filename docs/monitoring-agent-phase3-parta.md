# Monitoring Agent - Phase 3 Part A: Secondary Kubernetes Clusters

## Overview

The `monitoring-agent` chart is a wrapper around official Grafana Alloy and Kube-state-metrics Helm charts. It enables spoke clusters to collect metrics and logs, then push them to the central monitoring hub via Tailscale VPN.

## Chart Structure

```
charts/monitoring-agent/
├── Chart.yaml                      # Chart metadata + dependencies
├── values.yaml                     # Base configuration for all clusters
├── values-stages/                 # Environment-specific overrides
│   ├── production.yaml
│   ├── staging.yaml
│   └── development.yaml
├── values-clusters/               # Cluster-specific overrides (examples)
│   ├── homelab-k8s.yaml
│   └── euw1-production.yaml
├── templates/
│   └── 1password-secret.yaml     # Hub credentials (if needed)
└── README.md
```

## Components Deployed

### Grafana Alloy (DaemonSet)
- **Image**: `grafana/alloy:v1.13.1`
- **Purpose**: Unified collector for metrics + logs
- **Functionality**:
  - `prometheus.exporter.unix`: Node metrics (CPU, memory, disk, network)
  - `prometheus.scrape`: Scrapes metrics from exporters
  - `prometheus.remote_write`: Pushes metrics to hub Prometheus
  - `loki.source.kubernetes`: Collects pod logs
  - `loki.write`: Pushes logs to hub Loki

### Kube-state-metrics (Deployment)
- **Image**: `registry.k8s.io/kube-state-metrics:v2.14.0`
- **Purpose**: Exposes Kubernetes API object metrics
- **Metrics**: Pods, nodes, deployments, services, PVCs, etc.

## Values Hierarchy

Values are merged in this order (later values override earlier ones):

```
1. values.yaml (base)
   ↓
2. values-stages/<stage>.yaml (environment)
   ↓
3. values-clusters/<cluster>.yaml (cluster-specific)
   ↓
4. ArgoCD Application values (inline)
```

### Level 1: Base Values (`values.yaml`)

Default configuration for all clusters:
- Resource limits
- Scrape intervals
- Basic Alloy configuration
- External labels (cluster, environment)

### Level 2: Stage Values (`values-stages/*.yaml`)

Environment-specific overrides:

| Stage | Memory (Alloy) | CPU (Alloy) | Memory (KSM) | CPU (KSM) |
|-------|----------------|--------------|----------------|-------------|
| production | 512Mi / 1Gi | 250m / 500m | 128Mi / 256Mi | 100m / 200m |
| staging | 256Mi / 512Mi | 150m / 300m | 64Mi / 128Mi | 50m / 100m |
| development | 128Mi / 256Mi | 100m / 200m | 32Mi / 64Mi | 25m / 50m |

### Level 3: Cluster-Specific Values (`values-clusters/*.yaml`)

Per-cluster customizations:
- Unique cluster name
- Specific Tailscale hub endpoint
- Resource adjustments for cluster size
- Custom exporters or scrape configs

Example:
```yaml
global:
  clusterName: "homelab-k8s"
  hubEndpoint: "100.64.0.2"

alloy:
  resources:
    limits:
      memory: "768Mi"  # Cluster-specific adjustment
```

### Level 4: ArgoCD Inline Values

Final override in ArgoCD Application:
```yaml
helm:
  values: |
    global:
      clusterName: "homelab-k8s"
      hubEndpoint: "100.64.0.2"
```

## ArgoCD Deployment Patterns

### Pattern 1: Base + Stage + Cluster File

Use when you have dedicated cluster files:

```yaml
# argo-apps/monitoring-agent-homelab-k8s.yaml
helm:
  valueFiles:
    - values.yaml                           # Level 1
    - values-stages/production.yaml         # Level 2
    - values-clusters/homelab-k8s.yaml    # Level 3
```

**Pros**: Clean separation, reusable cluster files
**Cons**: More files to maintain

### Pattern 2: Base + Stage + Inline

Use when you want everything in the ArgoCD app:

```yaml
# argo-apps/monitoring-agent-staging.yaml
helm:
  valueFiles:
    - values.yaml
    - values-stages/staging.yaml         # Level 2
  values: |
    # Level 3 + 4 combined
    global:
      clusterName: "staging-cluster"
      hubEndpoint: "100.64.0.2"
```

**Pros**: Single file deployment
**Cons**: Harder to reuse cluster configs

### Pattern 3: Simple Inline (No Stage Files)

For simple deployments without stage hierarchy:

```yaml
# argo-apps/monitoring-agent-simple.yaml
helm:
  valueFiles:
    - values.yaml
  values: |
    global:
      clusterName: "simple-cluster"
      environment: "production"
      hubEndpoint: "100.64.0.2"
    alloy:
      resources:
        limits:
          memory: "1Gi"
          cpu: "500m"
```

**Pros**: Minimal files
**Cons**: No environment separation

## Example ArgoCD Applications

### Production Cluster with Cluster File

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

### Staging Cluster with Inline Values

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: monitoring-agent-staging
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
        - values-stages/staging.yaml
      values: |
        global:
          clusterName: "staging-cluster"
          hubEndpoint: "100.64.0.2"
  destination:
    name: staging-cluster
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## Pre-Deployment Requirements

### 1. Tailscale Connectivity

Ensure the spoke cluster can reach the hub:
```bash
# From a node in the spoke cluster
ping <HUB_TAILSCALE_IP>
curl http://<HUB_TAILSCALE_IP>:9090/-/healthy
```

### 2. 1Password Setup (Optional)

If using secrets, create the 1Password item:
```
Vault: infrastructure
Item: monitoring-spoke
  Fields:
    - hub_endpoint: http://<HUB_TAILSCALE_IP>
    - cluster_name: <cluster-identifier>
```

### 3. Resource Requirements

Ensure cluster has sufficient resources:
- **Alloy**: 512Mi - 2Gi RAM (depending on stage/cluster)
- **Kube-state-metrics**: 64Mi - 256Mi RAM
- **Total**: ~1Gi - 2.5Gi RAM per cluster

## Deployment Steps

### Step 1: Choose Deployment Pattern

Select one of the patterns above based on your needs.

### Step 2: Configure Values

Create or modify values files with:
- `global.clusterName`: Unique identifier
- `global.hubEndpoint`: Hub Tailscale IP
- Resource limits (if customizing)

### Step 3: Create ArgoCD Application

Create the ArgoCD Application file in `argo-apps/`.

### Step 4: Deploy

```bash
# Apply ArgoCD application
kubectl apply -f argo-apps/monitoring-agent-homelab-k8s.yaml

# Verify sync in ArgoCD UI
```

### Step 5: Verify

```bash
# Check pods are running
kubectl get pods -n monitoring

# Check Alloy is pushing metrics (from hub cluster)
curl 'http://prometheus.monitoring.svc:9090/api/v1/query?query=up{cluster="homelab-k8s"}'

# Check logs are being sent (from hub cluster)
curl 'http://loki.monitoring.svc:3100/loki/api/v1/query?query={cluster="homelab-k8s"}'
```

## Troubleshooting

### Issue: Alloy pods not starting

Check resource limits:
```bash
kubectl describe pod -n monitoring <alloy-pod>
```

Adjust resources in cluster-specific values if needed.

### Issue: Metrics not arriving at hub

1. Check Tailscale connectivity from pod:
```bash
kubectl exec -n monitoring -it <alloy-pod> -- ping <HUB_TAILSCALE_IP>
```

2. Check Alloy logs for errors:
```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=alloy
```

3. Verify hub Prometheus remote_write receiver is accessible:
```bash
curl http://<HUB_TAILSCALE_IP>:9090/-/healthy
```

### Issue: Logs not arriving at hub

1. Check Alloy logs for Loki write errors:
```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=alloy | grep loki
```

2. Verify hub Loki is accepting data:
```bash
curl http://<HUB_TAILSCALE_IP>:3100/ready
```

## Next Steps

After deploying monitoring-agent to the spoke cluster:

1. ✅ Verify metrics are visible in hub Grafana
2. ✅ Verify logs are searchable in hub Loki
3. ✅ Create Grafana dashboards for spoke cluster
4. ✅ Configure alerts for spoke cluster health
5. ✅ Proceed to Phase 3 Part B: NixOS systems

## Files Created

### Chart Files
- `charts/monitoring-agent/Chart.yaml`
- `charts/monitoring-agent/values.yaml`
- `charts/monitoring-agent/values-stages/production.yaml`
- `charts/monitoring-agent/values-stages/staging.yaml`
- `charts/monitoring-agent/values-stages/development.yaml`
- `charts/monitoring-agent/values-clusters/homelab-k8s.yaml`
- `charts/monitoring-agent/values-clusters/euw1-production.yaml`
- `charts/monitoring-agent/templates/1password-secret.yaml`
- `charts/monitoring-agent/.helmignore`
- `charts/monitoring-agent/README.md`

### ArgoCD Examples
- `argo-apps/monitoring-agent-homelab-k8s.yaml`
- `argo-apps/monitoring-agent-staging.yaml`

## Validation

```bash
# Lint chart
helm lint charts/monitoring-agent

# Check dependencies
ls charts/monitoring-agent/charts/

# Dry-run render
helm template charts/monitoring-agent \
  --set global.clusterName=test \
  --set global.hubEndpoint=100.64.0.1 \
  | kubectl apply --dry-run=client -f -
```

✅ Chart validated successfully
✅ Dependencies downloaded (alloy, kube-state-metrics)
✅ Ready for deployment to spoke clusters
