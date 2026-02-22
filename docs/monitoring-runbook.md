# Monitoring Runbook

**Purpose**: Operational procedures for common monitoring issues
**Last Updated**: 2026-02-21
**Version**: 1.0

---

## Table of Contents

- [Critical Incidents](#critical-incidents)
- [Alert Management](#alert-management)
- [Component Troubleshooting](#component-troubleshooting)
- [Maintenance Procedures](#maintenance-procedures)
- [Recovery Procedures](#recovery-procedures)

---

## Critical Incidents

### Incident: InstanceDown Alert

**Severity**: Critical
**Alert**: `InstanceDown`
**Condition**: `up == 0` for 1 minute

#### Immediate Actions

1. **Identify affected system**
   ```bash
   # From hub Prometheus
   curl 'http://prometheus.monitoring.svc:9090/api/v1/query?query=up{alertname="InstanceDown"}'

   # Get instance label from alert
   # Format: cluster="xxx", instance="yyy"
   ```

2. **Check system connectivity**
   ```bash
   # If instance is a cluster, check ArgoCD
   kubectl get clusters -n argocd

   # If instance is NixOS system, check Tailscale
   tailscale status

   # Ping the target system
   ping <system-tailscale-ip>
   ```

3. **Check component logs**
   ```bash
   # For Kubernetes clusters
   kubectl logs -n monitoring -l app.kubernetes.io/name=alloy --tail=100

   # For NixOS systems
   journalctl -u alloy -n 100
   ```

#### Resolution Paths

**Path A: Tailscale Disconnected**
```bash
# Restart Tailscale on affected system
# Kubernetes: Check DaemonSet
kubectl rollout restart daemonset/alloy -n monitoring

# NixOS:
sudo systemctl restart tailscaled
```

**Path B: Component Crash Looping**
```bash
# Check pod status
kubectl describe pod <pod-name> -n monitoring

# Common causes:
# - OOMKilled: Increase memory limits
# - CrashLoopBackOff: Check logs for errors
# - ImagePullBackOff: Check image repository access
```

**Path C: Resource Exhaustion**
```bash
# Check node resources
kubectl top nodes

# Check pod resource usage
kubectl top pods -n monitoring
```

#### Verification

```bash
# Verify system is back up
curl 'http://prometheus.monitoring.svc:9090/api/v1/query?query=up{instance="<system>"}'

# Expected: {"status":"success","data":{"resultType":"vector","result":[{"metric":{"..."},"value":[timestamp,"1"]}]}}
```

---

### Incident: High Memory Usage

**Severity**: Warning
**Alert**: `HighMemoryUsage`
**Condition**: Memory usage > 85% for 5 minutes

#### Immediate Actions

1. **Identify affected system**
   ```bash
   curl 'http://prometheus.monitoring.svc:9090/api/v1/query?query=node_memory_MemAvailable_bytes/ node_memory_MemTotal_bytes'
   ```

2. **Check memory-hungry processes**
   ```bash
   # For K8s cluster
   kubectl top pods -A --sort-by=memory

   # For NixOS
   ps aux --sort=-%mem | head -10
   ```

3. **Check for memory leaks**
   ```bash
   # Look for containers with increasing memory usage
   # Query: rate(container_memory_working_set_bytes[5m])
   curl 'http://prometheus.monitoring.svc:9090/api/v1/query?query=rate(container_memory_working_set_bytes[5m])'
   ```

#### Resolution Paths

**Path A: Scale Up Resources**
```bash
# For K8s deployments
kubectl scale deployment <name> --replicas=<higher> -n <namespace>

# For monitoring agent
# Edit values-clusters/<cluster>.yaml
alloy:
  resources:
    limits:
      memory: "2Gi"  # Increase from 1Gi
```

**Path B: Identify and Kill Hog Processes**
```bash
# On NixOS
systemctl stop <memory-hog-service>

# On K8s
kubectl delete pod <memory-hog-pod> -n <namespace>
# Let it restart and hopefully use less memory
```

**Path C: Add Monitoring Exclusions**
```bash
# Exclude memory-intensive workloads from alerts if they're expected
# Edit Prometheus alert rules
# Add: unless: workload="expected-memory-hog"
```

#### Verification

```bash
# Wait 10-15 minutes, then verify memory usage
curl 'http://prometheus.monitoring.svc:9090/api/v1/query?query=(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100'

# Should be below 85%
```

---

### Incident: High CPU Usage

**Severity**: Warning
**Alert**: `HighCPUUsage`
**Condition**: CPU usage > 80% for 5 minutes

#### Immediate Actions

1. **Identify affected system**
   ```bash
   curl 'http://prometheus.monitoring.svc:9090/api/v1/query?query=100 - avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100'
   ```

2. **Find CPU-hungry processes**
   ```bash
   # For K8s cluster
   kubectl top pods -A --sort-by=cpu

   # For NixOS
   ps aux --sort=-%cpu | head -10
   ```

3. **Check for runaway processes**
   ```bash
   # Query rate of CPU usage
   curl 'http://prometheus.monitoring.svc:9090/api/v1/query?query=rate(container_cpu_usage_seconds_total[5m])'
   ```

#### Resolution Paths

**Path A: Scale Up Resources**
```bash
# For K8s deployments with HPA
kubectl autoscale deployment <name> --min=2 --max=10 --cpu-percent=70

# Manual scaling
kubectl scale deployment <name> --replicas=<higher>
```

**Path B: Tune Workloads**
```bash
# Adjust resource limits/requests
kubectl set resources deployment <name> \
  --requests=cpu=<lower> \
  --limits=cpu=<higher>

# For NixOS services
# Edit NixOS configuration and rebuild
```

**Path C: Investigate Application Issues**
```bash
# Check application logs for errors
kubectl logs <pod-name> -n <namespace> --tail=500

# Look for:
# - Infinite loops
# - Busy waiting
# - Inefficient algorithms
```

#### Verification

```bash
# Wait 10-15 minutes, verify CPU usage
curl 'http://prometheus.monitoring.svc:9090/api/v1/query?query=100 - avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100'

# Should be below 80%
```

---

### Incident: Loki Storage Full

**Severity**: Critical
**Alert**: `LokiStorageFull`
**Condition**: Loki chunk utilization > 90% for 5 minutes

#### Immediate Actions

1. **Check Loki storage status**
   ```bash
   kubectl exec -n monitoring -it loki-0 -- df -h /loki

   # Check PVC size
   kubectl get pvc -n monitoring | grep loki
   ```

2. **Identify large log sources**
   ```bash
   # Query Loki for top log streams
   logcli query '{job=~".+"}' --stats --from=7d

   # Look for jobs/labels with highest byte count
   ```

3. **Check for log spam**
   ```bash
   # Find top log streams
   logcli query '{job=~".+"}' --limit=10 --from=1h

   # If you see repetitive logs, identify the source
   ```

#### Resolution Paths

**Path A: Reduce Retention (Emergency)**
```bash
   # Temporary: reduce retention to free space
   # Edit charts/monitoring/templates/loki/configmap.yaml
   limits_config:
     retention_period: "7d"  # Reduce from 15d

   # Apply changes
   kubectl apply -f <path-to-chart>
   kubectl rollout restart statefulset/loki -n monitoring

   # Wait for compaction to free space
   # Monitor: kubectl exec -n monitoring loki-0 -- df -h /loki
```

**Path B: Exclude High-Volume Logs**
```bash
   # Edit Alloy configuration on affected cluster
   # Add relabeling to drop high-volume logs
   loki.source.kubernetes "pods" {
     relabel_rules = '''
       drop_log_line {
         drop_label_value "container", "nginx-ingress-controller"
       }
     '''
     forward_to = [loki.write.hub.receiver]
   }
```

**Path C: Increase PVC Size**
```bash
   # For long-term: increase PVC size
   # Edit chart values
   storage:
     logs:
       size: "30Gi"  # Increase from 20Gi

   # Apply changes
   helm upgrade <release> ./charts/monitoring -n monitoring
```

#### Verification

```bash
# Check Loki utilization
curl 'http://prometheus.monitoring.svc:9090/api/v1/query?query=loki_ingester_chunk_utilization'

# Should be below 90%
```

---

### Incident: PVC Above Threshold

**Severity**: Warning
**Alert**: `PVCAboveThreshold`
**Condition**: PVC usage > 85% for 10 minutes

#### Immediate Actions

1. **Identify affected PVC**
   ```bash
   # From alert
   # persistentvolumeclaim: <pvc-name>

   # Check PVC details
   kubectl get pvc <pvc-name> -n <namespace>
   ```

2. **Find what's using the space**
   ```bash
   # Find pods using the PVC
   kubectl get pods -n <namespace> -o json | jq '.items[].spec.volumes[] | select(.persistentVolumeClaim.claimName == "<pvc-name>")'

   # Check pod logs for large files
   kubectl exec <pod-name> -n <namespace> -- du -sh /path/to/pvc
   ```

3. **Check for log files growing unbounded**
   ```bash
   kubectl exec <pod-name> -n <namespace> -- find /path/to/pvc -name "*.log" -size +100M
   ```

#### Resolution Paths

**Path A: Clean Up Old Files**
```bash
   # For log files
   kubectl exec <pod-name> -n <namespace> -- rm /path/to/pvc/logs/*.old

   # For temporary files
   kubectl exec <pod-name> -n <namespace> -- rm /path/to/pvc/tmp/*
```

**Path B: Configure Log Rotation**
```bash
   # Add log rotation to application
   # Example for NixOS services
   services.logging.extraLogPaths = [ "/var/log/app/*.log" ]
   services.logrotate = {
     enable = true;
     settings = {
       compress = true;
       delaycompress = true;
       rotate = 10;
       size = "100M";
     };
   };
```

**Path C: Increase PVC Size**
```bash
   # Increase PVC size in chart values
   pvc:
     size: "20Gi"  # Increase from 10Gi

   # Apply changes
   # Note: Some storage classes don't support resize
```

#### Verification

```bash
# Check PVC usage
kubectl exec <pod-name> -n <namespace> -- df -h /path/to/pvc

# Should be below 85%
```

---

### Incident: Tailscale Connectivity Lost

**Severity**: Critical
**Alert**: `TailscaleConnectivityLost`
**Condition**: Alloy up == 0 for 2 minutes

#### Immediate Actions

1. **Identify affected system**
   ```bash
   # From alert
   # instance: <hostname>

   # Check Tailscale status
   # From system (if accessible via SSH)
   tailscale status
   ```

2. **Test network connectivity**
   ```bash
   # From hub cluster
   kubectl exec -n monitoring -it <alloy-pod> -- ping <system-tailscale-ip>

   # From affected system
   ping <hub-tailscale-ip>
   ```

3. **Check Tailscale logs**
   ```bash
   # For K8s
   kubectl logs -n kube-system -l app=tailscale --tail=100

   # For NixOS
   journalctl -u tailscaled -n 100
   ```

#### Resolution Paths

**Path A: Restart Tailscale**
```bash
   # For K8s DaemonSet
   kubectl rollout restart daemonset/tailscale -n kube-system

   # For NixOS
   sudo systemctl restart tailscaled
```

**Path B: Check ACLs**
```bash
   # From admin machine
   tailscale acl show

   # Ensure system has access to hub IPs
   # Required: 100.64.0.0/10
```

**Path C: Verify Machine Key**
```bash
   # Check if machine key is still valid
   tailscale status --json | jq '.Self'

   # If needed, re-authenticate
   tailscale up --authkey=<new-key>
```

#### Verification

```bash
# Test connectivity
ping <system-tailscale-ip>

# Verify Alloy is up
curl 'http://prometheus.monitoring.svc:9090/api/v1/query?query=up{job="alloy",instance="<system>"}'

# Expected: {"status":"success","data":{"resultType":"vector","result":[{"metric":{"..."},"value":[timestamp,"1"]}]}}
```

---

## Alert Management

### How to Silence Alerts

```bash
# For 1 hour
curl -X POST http://alertmanager.monitoring.svc:9093/api/v2/silences \
  -H 'Content-Type: application/json' \
  -d '{
    "matchers": [
      {"name": "alertname", "value": "InstanceDown", "isRegex": false}
    ],
    "startsAt": "2026-02-21T12:00:00Z",
    "endsAt": "2026-02-21T13:00:00Z",
    "createdBy": "operator",
    "comment": "Maintenance window"
  }'
```

### How to View Active Alerts

```bash
# From Prometheus
curl 'http://prometheus.monitoring.svc:9090/api/v1/alerts'

# From Alertmanager
curl http://alertmanager.monitoring.svc:9093/api/v2/alerts
```

### How to Acknowledge Alerts

```bash
# Open Grafana: http://grafana.monitoring.svc:3000
# Navigate to Alerting
# View and acknowledge alerts
# Add comments for documentation
```

---

## Component Troubleshooting

### Prometheus Issues

#### Prometheus Not Starting

```bash
# Check pod status
kubectl describe pod prometheus-0 -n monitoring

# Common issues:
# - PVC not ready: Check storage class
# - ConfigMap error: Check prometheus-config syntax
# - OOMKilled: Increase memory limits

# View logs
kubectl logs prometheus-0 -n monitoring --tail=100
```

#### Prometheus Not Scraping Targets

```bash
# Check targets
curl http://prometheus.monitoring.svc:9090/api/v1/targets

# Identify failed targets
# Check target labels:
#   - job: "kube-state-metrics" → check KSM service
#   - job: "alloy" → check Alloy pods

# Common fixes:
# - Check NetworkPolicies allow scraping
# - Verify service DNS resolution
# - Check RBAC permissions
```

#### Prometheus High Memory Usage

```bash
# Check memory usage
kubectl exec prometheus-0 -n monitoring -- cat /proc/meminfo

# Check TSDB size
kubectl exec prometheus-0 -n monitoring -- du -sh /prometheus

# If TSDB is large, reduce retention
# Edit values.yaml
prometheus:
  retention:
    time: "7d"  # Reduce from 15d
```

### Loki Issues

#### Loki Not Starting

```bash
# Check pod status
kubectl describe pod loki-0 -n monitoring

# Common issues:
# - PVC not ready: Check storage class
# - ConfigMap error: Check loki-config syntax

# View logs
kubectl logs loki-0 -n monitoring --tail=100
```

#### Loki Not Receiving Logs

```bash
# Check Alloy is sending logs
kubectl logs -n monitoring -l app.kubernetes.io/name=alloy | grep loki

# Check Loki is ready
curl http://loki.monitoring.svc:3100/ready

# Test Loki push
curl -X POST http://loki.monitoring.svc:3100/loki/api/v1/push \
  -H 'Content-Type: application/json' \
  -d '{"streams":[{"stream":{"job":"test"},"values":[["'$(( $(date +%s) * 1000000000 ))'","test log"]]}]}'

# Query logs
logcli query '{job="test"}' --limit=10
```

### Grafana Issues

#### Grafana Not Loading Dashboards

```bash
# Check Grafana is running
kubectl rollout status deployment/grafana -n monitoring

# Check datasources
curl http://grafana.monitoring.svc:3000/api/datasources

# Common issues:
# - Datasource down: Check Prometheus/Loki connectivity
# - Wrong UID: Check datasource configuration
# - Dashboard JSON error: Import manually via UI
```

#### Grafana Login Issues

```bash
# Reset admin password
kubectl exec -n monitoring -it deployment/grafana -- \
  grafana-cli admin reset-admin-password <new-password>

# Or get from 1Password
kubectl get secret monitoring-hub-secrets -n monitoring -o jsonpath='{.data.grafana_admin_password}' | base64 -d
```

### Alloy Issues

#### Alloy Not Pushing Metrics

```bash
# Check Alloy logs
kubectl logs -n monitoring -l app.kubernetes.io/name=alloy | grep prometheus

# Check remote_write configuration
kubectl get configmap -n monitoring alloy-configmap -o yaml

# Test hub connectivity
kubectl exec -n monitoring -it <alloy-pod> -- ping <hub-tailscale-ip>
```

#### Alloy Not Pushing Logs

```bash
# Check Alloy logs
kubectl logs -n monitoring -l app.kubernetes.io/name=alloy | grep loki

# Check log source configuration
kubectl get configmap -n monitoring alloy-configmap -o yaml | grep -A 20 "loki.source"

# Test Loki push
kubectl exec -n monitoring -it <alloy-pod> -- \
  curl -X POST http://<hub-tailscale-ip>:3100/loki/api/v1/push \
  -H 'Content-Type: application/json' \
  -d '{"streams":[{"stream":{"job":"test"},"values":[["'$(( $(date +%s) * 1000000000 ))'","test"]]}]}'
```

---

## Maintenance Procedures

### Hub Maintenance

#### Prometheus Maintenance Window

1. **Silence alerts**
   ```bash
   # See Alert Management section above
   ```

2. **Backup Prometheus data**
   ```bash
   kubectl exec -n monitoring prometheus-0 -- tar -czf /tmp/prometheus-backup.tar.gz /prometheus
   kubectl cp monitoring/prometheus-0:/tmp/prometheus-backup.tar.gz ./prometheus-backup-$(date +%Y%m%d).tar.gz
   ```

3. **Upgrade Prometheus**
   ```bash
   # Update chart values with new version
   # helm upgrade monitoring ./charts/monitoring -n monitoring
   ```

4. **Verify targets**
   ```bash
   curl http://prometheus.monitoring.svc:9090/api/v1/targets
   ```

#### Loki Maintenance Window

1. **Silence alerts**
   ```bash
   # See Alert Management section above
   ```

2. **Backup Loki data**
   ```bash
   kubectl exec -n monitoring loki-0 -- tar -czf /tmp/loki-backup.tar.gz /loki
   kubectl cp monitoring/loki-0:/tmp/loki-backup.tar.gz ./loki-backup-$(date +%Y%m%d).tar.gz
   ```

3. **Run compaction manually (if needed)**
   ```bash
   kubectl exec -n monitoring loki-0 -- wget -O- localhost:3100/compactor/run
   ```

4. **Verify logs are being received**
   ```bash
   logcli query '{job=~".+"}' --limit=10 --from=1m
   ```

### Spoke Maintenance

#### Upgrading Monitoring Agent

1. **Prepare new values**
   ```bash
   # Review charts/monitoring-agent/values-stages/<stage>.yaml
   # Update image tags if needed
   ```

2. **Deploy via ArgoCD**
   ```bash
   # ArgoCD will auto-sync if automated
   # Or manual sync via CLI/UI
   ```

3. **Verify connectivity**
   ```bash
   # Check logs
   kubectl logs -n monitoring -l app.kubernetes.io/name=alloy --tail=50

   # Verify metrics in hub
   curl 'http://prometheus.monitoring.svc:9090/api/v1/query?query=up{cluster="<spoke-name>"}'
   ```

---

## Recovery Procedures

### Recover from Lost Data

#### Prometheus Data Loss

```bash
# If TSDB is corrupted:
1. Scale down Prometheus to 0
   kubectl scale deployment prometheus --replicas=0 -n monitoring

2. Delete PVC
   kubectl delete pvc prometheus-pvc -n monitoring

3. Scale up Prometheus
   kubectl scale deployment prometheus --replicas=1 -n monitoring

# This creates a new TSDB with 0 data
# Data will be collected from scratch
```

#### Loki Data Loss

```bash
# If Loki data is corrupted:
1. Scale down Loki to 0
   kubectl scale statefulset loki --replicas=0 -n monitoring

2. Delete PVC
   kubectl delete pvc loki-loki-0 -n monitoring

3. Scale up Loki
   kubectl scale statefulset loki --replicas=1 -n monitoring

# Logs will be collected from scratch
```

### Recover from Complete Hub Failure

```bash
# If entire hub cluster is down:

1. Spokes will continue collecting data locally
   # Alloy buffers data for a period

2. Deploy new hub cluster
   # Follow charts/monitoring deployment procedure

3. Update spoke hub endpoints
   # Edit charts/monitoring-agent/values-clusters/*.yaml
   # Update: hubEndpoint: "<new-hub-ip>"

4. Spokes will reconnect and push buffered data
```

---

## Appendix

### Useful Queries

#### System Health
```promql
# All systems up
up

# Systems with issues
up == 0

# CPU usage by instance
100 - avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100

# Memory usage by instance
(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100
```

#### Storage Health
```promql
# Disk usage by filesystem
(node_filesystem_size_bytes - node_filesystem_avail_bytes) / node_filesystem_size_bytes * 100

# PVC usage
(kubelet_volume_stats_capacity_bytes - kubelet_volume_stats_available_bytes) / kubelet_volume_stats_capacity_bytes * 100

# Loki chunk utilization
loki_ingester_chunk_utilization
```

#### Network Health
```promql
# Network traffic by interface
rate(node_network_receive_bytes_total[5m])
rate(node_network_transmit_bytes_total[5m])

# Network errors
rate(node_network_receive_errs_total[5m])
rate(node_network_transmit_errs_total[5m])
```

### Contact Information

- **On-Call**: (TBD)
- **Engineering**: (TBD)
- **Infrastructure**: (TBD)

### Related Documentation

- [Architecture Guide](./monitoring-architecture.md)
- [Alert Rules Reference](./monitoring-alert-rules.md)
- [Resource Usage Guide](./monitoring-resources.md)
- [Troubleshooting Guide](./monitoring-troubleshooting.md)
