# Monitoring Alert Rules Reference

**Version**: 1.0
**Last Updated**: 2026-02-21
**Purpose**: Complete reference for all alert rules in the monitoring system

---

## Table of Contents

- [Alert Rule Groups](#alert-rule-groups)
- [Alert Definitions](#alert-definitions)
- [Managing Alert Rules](#managing-alert-rules)
- [Testing Alert Rules](#testing-alert-rules)
- [Customizing Alert Rules](#customizing-alert-rules)

---

## Alert Rule Groups

Alerts are organized into three groups for logical grouping and routing:

### 1. System Alerts
**File**: `charts/monitoring/templates/prometheus/alerts.yaml`
**Group Name**: `system-alerts`
**Focus**: System health and resource utilization

### 2. Storage Alerts
**File**: `charts/monitoring/templates/prometheus/alerts.yaml`
**Group Name**: `storage-alerts`
**Focus**: Storage capacity and health

### 3. Connectivity Alerts
**File**: `charts/monitoring/templates/prometheus/alerts.yaml`
**Group Name**: `connectivity-alerts`
**Focus**: Network and system connectivity

---

## Alert Definitions

### System Alerts

#### InstanceDown

**Severity**: Critical
**Condition**: `up == 0` for 1 minute

**Expression**:
```promql
up == 0
```

**For Duration**: 1 minute

**Labels**:
- `severity: critical`
- Inherits from metric: `job`, `instance`, `cluster`, `environment`

**Annotations**:
- `summary`: "Instance {{ "{{" }}$labels.instance{{ " }}" }} down"
- `description`: "{{ "{{" }}$labels.instance{{ " }}" }} has been down for more than 1 minute"

**When This Fires**:
- A system (cluster or node) stops reporting metrics to Prometheus
- Common causes:
  - System crashed or powered off
  - Tailscale disconnected
  - Alloy/prometheus crashed
  - Network partition

**Impact**:
- Loss of visibility into the affected system
- Potential application or service outage

**Resolution**:
1. Identify affected system from alert label `instance`
2. Check system connectivity (ping, Tailscale status)
3. Check component logs (Alloy, Prometheus)
4. Restart affected components if needed
5. Verify system comes back up

**Related Metrics**:
- `up{job="alloy"}` - Alloy process status
- `up{job="prometheus"}` - Prometheus process status

---

#### HighMemoryUsage

**Severity**: Warning
**Condition**: Memory usage > 85% for 5 minutes

**Expression**:
```promql
(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 85
```

**For Duration**: 5 minutes

**Labels**:
- `severity: warning`
- Inherits: `instance`, `cluster`, `environment`

**Annotations**:
- `summary`: "High memory usage on {{ "{{" }}$labels.instance{{ " }}" }}"
- `description`: "Memory usage is above 85% for 5 minutes"

**When This Fires**:
- System has been using >85% of RAM for 5+ minutes
- Common causes:
  - Memory leak in application
  - Insufficient memory for workload
  - High memory usage by specific service
  - Too many applications running

**Impact**:
- System may start swapping (degraded performance)
- Applications may crash due to OOM
- New applications may fail to start

**Resolution**:
1. Identify memory-hungry processes:
   - K8s: `kubectl top pods -A --sort-by=memory`
   - NixOS: `ps aux --sort=-%mem | head -10`
2. Scale up resources if needed
3. Kill or restart memory-hog processes
4. Investigate for memory leaks
5. Consider memory increase or workload redistribution

**Related Metrics**:
- `node_memory_MemAvailable_bytes` - Available memory
- `node_memory_MemTotal_bytes` - Total memory
- `container_memory_working_set_bytes` - Container memory usage

---

#### HighCPUUsage

**Severity**: Warning
**Condition**: CPU usage > 80% for 5 minutes

**Expression**:
```promql
100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
```

**For Duration**: 5 minutes

**Labels**:
- `severity: warning`
- Inherits: `instance`, `cluster`, `environment`

**Annotations**:
- `summary`: "High CPU usage on {{ "{{" }}$labels.instance{{ " }}" }}"
- `description`: "CPU usage is above 80% for 5 minutes"

**When This Fires**:
- System CPU has been >80% utilized for 5+ minutes
- Common causes:
  - CPU-intensive workload
  - Infinite loop in application
  - Insufficient CPU for workload
  - High number of processes

**Impact**:
- System performance degradation
- Applications may slow down
- Request latency increases

**Resolution**:
1. Identify CPU-hungry processes:
   - K8s: `kubectl top pods -A --sort-by=cpu`
   - NixOS: `ps aux --sort=-%cpu | head -10`
2. Scale up CPU resources if needed
3. Investigate application code for inefficiencies
4. Horizontal Pod Autoscaler may help (for K8s)
5. Consider CPU increase or workload redistribution

**Related Metrics**:
- `node_cpu_seconds_total{mode="idle"}` - Idle CPU time
- `container_cpu_usage_seconds_total` - Container CPU usage
- `rate(process_cpu_seconds_total[5m])` - Process CPU rate

---

### Storage Alerts

#### LokiStorageFull

**Severity**: Critical
**Condition**: Loki chunk utilization > 90% for 5 minutes

**Expression**:
```promql
loki_ingester_chunk_utilization > 0.9
```

**For Duration**: 5 minutes

**Labels**:
- `severity: critical`
- Inherits: `instance`, `cluster`, `environment`

**Annotations**:
- `summary`: "Loki storage nearly full"
- `description`: "Loki storage on {{ "{{" }}$labels.instance{{ " }}" }} is approaching capacity"

**When This Fires**:
- Loki is using >90% of configured storage
- Common causes:
  - High log volume (log spam)
  - Too long retention
  - Insufficient storage allocation
  - Compaction not freeing space

**Impact**:
- Loki may start rejecting new logs
- Loss of log visibility
- Potential service disruption

**Resolution**:
1. Check Loki storage: `kubectl exec -n monitoring loki-0 -- df -h /loki`
2. Identify high-volume log sources: `logcli query '{job=~".+"}' --stats --from=7d`
3. Reduce retention (emergency): Edit `retention_period` in Loki config
4. Exclude high-volume logs: Add relabeling rules in Alloy
5. Increase PVC size: Edit storage size in values
6. Run manual compaction: `kubectl exec -n monitoring loki-0 -- wget -O- localhost:3100/compactor/run`

**Related Metrics**:
- `loki_ingester_chunk_utilization` - Loki storage utilization
- `loki_ingester_chunk_sizes` - Chunk size distribution

---

#### PVCAboveThreshold

**Severity**: Warning
**Condition**: PVC usage > 85% for 10 minutes

**Expression**:
```promql
(kubelet_volume_stats_capacity_bytes - kubelet_volume_stats_available_bytes) / kubelet_volume_stats_capacity_bytes > 0.85
```

**For Duration**: 10 minutes

**Labels**:
- `severity: warning`
- Inherits: `persistentvolumeclaim`, `namespace`, `pod`, `cluster`, `environment`

**Annotations**:
- `summary`: "PVC usage above 85%"
- `description**: "PVC {{ "{{" }}$labels.persistentvolumeclaim{{ " }}" }} is above 85% full"

**When This Fires**:
- A PVC is using >85% of its allocated capacity
- Common causes:
  - Log files growing unbounded
  - Large files created
  - Database data growth
  - Insufficient PVC size

**Impact**:
- Application may crash when PVC is full
- New data cannot be written
- Service disruption

**Resolution**:
1. Identify affected PVC from alert label `persistentvolumeclaim`
2. Find pods using the PVC: `kubectl get pods -n <namespace> -o json | jq`
3. Check what's using space: `kubectl exec <pod> -- du -sh /path/to/pvc`
4. Clean up old files: `kubectl exec <pod> -- rm /path/to/pvc/*.old`
5. Configure log rotation: Add `logrotate` to application
6. Increase PVC size: Edit size in chart values (if supported)

**Related Metrics**:
- `kubelet_volume_stats_capacity_bytes` - Total PVC capacity
- `kubelet_volume_stats_available_bytes` - Available space
- `kubelet_volume_stats_used_bytes` - Used space

---

### Connectivity Alerts

#### TailscaleConnectivityLost

**Severity**: Critical
**Condition**: Alloy up == 0 for 2 minutes

**Expression**:
```promql
up{job="alloy"} == 0
```

**For Duration**: 2 minutes

**Labels**:
- `severity: critical`
- Inherits: `instance`, `cluster`, `environment`

**Annotations**:
- `summary`: "Tailscale connectivity lost"
- `description`: "Alloy on {{ "{{" }}$labels.instance{{ " }}" }} cannot reach monitoring hub via Tailscale"

**When This Fires**:
- Alloy cannot reach hub Prometheus/Loki via Tailscale
- Common causes:
  - Tailscale disconnected or crashed
  - Hub Tailscale IP changed
  - Network partition
  - ACLs blocking access
  - Hub components crashed

**Impact**:
- Loss of metrics and logs from affected system
- No visibility into system health
- Potential undetected service issues

**Resolution**:
1. Check Tailscale status on affected system
2. Test network connectivity: `ping <hub-tailscale-ip>`
3. Check Tailscale logs: `journalctl -u tailscaled`
4. Restart Tailscale: `systemctl restart tailscaled`
5. Verify ACLs: `tailscale acl show`
6. Check hub components are running: `kubectl get pods -n monitoring`

**Related Metrics**:
- `up{job="alloy"}` - Alloy process status
- `alloy_remote_write_send_bytes_total` - Data sent to hub
- `alloy_loki_send_bytes_total` - Logs sent to hub

---

## Managing Alert Rules

### Viewing Alert Rules

**Via Prometheus UI**:
1. Open Prometheus: `http://prometheus.monitoring.svc:9090`
2. Navigate to Status → Rules
3. View all loaded rules and their states

**Via API**:
```bash
# Get all rules
curl http://prometheus.monitoring.svc:9090/api/v1/rules

# Get active alerts
curl http://prometheus.monitoring.svc:9090/api/v1/alerts
```

### Reloading Alert Rules

**Manual Reload**:
```bash
# Trigger Prometheus config reload
curl -X POST http://prometheus.monitoring.svc:9090/-/reload

# Verify rules loaded
curl http://prometheus.monitoring.svc:9090/api/v1/rules
```

**Automatic Reload**:
- Prometheus watches the ConfigMap and reloads automatically when changed
- No manual action required when updating ConfigMap

### Updating Alert Rules

1. **Edit the alert rules file**:
   ```bash
   vim charts/monitoring/templates/prometheus/alerts.yaml
   ```

2. **Make your changes**:
   - Add new alert rules
   - Modify existing rules
   - Adjust thresholds or durations

3. **Apply changes**:
   ```bash
   # Via ArgoCD (auto-sync)
   # ArgoCD will detect the change and sync

   # Or manual apply
   kubectl apply -f charts/monitoring/templates/prometheus/alerts.yaml

   # Or chart upgrade
   helm upgrade monitoring ./charts/monitoring -n monitoring
   ```

4. **Verify**:
   ```bash
   # Check rules loaded
   curl http://prometheus.monitoring.svc:9090/api/v1/rules
   ```

---

## Testing Alert Rules

### Testing Alert Expression

**Test in Prometheus UI**:
1. Open Prometheus: `http://prometheus.monitoring.svc:9090`
2. Go to Graph tab
3. Enter the alert expression
4. Check if it evaluates to true/false

**Test via API**:
```bash
# Test expression
curl 'http://prometheus.monitoring.svc:9090/api/v1/query?query=up==0'

# Test with time range
curl 'http://prometheus.monitoring.svc:9090/api/v1/query_range?query=up==0&start=1708560000&end=1708563600&step=60'
```

### Forcing an Alert

**To test alerting, you can force a condition**:

**Example: Force InstanceDown alert**
```bash
# Stop Alloy on a node
kubectl delete pod -n monitoring <alloy-pod>

# Wait 1 minute
# Alert should fire

# Restart Alloy
kubectl scale daemonset/alloy --replicas=<expected> -n monitoring
```

**Example: Force HighMemoryUsage alert**
```bash
# Allocate memory on a node
kubectl run stress-mem --image=polinux/stress \
  --rm -it --restart=Never \
  -- stress-ng --vm 1 --vm-bytes 1024M --timeout 600s

# Wait 5 minutes
# Alert should fire

# Cleanup
kubectl delete pod stress-mem
```

**Example: Force HighCPUUsage alert**
```bash
# Allocate CPU on a node
kubectl run stress-cpu --image=polinux/stress \
  --rm -it --restart=Never \
  -- stress-ng --cpu 4 --timeout 600s

# Wait 5 minutes
# Alert should fire

# Cleanup
kubectl delete pod stress-cpu
```

---

## Customizing Alert Rules

### Adding New Alert Rules

**Step 1**: Add rule to appropriate group
```yaml
# In charts/monitoring/templates/prometheus/alerts.yaml
groups:
  - name: custom-alerts
    rules:
      - alert: CustomAlertName
        expr: <expression>
        for: <duration>
        labels:
          severity: <severity>
          custom_label: <value>
        annotations:
          summary: "<summary>"
          description: "<description>"
```

**Step 2**: Choose severity level
- `critical`: Immediate action required
- `warning`: Investigate soon
- `info`: Informational

**Step 3**: Apply changes
```bash
kubectl apply -f charts/monitoring/templates/prometheus/alerts.yaml
```

### Example Custom Alerts

#### High Disk Usage
```yaml
- alert: HighDiskUsage
  expr: (node_filesystem_size_bytes - node_filesystem_avail_bytes) / node_filesystem_size_bytes * 100 > 90
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "High disk usage on {{ "{{" }}$labels.instance{{ " }}" }}"
    description: "Disk usage is above 90% for 10 minutes"
```

#### High Error Rate
```yaml
- alert: HighErrorRate
  expr: rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]) > 0.1
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "High error rate on {{ "{{" }}$labels.instance{{ " }}" }}"
    description: "Error rate is above 10% for 5 minutes"
```

#### Pod CrashLooping
```yaml
- alert: PodCrashLooping
  expr: rate(kube_pod_container_status_restarts_total[5m]) > 0
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Pod {{ "{{" }}$labels.pod{{ " }}" }} is crash looping"
    description: "Pod has restarted more than 0 times in 5 minutes"
```

---

## Best Practices

### Alert Thresholds

- **Don't alert too early**: Use `for` duration to avoid alert flapping
- **Don't alert too late**: Balance between detection speed and noise
- **Use percentiles**: Consider `p95`, `p99` for better alerts

### Alert Labels

- **Use descriptive labels**: Make it easy to identify the affected system
- **Cluster label**: Always include `cluster` label for multi-cluster setups
- **Severity label**: Always include `severity` for routing

### Alert Annotations

- **Summary**: Short, human-readable description
- **Description**: Longer explanation with context
- **Runbook**: Link to runbook for resolution steps
- **Impact**: What happens if this alert fires

### Alert Groups

- **Logical grouping**: Group related alerts together
- **Group names**: Use clear, descriptive names
- **Evaluation interval**: Differentiate evaluation intervals by group

---

## Related Documentation

- [Monitoring Runbook](./monitoring-runbook.md)
- [Monitoring Architecture](./monitoring-architecture.md)
- [Resource Usage Guide](./monitoring-resources.md)
- [Troubleshooting Guide](./monitoring-troubleshooting.md)

---

## Change Log

| Date | Version | Changes |
|-------|---------|---------|
| 2026-02-21 | 1.0 | Initial alert rules reference |
