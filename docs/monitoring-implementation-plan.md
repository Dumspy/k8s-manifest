# Monitoring Infrastructure Implementation Plan

**Status**: ✅ **APPROVED FOR PHASE 1**  
**Last Updated**: 2026-02-14  
**Architecture**: Hub-and-Spoke (Alloy-based unified collector)

---

## Pre-Phase 1 Checklist (Critical Fixes Applied)

- [x] Prometheus remote_write receiver flag enabled (`--web.enable-remote-write-receiver`)
- [x] Security model simplified to Tailscale ACLs only (removed nginx sidecars)
- [x] Agent resource table updated (Alloy only, removed Prometheus/Node Exporter)
- [x] External labels strategy added (`cluster=<name>`)
- [x] Alert metric verification confirmed (using `prometheus.exporter.unix`)
- [x] Storage alerts added (Prometheus/Loki full)
- [x] Connectivity alerts added (Tailscale)
- [x] Grafana datasource provisioning ConfigMap added
- [x] kube-state-metrics added to OCI hub
- [x] Validation commands fixed (removed basic auth)
- [x] NixOS Alloy config syntax corrected  

## Overview

Multi-cluster monitoring infrastructure with centralized hub on OCI cluster.

**Architecture**: Hub-and-Spoke (OCI Hub + Remote Spokes)  
**Hub Location**: OCI k3s cluster (1-3 nodes, 64GB storage per node)  
**Purpose**: Centralized storage and visualization for all metrics/logs
**Connectivity**: Tailscale VPN (100.64.0.0/10)

---

## Architecture

### Central Hub (OCI Cluster)

Namespace: `monitoring`

| Component | Purpose | Storage | Retention |
|-----------|---------|---------|-----------|
| Prometheus Server | Central metrics ingestion | 30GB | 15 days |
| Grafana | Visualization dashboards | None (stateless) | N/A |
| Access | Cloudflare Tunnel (handled separately) | N/A | N/A |
| Alertmanager | Alert routing (Discord webhook) | None | N/A |
| Loki | Log aggregation | 20GB | 15 days |
| Alloy | Log collection (DaemonSet on all OCI nodes) | None | N/A |
| Kube State Metrics | K8s API object metrics for OCI cluster | None | N/A |

### Homelab Kubernetes Cluster (Spoke)

The secondary k8s cluster runs a **lightweight Alloy-based stack** deployed via Helm:

| Component | Purpose | Deployment Method |
|-----------|---------|-------------------|
| **Grafana Alloy** | Unified collector (metrics + logs) | Helm chart (DaemonSet) |
| Kube State Metrics | Kubernetes API object metrics | Helm chart |

**Why Alloy?**
- Replaces Node Exporter + Promtail combo
- Single binary handles both metrics and logs
- Native support for Kubernetes (auto-discovers pods, collects logs)
- Pushes to remote hub via Tailscale

### Homelab NixOS VMs (Spokes)

NixOS systems use **Grafana Alloy** as the unified collector:

| Component | Purpose | Configuration Location |
|-----------|---------|----------------------|
| **Grafana Alloy** | Unified collector (metrics + logs) | NixOS configuration |

**Why Alloy on NixOS?**
- Modern replacement for "Node Exporter + Promtail"
- Single service handles both metrics and logs
- Native NixOS module support
- Declarative configuration via `configuration.nix`

### Data Flow (Hub-and-Spoke)

**Hub (OCI Cluster)** receives data from all Spokes via Tailscale VPN:

```
┌─────────────────────────────────────────────────────────────────┐
│                         OCI HUB                                  │
│  ┌──────────────────┐  ┌──────────┐  ┌──────────────────┐       │
│  │ Prometheus       │  │ Loki     │  │ Grafana          │       │
│  │ (30GB storage)   │  │ (20GB)   │  │ (Visualization)  │       │
│  │ Remote Receiver  │  │ Logs     │  │                  │       │
│  └────────▲─────────┘  └────▲─────┘  └──────────────────┘       │
└───────────┼─────────────────┼───────────────────────────────────┘
            │                 │
            │   All data pushed via Tailscale (100.x.x.x)
            │                 │
   ┌────────┴─────────────────┴────────┐
   │                                   │
   │  ┌─────────────────────────────┐  │  ┌──────────────────────┐
   │  │   Homelab K8s Cluster       │  │  │   Homelab NixOS VMs  │
   │  │   ┌─────────────────────┐   │  │  │   ┌──────────────┐   │
   │  │   │ Alloy (DaemonSet)   │───┼──┼──┼──▶│ Alloy        │   │
   │  │   │ - Scrapes metrics   │   │  │  │   │ - Node exp   │   │
   │  │   │ - Collects pod logs │   │  │  │   │ - Log reader │   │
   │  │   │ - Pushes to Hub     │   │  │  │   │ - Pushes     │   │
   │  │   └─────────────────────┘   │  │  │   └──────────────┘   │
   │  └─────────────────────────────┘  │  └──────────────────────┘
   │                                   │
   └───────────────────────────────────┘
                   SPOKES
```

**Key Design Decisions:**
- **Push model**: Spokes push data to Hub (simpler than Hub scraping into Tailscale network)
- **Unified collector**: Alloy handles both metrics and logs everywhere
- **No scraping**: Hub Prometheus configured as remote_write receiver only
- **Security via Tailscale ACLs**: No additional authentication required on endpoints

---

## Chart Structure

### Chart 1: monitoring (Hub)

```
charts/monitoring/
├── Chart.yaml                  # Standalone chart
├── values.yaml                 # Configuration
└── templates/
    ├── _helpers.tpl            # Helm helpers
    ├── namespace.yaml          # monitoring namespace
    ├── storageclass-metrics.yaml
    ├── storageclass-logs.yaml
    ├── 1password-secret.yaml   # Hub credentials
    ├── networkpolicy.yaml      # Security rules
    ├── prometheus/
    │   ├── deployment.yaml
    │   ├── service.yaml
    │   ├── pvc.yaml
    │   └── configmap.yaml
    ├── grafana/
    │   ├── deployment.yaml
    │   ├── service.yaml
    │   └── configmap.yaml
    ├── alertmanager/
    │   ├── deployment.yaml
    │   ├── service.yaml
    │   └── configmap.yaml
    ├── loki/
    │   ├── statefulset.yaml
    │   ├── service.yaml
    │   ├── pvc.yaml
    │   └── configmap.yaml
    └── alloy/
        ├── daemonset.yaml
        ├── configmap.yaml
        └── service.yaml
```

### Chart 2: monitoring-agent (Spoke Clusters)

**Approach**: Wrapper chart around official Grafana Alloy Helm chart

```
charts/monitoring-agent/
├── Chart.yaml                       # Wrapper chart
├── values.yaml                      # Base Alloy configuration
├── values-stages/
│   ├── values-production.yaml       # Production overrides
│   ├── values-staging.yaml          # Staging overrides
│   └── values-development.yaml      # Development overrides
└── templates/
    └── 1password-secret.yaml        # Hub credentials
```

**Dependencies** (in Chart.yaml):
```yaml
dependencies:
  - name: alloy
    version: 1.x.x
    repository: https://grafana.github.io/helm-charts
  - name: kube-state-metrics
    version: 7.x.x
    repository: https://prometheus-community.github.io/helm-charts
```

**Why a wrapper chart?**
- Leverages official Alloy chart (maintained, tested)
- Adds our custom values hierarchy (base → stage → cluster)
- Includes kube-state-metrics for K8s API metrics
- Manages 1Password secrets for hub authentication

#### Values Hierarchy (Override Order)

**Level 1: Base Values** (`values.yaml`)
- Default configuration for all clusters
- Resource limits, scrape intervals, common settings

**Level 2: Stage Values** (`values-stages/*.yaml`)
- Environment-specific overrides (production, staging, dev)
- Retention policies, resource scaling, feature flags

**Level 3: Cluster-Specific Overrides**
- Per-cluster customizations in ArgoCD Application
- Unique endpoints, cluster-specific exporters

**Example Override Chain:**
```yaml
# values.yaml (base)
alloy:
  alloy:
    configMap:
      content: |-
        // Base configuration for all clusters
        prometheus.scrape "k8s_metrics" {
          targets = discovery.kubernetes.nodes.targets
          forward_to = [prometheus.remote_write.hub.receiver]
        }
        
        loki.source.kubernetes "pods" {
          forward_to = [loki.write.hub.receiver]
        }
        
        prometheus.remote_write "hub" {
          endpoint {
            url = "http://monitoring-hub:9090/api/v1/write"
          }
        }
        
        loki.write "hub" {
          endpoint {
            url = "http://monitoring-hub:3100/loki/api/v1/push"
          }
        }

# values-stages/production.yaml (stage override)
alloy:
  alloy:
    resources:
      limits:
        memory: 2Gi      # Override: more memory for prod
        cpu: 1000m       # Override: more CPU for prod

# ArgoCD Application (cluster-specific)
alloy:
  alloy:
    configMap:
      content: |-
        // Cluster-specific: custom scrape configs
        prometheus.scrape "custom_app" {
          targets = [{"__address__" = "custom-service:8080"}]
          forward_to = [prometheus.remote_write.hub.receiver]
        }
        
        // Include base config via import
        import.file "base_config" {
          filename = "/etc/alloy/base.river"
        }
```

#### ArgoCD Application Example

```yaml
# argo-apps/monitoring-agent-production.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: monitoring-agent-production
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/Dumspy/k8s-manifest
    path: charts/monitoring-agent
    targetRevision: HEAD
    helm:
      # Load in order: base -> stage -> cluster-specific
      valueFiles:
        - values.yaml                           # Level 1: Base
        - values-stages/production.yaml         # Level 2: Stage
        - values-clusters/production-euw1.yaml  # Level 3: Cluster-specific
  destination:
    server: https://production-euw1.kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

**Alternative: Inline Values for Simplicity**

```yaml
# For simpler deployments without separate cluster files
helm:
  valueFiles:
    - values.yaml
    - values-stages/production.yaml
  values: |
    # Cluster-specific overrides inline
    prometheus:
      remoteWrite:
        - url: "http://<HUB_TAILSCALE_IP>:9090/api/v1/write"
```

---

## Resource Allocation

### Hub Components

| Component | Memory Limit | CPU Limit | Memory Request | CPU Request |
|-----------|-------------|-----------|----------------|-------------|
| Prometheus | 8Gi | 2000m | 4Gi | 1000m |
| Grafana | 512Mi | 200m | 256Mi | 100m |
| Alertmanager | 512Mi | 200m | 256Mi | 100m |
| Loki | 4Gi | 1000m | 2Gi | 500m |
| Alloy | 256Mi | 200m | 128Mi | 100m |
| **Total** | **~13.5Gi** | **3.6 CPU** | **~7Gi** | **1.9 CPU** |

### Spoke Components (Secondary Cluster)

| Component | Memory Limit | CPU Limit | Memory Request | CPU Request |
|-----------|-------------|-----------|----------------|-------------|
| Grafana Alloy | 1Gi | 500m | 512Mi | 250m |
| Kube State Metrics | 256Mi | 200m | 128Mi | 100m |
| **Total per node** | **~1.3Gi** | **0.7 CPU** | **~640Mi** | **0.35 CPU** |

**Note**: Grafana Alloy replaces the previous "Prometheus Agent + Node Exporter + Promtail" combo with a single unified collector.

---

## Storage Configuration

### Storage Classes

**monitoring-metrics** (k3s local-storage)
- Size: 30GB
- Reclaim Policy: Retain
- Used by: Prometheus

**monitoring-logs** (k3s local-storage)
- Size: 20GB
- Reclaim Policy: Retain
- Used by: Loki

### Storage Math

**OCI Node Capacity**: 64GB per node  
**Monitoring Stack**: 50GB (30GB metrics + 20GB logs)  
**Headroom**: 14GB for workloads and system  
**Verdict**: ✅ Fits comfortably

---

## Implementation Phases

### Phase 1: Hub Infrastructure

**Goal**: Deploy monitoring stack on OCI cluster

1. Create `charts/monitoring/` structure
2. Create k3s storage classes
3. Deploy Prometheus server (30GB PVC, 15d retention)
4. Deploy Loki (20GB PVC, 15d retention, monolithic mode)
5. Deploy Grafana
6. Deploy Alertmanager
7. Deploy Alloy for OCI cluster log collection
8. Configure 1Password secrets for hub
9. Create network policies
10. Validate: `helm lint && kubectl apply --dry-run=client`
11. Access Grafana via port-forward

**Deliverables**:
- [ ] `charts/monitoring/` chart
- [ ] `argo-apps/monitoring.yaml` ArgoCD application
- [ ] Working Prometheus scraping OCI cluster
- [ ] Working Loki collecting OCI cluster logs
- [ ] Grafana accessible via port-forward

### Phase 2: Security & Datasources

**Goal**: Configure datasources and validate connectivity

1. Configure Tailscale NetworkPolicy (100.64.0.0/10) - defense-in-depth
2. Configure Grafana datasources (Prometheus, Loki)
3. Test connectivity from NixOS system via Tailscale
4. **Note**: Cloudflare Tunnel for Grafana access handled separately by user

**Deliverables**:
- [ ] NetworkPolicy restricting access to Tailscale IPs (defense-in-depth)
- [ ] Grafana datasources configured (via ConfigMap provisioning)
- [ ] Connectivity validated from NixOS system via Tailscale

#### Grafana Datasource Provisioning

Instead of manually configuring datasources in Grafana UI, we use ConfigMap provisioning:

```yaml
# charts/monitoring/templates/grafana/datasources.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasources
  namespace: monitoring
  labels:
    grafana_datasource: "1"
data:
  datasources.yaml: |
    apiVersion: 1
    
    datasources:
      - name: Prometheus
        type: prometheus
        access: proxy
        url: http://prometheus.monitoring.svc:9090
        isDefault: true
        editable: false
        jsonData:
          timeInterval: "30s"
      
      - name: Loki
        type: loki
        access: proxy
        url: http://loki.monitoring.svc:3100
        editable: false
        jsonData:
          derivedFields:
            - datasourceUid: Prometheus
              matcherRegex: "(\\w+):(\\d+)"
              name: trace_id
              url: "$${__value.raw}"
```

**Note**: Set `grafana_datasource: "1"` label to enable Grafana's provisioning scanner.

### Phase 3: Remote System Configuration

**Goal**: Connect secondary k8s cluster and first NixOS system

**Part A: Secondary Kubernetes Cluster**
1. Create `charts/monitoring-agent/` wrapper chart
2. Configure Grafana Alloy Helm chart dependency
3. Add kube-state-metrics for K8s API metrics
4. Set up values hierarchy (base → stage → cluster)
5. Configure hub tailnet endpoint in values
6. Deploy to secondary cluster via ArgoCD
7. Test metrics arriving in central Prometheus
8. Test logs arriving in central Loki
9. Create Grafana dashboard for k8s metrics

**Part B: NixOS System**
10. Add Alloy configuration to `configuration.nix`
11. Configure metrics collection (node exporter via Alloy)
12. Configure logs collection (journal via Alloy)
13. Configure hub tailnet endpoint
14. Test metrics/logs arriving in hub
15. Document NixOS configuration pattern

**Deliverables**:
- [ ] `charts/monitoring-agent/` chart created with values hierarchy (base → stage → cluster)
- [ ] `values-stages/` directory with production/staging/development configs
- [ ] Example ArgoCD Application showing values override chain
- [ ] Secondary cluster connected via Helm chart
- [ ] First NixOS system connected
- [ ] Metrics visible in central Grafana
- [ ] Logs searchable in central Grafana
- [ ] Documentation for both deployment methods

### Phase 4: Scale & Harden

**Goal**: Deploy to remaining systems and harden

1. Deploy monitoring-agent to additional k8s clusters (if any)
2. Apply NixOS module to additional systems
3. Configure Alertmanager routing rules
4. Set up basic alerts (system down, high resource usage, PVC full)
5. Verify PVC backups working (external system)
6. Create runbook for common issues
7. Document architecture for team
8. Review and optimize resource usage

**Deliverables**:
- [ ] All clusters connected
- [ ] All NixOS systems connected
- [ ] Alertmanager routing configured
- [ ] Runbook created
- [ ] Documentation complete

---

## Configuration Details

### Prometheus Server Config

**Scrape Interval**: 30 seconds
**Retention**: 15 days
**Storage**: 30GB with 28GB retention size limit
**Scrape Targets**: OCI cluster only (pods, nodes, services)
**Remote Write Receiver**: Enabled (`--web.enable-remote-write-receiver`)
**External Labels**: `cluster=oci-hub` (prevents metric collision)
**Compression**: Enabled (TSDB)
**Authentication**: None (secured via Tailscale ACLs)

### Loki Config

**Deployment Mode**: Monolithic (singleBinary)
**Retention**: 15 days
**Storage**: 20GB
**Index Period**: 24 hours
**Chunk Size**: 1MB
**Compression**: Snappy
**Compactor**: Enabled (to maintain storage target)
**Authentication**: None (secured via Tailscale ACLs)

**Compaction Config:**
```yaml
compactor:
  retention_enabled: true
  retention_delete_delay: 2h
  retention_delete_worker_count: 150
```

### External Labels Strategy

**Critical for Multi-Cluster**: Every cluster must set `external_labels.cluster` to prevent metric collision.

**OCI Hub:**
```yaml
external_labels:
  cluster: oci-hub
  environment: production
```

**Secondary K8s Cluster:**
```yaml
external_labels:
  cluster: homelab-k8s
  environment: production
```

**NixOS Systems:**
```yaml
external_labels:
  cluster: homelab-nixos
  host: "${config.networking.hostName}"
```

**Benefits:**
- Prevents metric collision when querying
- Enables filtering by cluster: `{cluster="homelab-k8s"}`
- Clean cross-cluster comparison

### Alloy Config

**Hub Role**: Collect logs from OCI cluster containers  
**Agent Role**: Collect logs from remote cluster, push to hub Loki  
**Config Format**: River  
**Log Sources**: Container logs, systemd (optional), custom paths

---

## NixOS System Requirements

NixOS systems use **Grafana Alloy** as the unified collector. Alloy replaces the "Node Exporter + Promtail" combo with a single service.

### NixOS Configuration Example

Add this to your VM's `configuration.nix`. Note that we use Tailscale IPs for the remote endpoints.

```nix
{ config, pkgs, ... }:

{
  # Enable the Alloy service
  services.alloy = {
    enable = true;
    # Alloy uses a 'flow' configuration syntax (River)
    config = ''
      // --- METRICS COLLECTION ---
      prometheus.exporter.unix "local_system" {
        set_collectors = ["systemd", "filesystem", "cpu", "meminfo", "disk", "loadavg", "netdev"]
      }

      prometheus.scrape "metrics_scraper" {
        targets    = prometheus.exporter.unix.local_system.targets
        forward_to = [prometheus.remote_write.remote_hub.receiver]
        scrape_interval = "30s"
      }

      prometheus.remote_write "remote_hub" {
        endpoint {
          url = "http://<HUB_TAILSCALE_IP>:9090/api/v1/write"
        }
      }

      // --- LOGS COLLECTION ---
      loki.source.journal "read_journal" {
        forward_to = [loki.write.remote_loki.receiver]
        labels     = { 
          job = "systemd-journal"
          host = "${config.networking.hostName}"
        }
      }

      loki.write "remote_loki" {
        endpoint {
          url = "http://<HUB_TAILSCALE_IP>:3100/loki/api/v1/push"
        }
      }
    '';
  };
}
```

### What This Does

**Metrics Path:**
- `prometheus.exporter.unix` - Collects system metrics (CPU, memory, disk, network, load)
- `prometheus.scrape` - Scrapes the local metrics
- `prometheus.remote_write` - Pushes to hub Prometheus via Tailscale

**Logs Path:**
- `loki.source.journal` - Reads systemd journal logs
- `loki.write` - Pushes to hub Loki via Tailscale

**Benefits:**
- Single binary handles everything
- Declarative NixOS configuration
- Automatic retries and buffering
- No separate Node Exporter or Promtail needed
  config = ''
    local.file_match "logs" {
      path_targets = [{"__path__" = "/var/log/**/*.log"}]
    }

    loki.source.file "logs" {
      targets    = local.file_match.logs.targets
      forward_to = [loki.write.hub.receiver]
    }

    loki.write "hub" {
      endpoint {
        name = "loki"
        url  = "http://<HUB_TAILSCALE_IP>:3100/loki/api/v1/push"
      }
    }
  '';
};
```

**3. Credentials**
- No credentials required (secured via Tailscale ACLs)

### Tailscale Requirements
- All NixOS systems must be on same Tailscale network as OCI cluster
- Magic DNS enabled for easy hostname resolution (optional)

---

## Alertmanager Configuration

**Initial Setup**: Discord webhook for notifications  
**Future**: May migrate to PagerDuty for on-call rotation

### Alert Routing Rules

```yaml
# Alertmanager configuration (stored in 1Password)
route:
  receiver: 'discord'
  group_by: ['alertname', 'severity']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  routes:
    - match:
        severity: critical
      receiver: 'discord-critical'
      repeat_interval: 1h

receivers:
  - name: 'discord'
    discord_configs:
      - webhook_url: '<from 1Password>'
        title: 'Monitoring Alert'
        message: |
          {{ range .Alerts }}
          **{{ .Annotations.summary }}**
          Severity: {{ .Labels.severity }}
          {{ .Annotations.description }}
          {{ end }}

  - name: 'discord-critical'
    discord_configs:
      - webhook_url: '<from 1Password>'
        title: 'CRITICAL: Monitoring Alert'
        message: |
          @everyone {{ range .Alerts }}
          **{{ .Annotations.summary }}**
          Severity: {{ .Labels.severity }}
          {{ .Annotations.description }}
          {{ end }}
```

### Basic Alert Rules

**✅ Metric Verification**: These alerts use metrics from `prometheus.exporter.unix` (enabled in Alloy on all systems).

```yaml
# Prometheus alerting rules
groups:
  - name: system-alerts
    rules:
      - alert: InstanceDown
        expr: up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Instance {{ $labels.instance }} down"
          description: "{{ $labels.instance }} has been down for more than 1 minute"

      - alert: HighMemoryUsage
        expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage on {{ $labels.instance }}"
          description: "Memory usage is above 85% for 5 minutes"

      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage on {{ $labels.instance }}"
          description: "CPU usage is above 80% for 5 minutes"

  - name: storage-alerts
    rules:
      - alert: LokiStorageFull
        expr: loki_ingester_chunk_utilization > 0.9
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Loki storage nearly full"
          description: "Loki storage on {{ $labels.instance }} is approaching capacity"

      - alert: PVCAboveThreshold
        expr: (kubelet_volume_stats_capacity_bytes - kubelet_volume_stats_available_bytes) / kubelet_volume_stats_capacity_bytes > 0.85
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "PVC usage above 85%"
          description: "PVC {{ $labels.persistentvolumeclaim }} is above 85% full"

  - name: connectivity-alerts
    rules:
      - alert: TailscaleConnectivityLost
        expr: up{job="alloy"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Tailscale connectivity lost"
          description: "Alloy on {{ $labels.instance }} cannot reach monitoring hub via Tailscale"
```

---

## Secrets Management

### 1Password Vault Structure

**Vault**: `infrastructure`

**Item**: `monitoring-hub`
```
grafana_admin_password: <generated>
alertmanager_discord_webhook: <generated>
alertmanager_discord_critical_webhook: <generated>
```

**Item**: `monitoring-secondary-cluster`
```
cluster_name: secondary-k8s
hub_endpoint: http://<HUB_TAILSCALE_IP>
```

**Item**: `monitoring-nixos-systems` (per-system items)
```
system_name: <hostname>
hub_endpoint: http://<HUB_TAILSCALE_IP>
```

**Note**: No authentication credentials needed for Prometheus/Loki endpoints - secured via Tailscale ACLs.

### Secret Implementation

```yaml
# templates/1password-secret.yaml
apiVersion: onepassword.com/v1
kind: OnePasswordItem
metadata:
  name: monitoring-secrets
  namespace: monitoring
spec:
  itemPath: "vaults/infrastructure/items/monitoring-hub"
```

---

## Network Security

### NetworkPolicy (Hub)

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: monitoring-hub
  namespace: monitoring
spec:
  podSelector: {}
  policyTypes:
    - Ingress
  ingress:
    # Internal traffic
    - from:
        - namespaceSelector:
            matchLabels:
              name: monitoring
    # Tailscale network (100.64.0.0/10)
    - from:
        - ipBlock:
            cidr: 100.64.0.0/10
      ports:
        - protocol: TCP
          port: 9090  # Prometheus remote_write
        - protocol: TCP
          port: 3100  # Loki push
```

### Authentication

**Security Model**: Tailscale ACLs as primary security boundary
- All monitoring components accessible via tailnet (100.64.0.0/10)
- ACLs control which devices can access hub services
- No additional authentication required on endpoints

**Components**:
- **Prometheus Remote Write**: No auth (secured by Tailscale ACLs)
- **Loki Push**: No auth (secured by Tailscale ACLs)
- **Grafana**: Internal auth (admin user), external access via Cloudflare Tunnel
- **Alertmanager**: No external access (internal only)

### Connectivity

**NixOS to Hub**: Tailscale VPN
- All NixOS systems connect via Tailscale (100.x.x.x/10)
- Secure private network, no public internet exposure needed
- NetworkPolicy restricts remote_write to Tailscale IPs only

**Grafana Access**: Cloudflare Tunnel (handled separately)
- User will configure Cloudflare Tunnel for Grafana access
- No ingress configuration needed in monitoring chart

---

## Monitoring Checklist

### Health Checks

- [ ] Prometheus target page shows all targets UP
- [ ] Loki ready endpoint returns 200
- [ ] Grafana health endpoint returns 200
- [ ] Alloy metrics endpoint accessible

### Data Validation

- [ ] Metrics appearing in Prometheus (query: `up`)
- [ ] Logs appearing in Loki (search: `{job="alloy"}`)
- [ ] Dashboards loading in Grafana
- [ ] Remote cluster data visible

### Resource Monitoring

- [ ] PVC usage under 80%
- [ ] Memory usage within limits
- [ ] CPU usage within limits
- [ ] Network bandwidth acceptable

---

## Validation Commands

```bash
# Lint chart
helm lint charts/monitoring

# Dry run
helm template charts/monitoring | kubectl apply --dry-run=client -f -

# Check pods
kubectl get pods -n monitoring

# Port forward Grafana
kubectl port-forward svc/grafana 3000:3000 -n monitoring

# Check Prometheus targets
curl http://localhost:9090/api/v1/targets

# Check Loki ready
curl http://loki.monitoring.svc:3100/ready

# Test remote_write endpoint (via Tailscale, no auth required)
# From NixOS system, test connectivity (will get 204 No Content on success):
curl -X POST http://<HUB_TAILSCALE_IP>:9090/api/v1/write -v

# Test Loki push endpoint (via Tailscale, no auth required):
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"streams":[{"stream":{"job":"test"},"values":[["'$(( $(date +%s) * 1000000000 ))'","test log"]]}]}' \
  http://<HUB_TAILSCALE_IP>:3100/loki/api/v1/push
```

---

## Rollback Plan

If issues occur during deployment:

1. **ArgoCD**: Sync to previous revision
2. **Helm**: `helm rollback monitoring <revision>`
3. **Manual**: Scale down deployments, delete PVCs (data retained), redeploy
4. **Data**: PVC reclaim policy is `Retain`, so data persists

---

## Next Steps

1. Review this plan
2. Confirm architecture decisions
3. Begin Phase 1 implementation
4. Create GitHub issues for each phase

---

## Decisions Made

| Question | Decision |
|----------|----------|
| **NixOS connectivity** | ✅ Tailscale VPN (100.64.0.0/10) |
| **Grafana access** | ✅ User handles via Cloudflare Tunnel |
| **Dashboard storage** | ✅ Start with UI, migrate to Git later |
| **Backup strategy** | ✅ Handled externally (no action needed) |
| **Alert destinations** | ✅ Discord webhook (may move to PagerDuty) |

## Dashboard Migration Strategy

**Phase 1: Manual Configuration**
- Build dashboards via Grafana UI
- Iterate and refine based on needs
- Document dashboard purposes

**Phase 2: Git Migration**
- Export dashboard JSON from UI
- Store in `charts/monitoring/dashboards/`
- Configure Grafana sidecar for auto-loading
- Update documentation

**Benefits of this approach:**
- Start quickly without complex setup
- Refine dashboards based on actual usage
- Version control once stable
- Easy rollback to previous dashboard versions

---

## Executive Summary

### What We're Building

A **Hub-and-Spoke** monitoring infrastructure:
- **Hub** (OCI Cluster): Central storage and visualization (LGTM stack)
- **Spokes** (Homelab): Data collectors pushing to the Hub via Tailscale VPN

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      HUB (OCI Cluster)                       │
│  ┌──────────────┐  ┌──────────┐  ┌──────────────────────┐   │
│  │ Prometheus   │  │ Loki     │  │ Grafana              │   │
│  │ 30GB/15d     │  │ 20GB/15d │  │ Visualization        │   │
│  │ Remote Write │  │ Receiver │  │ Alertmanager (Discord│   │
│  │ Receiver     │  │          │  │                      │   │
│  └──────▲───────┘  └────▲─────┘  └──────────────────────┘   │
└───────┼────────────────┼────────────────────────────────────┘
        │                │
        └──────┬─────────┘
               │ Tailscale VPN (100.64.0.0/10)
       ┌───────┴────────┐
       │                │
┌──────▼──────┐  ┌──────▼──────┐
│ Homelab K8s │  │ NixOS VMs   │
│ ┌─────────┐ │  │ ┌─────────┐ │
│ │ Alloy   │ │  │ │ Alloy   │ │
│ │ - K8s   │ │  │ │ - Node  │ │
│ │   logs  │ │  │ │   exp   │ │
│ │ - Node  │ │  │ │ - Logs  │ │
│ │   exp   │ │  │ └─────────┘ │
│ └─────────┘ │  └─────────────┘
└─────────────┘
   SPOKES
```

### Key Design Decisions

**1. Unified Collector: Grafana Alloy**
- Replaces "Node Exporter + Promtail" combo
- Single binary handles metrics AND logs
- Runs on all systems: OCI, K8s clusters, NixOS VMs
- Native NixOS module support

**2. Push Model (Not Pull)**
- Spokes push data to Hub via Tailscale
- Easier than Hub scraping into home network
- Works through NAT/firewalls

**3. Technology Stack**
- **Metrics**: Prometheus (remote_write receiver)
- **Logs**: Loki
- **Visualization**: Grafana
- **Collector**: Grafana Alloy (everywhere)
- **Connectivity**: Tailscale VPN

**4. Security Model: Tailscale ACLs**
- Primary security boundary is the tailnet itself
- No additional authentication required on endpoints
- ACLs control device access to monitoring services
- NetworkPolicy provides defense-in-depth

### What's Different

**Instead of:**
- Prometheus Agent + Node Exporter + Promtail (3 components)

**We use:**
- Grafana Alloy (1 component, handles everything)

### Implementation Readiness

✅ Hub-and-Spoke architecture defined
✅ Unified Alloy collector approach validated
✅ Resource allocation calculated (50GB storage, ~13.5GB RAM)
✅ Security model defined (Tailscale ACLs + NetworkPolicy defense-in-depth)
✅ 4-phase implementation plan with deliverables
✅ NixOS configuration example provided
✅ Values hierarchy for multi-cluster deployments
✅ Alert rules and Discord routing configured
✅ Secrets management strategy (1Password)

### Ready for Build Phase

**Status: ✅ APPROVED FOR IMPLEMENTATION**

All critical fixes from both reviews have been incorporated:

✅ Remote write receiver flag
✅ Simplified auth model (Tailscale ACLs only)
✅ Resource table corrected
✅ External labels strategy
✅ Grafana datasource provisioning
✅ kube-state-metrics on hub
✅ Storage & connectivity alerts
✅ Validation commands fixed

**Proceed to Phase 1: Hub Infrastructure**
