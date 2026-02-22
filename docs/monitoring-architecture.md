# Monitoring Architecture Documentation

**Version**: 1.0
**Last Updated**: 2026-02-21
**Status**: Production Ready

---

## Executive Summary

Our monitoring infrastructure uses a **Hub-and-Spoke architecture** where:

- **Hub**: Central monitoring cluster on OCI (LGTM stack: Loki, Grafana, Tempo, Mimir)
- **Spokes**: Remote systems (K8s clusters, NixOS VMs) that push data to hub
- **Connectivity**: Tailscale VPN for secure, private network communication
- **Unified Collector**: Grafana Alloy handles both metrics and logs everywhere

**Design Goals**:
- Centralized visibility across all systems
- Minimal agent complexity on spoke systems
- Secure communication via Tailscale
- Scalable storage with configurable retention
- Efficient resource utilization

---

## System Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          TAILSCALE VPN (100.64.0.0/10)           │
└─────────────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              │               │               │
        ┌─────▼─────┐   ┌───▼────┐   ┌───▼────┐
        │   Hub     │   │ Spoke  │   │ Spoke  │
        │ (OCI k3s) │   │ (K8s)  │   │ (NixOS)│
        │           │   │         │   │         │
        │  LGTM     │   │  Alloy  │   │  Alloy  │
        │  Stack    │   │ + KSM   │   │         │
        │           │   │         │   │         │
        └─────┬─────┘   └────┬───┘   └────┬─────┘
              │               │               │
              ▼               ▼               ▼
        ┌─────────────────────────────────────────────┐
        │   Central Storage & Visualization        │
        │  - Prometheus (metrics)                │
        │  - Loki (logs)                        │
        │  - Grafana (dashboards)                │
        │  - Alertmanager (alerts)                │
        └─────────────────────────────────────────────┘
```

---

## Components

### Hub Components (OCI Cluster)

#### Prometheus
- **Version**: v3.5.1
- **Role**: Central metrics storage and query engine
- **Storage**: 30GB PVC, 15-day retention
- **Mode**: remote_write receiver (push-based from spokes)
- **Key Features**:
  - Receives metrics from all spokes via remote_write
  - Stores OCI cluster metrics via scraping
  - Evaluates alert rules
  - External labels: `cluster=oci-hub, environment=production`

#### Loki
- **Version**: v3.2.0
- **Role**: Central log aggregation and query engine
- **Storage**: 20GB PVC, 15-day retention
- **Mode**: Monolithic
- **Key Features**:
  - Receives logs from all spokes via push API
  - Stores OCI cluster logs
  - Indexes logs for fast querying
  - Compaction enabled for storage efficiency

#### Grafana
- **Version**: 11.3.0
- **Role**: Visualization and dashboards
- **Storage**: None (stateless)
- **Key Features**:
  - Pre-configured datasources (Prometheus, Loki)
  - Provisioned via ConfigMap
  - Admin password from 1Password
  - Manual dashboard creation initially (will migrate to Git)

#### Alertmanager
- **Version**: v0.31.1
- **Role**: Alert routing and notification
- **Storage**: None (stateless)
- **Key Features**:
  - Routes alerts to Discord webhooks
  - Grouping and deduplication
  - Repeat intervals
  - Different receivers for critical vs warning

#### Grafana Alloy (OCI Cluster)
- **Version**: v1.13.1
- **Role**: OCI cluster log + metrics collector
- **Deployment**: DaemonSet
- **Key Features**:
  - Collects OCI cluster pod logs via `loki.source.kubernetes`
  - Exposes node metrics via `prometheus.exporter.unix`
  - Pushes to hub Loki and Prometheus

#### Kube-state-metrics
- **Version**: v2.14.0
- **Role**: K8s API object metrics
- **Deployment**: Deployment
- **Key Features**:
  - Exposes metrics for pods, deployments, services, PVCs, etc.
  - Scrape target for Prometheus

---

### Spoke Components (Remote Systems)

#### Grafana Alloy (K8s Clusters)
- **Version**: v1.13.1
- **Role**: Unified metrics + logs collector
- **Deployment**: DaemonSet
- **Key Features**:
  - Collects node metrics via `prometheus.exporter.unix`
  - Collects pod logs via `loki.source.kubernetes`
  - Scrapes Kube-state-metrics
  - Pushes to hub via `prometheus.remote_write`
  - Pushes logs to hub via `loki.write`
  - External labels prevent metric collision

#### Kube-state-metrics (K8s Clusters)
- **Version**: v2.14.0
- **Role**: K8s API object metrics
- **Deployment**: Deployment
- **Key Features**:
  - Exposes cluster-level metrics
  - Scrape target for Alloy

#### Grafana Alloy (NixOS VMs)
- **Version**: v1.13.1
- **Role**: Unified metrics + logs collector
- **Deployment**: NixOS service
- **Key Features**:
  - Collects system metrics via `prometheus.exporter.unix`
  - Collects systemd journal logs via `loki.source.journal`
  - Pushes to hub via `prometheus.remote_write`
  - Pushes logs to hub via `loki.write`

---

## Data Flow

### Metrics Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                      SPOKE SYSTEMS                              │
├─────────────────────┬─────────────────────┬─────────────────────┤
│  OCI Cluster       │  K8s Cluster       │  NixOS VM          │
│                     │                     │                     │
│  Alloy (node)  ────┼───▶ Alloy (node)  ──┼───▶ Alloy (node)  │
│  └ prom.scrape    │    └ prom.scrape    │    └ prom.scrape    │
│      ↓            │        ↓            │        ↓            │
│  prom.rw (push)  │    prom.rw (push)  │    prom.rw (push)  │
│      ↓            │        ↓            │        ↓            │
└───────────────────┴────────┼───────────┴────────┼───────────┘
                            │ Tailscale          │
                            │ (100.64.0.0/10)    │
                            ▼                    │
┌─────────────────────────────────────────────────────────────────────┐
│                          HUB (OCI)                             │
│                                                               │
│  Prometheus ◀──────────────────────────────────────────────────┤
│  └ prom.remote_write.receiver                                  │
│                                                               │
│  Stores metrics with external_labels:                              │
│    - cluster: "oci-hub" / "homelab-k8s" / "homelab-nixos"    │
│    - environment: "production"                                    │
│                                                               │
│  Evaluates alert rules                                             │
│  Sends alerts to Alertmanager                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Logs Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                      SPOKE SYSTEMS                              │
├─────────────────────┬─────────────────────┬─────────────────────┤
│  OCI Cluster       │  K8s Cluster       │  NixOS VM          │
│                     │                     │                     │
│  Alloy (node)  ────┼───▶ Alloy (node)  ──┼───▶ Alloy (node)  │
│  └ loki.source.k8s │    └ loki.source.k8s│    └ loki.source.j│
│      ↓            │        ↓            │        ↓            │
│  loki.write       │    loki.write       │    loki.write       │
│      ↓            │        ↓            │        ↓            │
└───────────────────┴────────┼───────────┴────────┼───────────┘
                            │ Tailscale          │
                            │ (100.64.0.0/10)    │
                            ▼                    │
┌─────────────────────────────────────────────────────────────────────┐
│                          HUB (OCI)                             │
│                                                               │
│  Loki ◀─────────────────────────────────────────────────────────┤
│  └ /loki/api/v1/push receiver                                 │
│                                                               │
│  Stores logs with labels:                                        │
│    - cluster: "oci-hub" / "homelab-k8s" / "homelab-nixos"        │
│    - job: <workload>                                             │
│    - pod: <pod-name>                                              │
│    - namespace: <k8s-namespace>                                   │
│                                                               │
│  Indexes logs for fast querying                                  │
│  Compacts old data                                               │
└─────────────────────────────────────────────────────────────────────┘
```

### Alerts Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                       HUB (OCI)                               │
│                                                               │
│  Prometheus                                                    │
│  └ Evaluates alert rules every 30s                              │
│      │                                                          │
│      └──────▶ Alertmanager (when rule matches)                    │
│                  │                                              │
│                  └──────▶ Discord Webhook                     │
│                               │                                │
│                               ▼                                │
│  ┌───────────────────────────────────────────────────────────┐   │
│  │  Discord Notification                                     │   │
│  │  - Summary: Instance down                                │   │
│  │  - Severity: Critical                                    │   │
│  │  - Description: System X has been down for > 1m            │   │
│  └───────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Network Architecture

### Tailscale VPN

**Network**: `100.64.0.0/10`
**Purpose**: Secure private communication between hub and spokes

#### Hub Network
- **IP Address**: Assigned from Tailscale (e.g., `100.64.0.2`)
- **Services**:
  - Prometheus: `http://<hub-ip>:9090/api/v1/write`
  - Loki: `http://<hub-ip>:3100/loki/api/v1/push`
- **Security**:
  - NetworkPolicy restricts ingress to Tailscale IPs only
  - No additional authentication (ACLs as primary boundary)

#### Spoke Networks
- **IP Addresses**: Assigned from Tailscale (e.g., `100.64.0.10`, `100.64.0.11`)
- **Services**:
  - Alloy metrics endpoint: `http://<spoke-ip>:9090/metrics`
- **Security**:
  - Spokes only push data to hub
  - No ingress from hub required

#### ACL Configuration

```
{
  "tagOwners": {
    "tag:hub": ["user@example.com"],
    "tag:spoke": ["user@example.com"]
  },
  "acls": [
    {
      "action": "accept",
      "src": ["tag:spoke"],
      "dst": ["tag:hub:*"]
    }
  ]
}
```

---

## Security Model

### Primary Boundary: Tailscale ACLs

- All monitoring communication happens over Tailscale VPN
- ACLs control which devices can access hub services
- Spokes can push to hub, but cannot pull from each other

### Secondary Boundary: Kubernetes NetworkPolicies

**Hub NetworkPolicy**:
```yaml
spec:
  podSelector: {}
  policyTypes:
    - Ingress
  ingress:
    # Allow from monitoring namespace
    - from:
        - namespaceSelector:
            matchLabels:
              name: monitoring
    # Allow from Tailscale network (defense-in-depth)
    - from:
        - ipBlock:
            cidr: 100.64.0.0/10
      ports:
        - port: 9090  # Prometheus
        - port: 3100  # Loki
```

### No Additional Authentication

- Prometheus remote_write receiver: No auth (Tailscale ACLs only)
- Loki push API: No auth (Tailscale ACLs only)
- Grafana: Basic auth (admin/password) for UI access
- **Rationale**: Simplicity, Tailscale provides sufficient security

---

## Storage Architecture

### Prometheus Storage

**Storage Class**: `local-path-metrics` (k3s local storage)
**Size**: 30GB
**Retention**: 15 days (or 28GB, whichever comes first)
**Format**: TSDB (Time Series Database)
**Backup**: External system (handoff)

**Storage Math**:
```
Daily ingestion: ~1GB/day (estimated)
15 days = ~15GB
Headroom: ~15GB for compaction and spikes
Total: 30GB
```

### Loki Storage

**Storage Class**: `local-path-logs` (k3s local storage)
**Size**: 20GB
**Retention**: 15 days
**Format**: TSDB + Chunks
**Backup**: External system (handoff)
**Compaction**: Enabled (retention_delete_delay: 2h)

**Storage Math**:
```
Daily ingestion: ~500MB/day (estimated)
15 days = ~7.5GB
Index overhead: ~2-3x = ~15-22GB
Total: 20GB (compaction keeps it within bounds)
```

### Storage Summary

**Per Node (OCI Cluster)**:
- Monitoring stack: 50GB (30GB metrics + 20GB logs)
- System headroom: 14GB (64GB per node)
- **Status**: ✅ Fits comfortably

---

## Alert Strategy

### Alert Groups

#### System Alerts
- `InstanceDown`: System unreachable for >1m (Critical)
- `HighMemoryUsage`: Memory >85% for >5m (Warning)
- `HighCPUUsage`: CPU >80% for >5m (Warning)

#### Storage Alerts
- `LokiStorageFull`: Loki utilization >90% for >5m (Critical)
- `PVCAboveThreshold`: PVC >85% for >10m (Warning)

#### Connectivity Alerts
- `TailscaleConnectivityLost`: Alloy unreachable for >2m (Critical)

### Alert Routing

**Discord Channels**:
- `#monitoring`: All warnings and critical alerts
- `#monitoring-critical`: Critical alerts with @everyone ping

**Repeat Intervals**:
- Warnings: Every 4 hours
- Critical: Every 1 hour

---

## Scalability Considerations

### Hub Scalability

**Current Capacity**:
- Prometheus: ~2M series (estimated)
- Loki: ~500GB logs/day (estimated)
- Grafana: Unlimited (stateless, scales horizontally)

**Scaling Path**:
1. **Increase storage**: Expand PVCs (if supported) or add volumes
2. **Add replicas**: Deploy multiple Prometheus/Loki instances with sharding
3. **Upgrade to Mimir/Tempo**: For larger scale, migrate to cloud-native storage

### Spoke Scalability

**Per-Cluster Resource Usage**:
- Alloy: 512Mi - 1Gi RAM (depends on cluster size)
- Kube-state-metrics: 128Mi - 256Mi RAM
- **Total**: ~1Gi - 2Gi RAM per cluster

**Scaling Path**:
- More clusters: Deploy additional monitoring-agent instances
- Larger clusters: Increase resource limits in cluster-specific values

---

## Disaster Recovery

### Backup Strategy

**Manual** (external system handles):
- Prometheus TSDB: Tar + upload to backup location
- Loki data: Tar + upload to backup location
- Frequency: Daily or as needed

**Restore Procedure**:
1. Scale down component to 0
2. Delete PVC
3. Scale up component (new PVC created)
4. Restore data from backup
5. Restart component

### High Availability

**Current State**: Single-node hub (no HA)
**Future**: Add HA if required:
- Prometheus: Use Thanos or Cortex
- Loki: Deploy with replication factor >1
- Grafana: Deploy multiple instances with load balancer

---

## Monitoring Chart Structure

### Monitoring Hub Chart

```
charts/monitoring/
├── Chart.yaml
├── values.yaml
├── templates/
│   ├── prometheus/
│   ├── loki/
│   ├── grafana/
│   ├── alertmanager/
│   ├── alloy/
│   ├── kube-state-metrics/
│   ├── networkpolicy.yaml
│   ├── storageclass-*.yaml
│   ├── 1password-secret.yaml
│   └── _helpers.tpl
```

### Monitoring Agent Chart

```
charts/monitoring-agent/
├── Chart.yaml (with dependencies)
├── values.yaml (base)
├── values-stages/
│   ├── production.yaml
│   ├── staging.yaml
│   └── development.yaml
├── values-clusters/
│   ├── homelab-k8s.yaml
│   └── euw1-production.yaml
├── templates/
│   └── 1password-secret.yaml
└── charts/ (dependencies)
    ├── alloy-*.tgz
    └── kube-state-metrics-*.tgz
```

---

## Deployment Workflow

### Hub Deployment

1. **Create 1Password items**
   - `monitoring-hub`: grafana_admin_password, Discord webhooks

2. **Deploy ArgoCD application**
   ```bash
   kubectl apply -f argo-apps/monitoring.yaml
   ```

3. **Verify deployment**
   ```bash
   kubectl get pods -n monitoring
   kubectl port-forward svc/grafana 3000:3000 -n monitoring
   ```

### Spoke Deployment

1. **Choose deployment pattern**:
   - Base + Stage + Cluster file
   - Base + Stage + Inline values

2. **Configure values**:
   ```yaml
   global:
     clusterName: "my-cluster"
     hubEndpoint: "100.64.0.2"
   ```

3. **Deploy ArgoCD application**
   ```bash
   kubectl apply -f argo-apps/monitoring-agent-my-cluster.yaml
   ```

4. **Verify connectivity**
   ```bash
   curl 'http://prometheus.monitoring.svc:9090/api/v1/query?query=up{cluster="my-cluster"}'
   ```

---

## Technology Choices

### Why Grafana Alloy?

**Before**: Node Exporter + Promtail + Prometheus Agent (3 components)
**After**: Grafana Alloy (1 component)

**Benefits**:
- Unified collector for metrics + logs
- Native Kubernetes integration
- Single binary to maintain
- Declarative River configuration
- Native NixOS support

### Why Push Model?

**Before**: Hub scrapes spokes over Tailscale (pull)
**After**: Spokes push to hub over Tailscale

**Benefits**:
- Easier to traverse NAT/firewalls
- Spokes buffer data during network issues
- Simpler RBAC (spokes only need write access to hub)
- Better resilience

### Why Tailscale for Security?

**Before**: Basic auth + TLS on all endpoints
**After**: Tailscale ACLs as primary boundary

**Benefits**:
- Simplified authentication (no password management)
- Strong security (mTLS, key rotation)
- Easier to add/remove systems
- Defense-in-depth with NetworkPolicies

---

## Related Documentation

- [Monitoring Runbook](./monitoring-runbook.md)
- [Alert Rules Reference](./monitoring-alert-rules.md)
- [Resource Usage Guide](./monitoring-resources.md)
- [Troubleshooting Guide](./monitoring-troubleshooting.md)
- [Deployment Guide](./monitoring-deployment.md)

---

## Change Log

| Date | Version | Changes |
|-------|---------|---------|
| 2026-02-21 | 1.0 | Initial architecture documentation |
