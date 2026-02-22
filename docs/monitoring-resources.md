# Monitoring Resource Usage Guide

**Version**: 1.0
**Last Updated**: 2026-02-21
**Purpose**: Calculate, monitor, and optimize monitoring system resources

---

## Table of Contents

- [Resource Calculations](#resource-calculations)
- [Hub Resources](#hub-resources)
- [Spoke Resources](#spoke-resources)
- [Monitoring Resource Usage](#monitoring-resource-usage)
- [Optimization Strategies](#optimization-strategies)
- [Scaling Guidelines](#scaling-guidelines)

---

## Resource Calculations

### Hub Resources (OCI Cluster)

| Component | CPU (Req/Lim) | Memory (Req/Lim) | Storage |
|-----------|----------------|------------------|---------|
| Prometheus | 1000m / 2000m | 4Gi / 8Gi | 30Gi |
| Loki | 500m / 1000m | 2Gi / 4Gi | 20Gi |
| Grafana | 100m / 200m | 256Mi / 512Mi | 0Gi |
| Alertmanager | 100m / 200m | 256Mi / 512Mi | 0Gi |
| Alloy (OCI) | 100m / 200m | 128Mi / 256Mi | 0Gi |
| Kube-state-metrics | 100m / 200m | 128Mi / 256Mi | 0Gi |
| **Total** | **1.9K / 3.8K** | **~7Gi / ~14Gi** | **50Gi** |

**Per Node (OCI k3s)**:
- Assuming 3 nodes: ~1.3Gi / 2.7Gi CPU, ~2.4Gi / 4.7Gi RAM per node
- Storage: Distributed across nodes (not per-node)

**Node Requirements**:
- **Minimum**: 3 nodes with 4GB RAM each
- **Recommended**: 3 nodes with 8GB RAM each
- **Storage**: 64GB per node (k3s local-path)

---

### Spoke Resources (K8s Clusters)

| Component | CPU (Req/Lim) | Memory (Req/Lim) | Scale |
|-----------|----------------|------------------|-------|
| Grafana Alloy | 250m / 500m | 512Mi / 1Gi | DaemonSet (per node) |
| Kube-state-metrics | 100m / 200m | 128Mi / 256Mi | Deployment (1 replica) |
| **Per Node** | **350m / 700m** | **~640Mi / ~1.3Gi** | - |

**Example Spoke Clusters**:

| Cluster | Nodes | CPU (Req/Lim) | Memory (Req/Lim) |
|---------|--------|----------------|------------------|
| Homelab K8s (3 nodes) | 3 | 1.05K / 2.1K | 1.9Gi / 3.9Gi |
| Staging (1 node) | 1 | 350m / 700m | 640Mi / 1.3Gi |
| Development (1 node) | 1 | 350m / 700m | 640Mi / 1.3Gi |

---

### Spoke Resources (NixOS VMs)

| Component | CPU | Memory |
|-----------|-----|--------|
| Grafana Alloy | 100m / 200m | 128Mi / 256Mi |
| **Per VM** | **100m / 200m** | **128Mi / 256Mi** |

**Note**: NixOS Alloy configured via NixOS service, typically with lower resources than K8s DaemonSet.

---

## Hub Resources

### Prometheus

**Current Configuration**:
```yaml
prometheus:
  resources:
    requests:
      memory: "4Gi"
      cpu: "1000m"
    limits:
      memory: "8Gi"
      cpu: "2000m"
  retention:
    time: "15d"
    size: "28GB"
  scrapeInterval: "30s"
```

**Resource Usage Factors**:
- **Metrics ingested**: ~1M series
- **Scrape targets**: ~100 targets
- **Evaluation frequency**: Every 30s
- **Query load**: Depends on dashboard/alert usage

**Estimated Usage**:
- **Normal**: 4-5Gi RAM, 500-800m CPU
- **High**: 6-7Gi RAM, 1200-1500m CPU (during heavy querying)
- **Peak**: 8Gi RAM, 2000m CPU (during compaction)

**Storage Growth**:
- **Daily ingestion**: ~1GB/day
- **15-day retention**: ~15GB
- **Compaction overhead**: ~2x = ~30GB total

---

### Loki

**Current Configuration**:
```yaml
loki:
  resources:
    requests:
      memory: "2Gi"
      cpu: "500m"
    limits:
      memory: "4Gi"
      cpu: "1000m"
  retention:
    period: "15d"
  storage:
    size: "20Gi"
```

**Resource Usage Factors**:
- **Log lines ingested**: ~10M lines/day
- **Log volume**: ~500MB/day
- **Index overhead**: ~2-3x
- **Compaction frequency**: Every 2h

**Estimated Usage**:
- **Normal**: 2-2.5Gi RAM, 300-500m CPU
- **High**: 3-3.5Gi RAM, 700-900m CPU (during compaction)
- **Peak**: 4Gi RAM, 1000m CPU (during heavy query)

**Storage Growth**:
- **Daily logs**: ~500MB/day
- **15-day retention**: ~7.5GB
- **Index overhead**: ~2-3x = ~15-22GB total
- **Compaction**: Keeps usage within 20GB

---

### Grafana

**Current Configuration**:
```yaml
grafana:
  resources:
    requests:
      memory: "256Mi"
      cpu: "100m"
    limits:
      memory: "512Mi"
      cpu: "200m"
```

**Resource Usage Factors**:
- **Dashboard count**: 10-20 dashboards
- **Query frequency**: Depends on refresh interval
- **Concurrent users**: 1-5 users

**Estimated Usage**:
- **Normal**: 200-300Mi RAM, 50-80m CPU
- **High**: 350-400Mi RAM, 100-150m CPU (complex dashboards)
- **Peak**: 512Mi RAM, 200m CPU (data-intensive queries)

**Note**: Grafana is stateless, scales well with concurrent users.

---

### Alertmanager

**Current Configuration**:
```yaml
alertmanager:
  resources:
    requests:
      memory: "256Mi"
      cpu: "100m"
    limits:
      memory: "512Mi"
      cpu: "200m"
```

**Resource Usage Factors**:
- **Alert rate**: ~10 alerts/day (normal)
- **Notification rate**: Depends on alert routing
- **Silence count**: Depends on maintenance windows

**Estimated Usage**:
- **Normal**: 150-200Mi RAM, 20-50m CPU
- **High**: 250-300Mi RAM, 80-120m CPU (during alert storms)
- **Peak**: 512Mi RAM, 200m CPU (rare)

---

## Spoke Resources

### Grafana Alloy (K8s)

**Production Configuration**:
```yaml
alloy:
  resources:
    requests:
      memory: "512Mi"
      cpu: "250m"
    limits:
      memory: "1Gi"
      cpu: "500m"
```

**Staging Configuration**:
```yaml
alloy:
  resources:
    requests:
      memory: "256Mi"
      cpu: "150m"
    limits:
      memory: "512Mi"
      cpu: "300m"
```

**Development Configuration**:
```yaml
alloy:
  resources:
    requests:
      memory: "128Mi"
      cpu: "100m"
    limits:
      memory: "256Mi"
      cpu: "200m"
```

**Resource Usage Factors**:
- **Log volume**: Depends on workload
- **Metrics scraped**: Depends on exporters
- **Network I/O**: Pushing to hub via Tailscale

**Estimated Usage**:
- **Normal**: 512Mi RAM, 150-200m CPU (production)
- **High**: 768Mi RAM, 300-400m CPU (high log volume)
- **Peak**: 1Gi RAM, 500m CPU (log spike)

---

### Kube-state-metrics

**Production Configuration**:
```yaml
kube-state-metrics:
  resources:
    requests:
      memory: "128Mi"
      cpu: "100m"
    limits:
      memory: "256Mi"
      cpu: "200m"
```

**Staging Configuration**:
```yaml
kube-state-metrics:
  resources:
    requests:
      memory: "64Mi"
      cpu: "50m"
    limits:
      memory: "128Mi"
      cpu: "100m"
```

**Development Configuration**:
```yaml
kube-state-metrics:
  resources:
    requests:
      memory: "32Mi"
      cpu: "25m"
    limits:
      memory: "64Mi"
      cpu: "50m"
```

**Resource Usage Factors**:
- **K8s API objects**: Depends on cluster size
- **Collection frequency**: Every 30s
- **Metrics count**: ~2000 metrics per cluster

**Estimated Usage**:
- **Normal**: 128Mi RAM, 50-80m CPU
- **High**: 180-200Mi RAM, 100-150m CPU (large cluster)
- **Peak**: 256Mi RAM, 200m CPU (very large cluster)

---

## Monitoring Resource Usage

### Prometheus Queries

#### CPU Usage by Component

```promql
# Prometheus CPU
rate(process_cpu_seconds_total{job="prometheus"}[5m]) * 100

# Loki CPU
rate(process_cpu_seconds_total{job="loki"}[5m]) * 100

# Grafana CPU
rate(process_cpu_seconds_total{job="grafana"}[5m]) * 100

# Alloy CPU by cluster
rate(process_cpu_seconds_total{job="alloy"}[5m]) * 100
```

#### Memory Usage by Component

```promql
# Prometheus memory
process_resident_memory_bytes{job="prometheus"} / 1024 / 1024 / 1024

# Loki memory
process_resident_memory_bytes{job="loki"} / 1024 / 1024 / 1024

# Grafana memory
process_resident_memory_bytes{job="grafana"} / 1024 / 1024 / 1024

# Alloy memory by cluster
process_resident_memory_bytes{job="alloy"} / 1024 / 1024 / 1024
```

#### Storage Usage

```promql
# Prometheus TSDB size
prometheus_tsdb_storage_blocks_bytes / 1024 / 1024 / 1024

# Loki chunk utilization
loki_ingester_chunk_utilization

# PVC usage by namespace
(kubelet_volume_stats_capacity_bytes - kubelet_volume_stats_available_bytes) / kubelet_volume_stats_capacity_bytes * 100
```

#### Network I/O

```promql
# Bytes sent to hub
rate(alloy_remote_write_send_bytes_total[5m])

# Bytes received by hub
rate(prometheus_remote_storage_samples_total[5m])
```

### Kubernetes Metrics

#### Pod Resource Usage

```bash
# CPU usage
kubectl top pods -A --sort-by=cpu

# Memory usage
kubectl top pods -A --sort-by=memory
```

#### Node Resource Usage

```bash
# All nodes
kubectl top nodes

# Specific node
kubectl describe node <node-name>
```

#### PVC Usage

```bash
# All PVCs
kubectl get pvc -A

# Detailed usage
kubectl exec -n <namespace> <pod-name> -- df -h /path/to/pvc
```

---

## Optimization Strategies

### Prometheus Optimization

#### Reduce Retention

**Impact**: Significantly reduces memory and storage usage

**Configuration**:
```yaml
prometheus:
  retention:
    time: "7d"  # Reduce from 15d
    size: "15GB"  # Reduce from 28GB
```

**Trade-off**: Less historical data available

---

#### Reduce Scrape Interval

**Impact**: Reduces CPU and memory usage

**Configuration**:
```yaml
prometheus:
  scrapeInterval: "60s"  # Increase from 30s
```

**Trade-off**: Less granular metrics, longer detection time

---

#### Filter Metrics

**Impact**: Reduces series count and memory usage

**Method**: Add relabeling rules to drop unwanted metrics

```yaml
# In Prometheus scrape config
scrape_configs:
  - job_name: 'kubernetes-pods'
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__address__]
        regex: '(.+):10250'
        action: drop  # Drop cAdvisor
```

**Trade-off**: Loss of visibility into dropped metrics

---

### Loki Optimization

#### Reduce Retention

**Impact**: Significantly reduces storage usage

**Configuration**:
```yaml
loki:
  retention:
    period: "7d"  # Reduce from 15d
```

**Trade-off**: Less historical logs available

---

#### Drop High-Volume Logs

**Impact**: Reduces storage and CPU usage

**Method**: Add relabeling rules in Alloy

```river
loki.source.kubernetes "pods" {
  relabel_rules = '''
    drop_log_line {
      drop_label_value "container", "nginx-ingress-controller"
      drop_label_value "pod", "high-volume-app"
    }
  '''
  forward_to = [loki.write.hub.receiver]
}
```

**Trade-off**: Loss of visibility into dropped logs

---

#### Increase Compaction Frequency

**Impact**: More efficient storage usage

**Configuration**:
```yaml
loki:
  compactor:
    retention_delete_delay: "1h"  # Reduce from 2h
```

**Trade-off**: Higher CPU usage during compaction

---

### Grafana Optimization

#### Increase Query Cache

**Impact**: Reduces CPU usage for repeated queries

**Configuration**:
```yaml
grafana:
  configMap:
    content: |-
      [caching]
      enabled = true
      ttl = "5m"
```

**Trade-off**: Stale data during cache period

---

#### Reduce Dashboard Refresh Interval

**Impact**: Reduces CPU and memory usage

**Method**: Set dashboard refresh to 60s or more

**Trade-off**: Less real-time data

---

#### Disable Unused Plugins

**Impact**: Reduces memory usage

**Method**: Remove unused plugins from Grafana

**Trade-off**: Loss of plugin functionality

---

## Scaling Guidelines

### When to Scale Up

**Prometheus**:
- Memory usage consistently >80%
- Query response time >10s
- Series count >2M
- **Action**: Increase memory limit, add replicas with sharding

**Loki**:
- Memory usage consistently >80%
- Query response time >10s
- Storage utilization >85%
- **Action**: Increase memory limit, expand PVC

**Grafana**:
- CPU usage consistently >80%
- Dashboard load time >10s
- Concurrent users >10
- **Action**: Increase CPU/memory, add replicas

**Alloy**:
- Logs not being pushed (backpressure)
- Metrics lagging >5min
- **Action**: Increase CPU/memory

### When to Scale Down

**General Rules**:
- Average resource usage <20%
- No performance issues
- **Action**: Reduce resource limits to save costs

**Caution**:
- Leave buffer for spikes
- Monitor for 1-2 weeks after scaling down
- Be prepared to scale back up if needed

---

## Cost Optimization

### Resource Right-Sizing

**Step 1**: Monitor for 1-2 weeks
**Step 2**: Analyze usage patterns
**Step 3**: Adjust limits to 95th percentile
**Step 4**: Set requests to 50th percentile

**Example**:
```yaml
# Initial (oversized)
alloy:
  resources:
    requests:
      memory: "1Gi"
    limits:
      memory: "2Gi"

# After right-sizing
alloy:
  resources:
    requests:
      memory: "256Mi"  # Based on 50th percentile
    limits:
      memory: "512Mi"  # Based on 95th percentile
```

---

### Spot Instances

**Use spot instances for non-critical workloads**:
- Grafana: Can use spot (stateless)
- Alloy: Not recommended (spoke system)
- Prometheus: Not recommended (data loss risk)
- Loki: Not recommended (data loss risk)

---

### Consolidation

**Run multiple monitoring stacks on one cluster**:
- Only if isolation is not required
- Use namespaces for separation
- **Benefit**: Reduce infrastructure costs

---

## Related Documentation

- [Monitoring Runbook](./monitoring-runbook.md)
- [Monitoring Architecture](./monitoring-architecture.md)
- [Alert Rules Reference](./monitoring-alert-rules.md)
- [Troubleshooting Guide](./monitoring-troubleshooting.md)

---

## Change Log

| Date | Version | Changes |
|-------|---------|---------|
| 2026-02-21 | 1.0 | Initial resource usage guide |
