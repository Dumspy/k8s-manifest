# Monitoring Troubleshooting Guide

**Version**: 1.0
**Last Updated**: 2026-02-21
**Purpose**: Systematic troubleshooting procedures for monitoring issues

---

## Table of Contents

- [Troubleshooting Methodology](#troubleshooting-methodology)
- [Hub Issues](#hub-issues)
- [Spoke Issues](#spoke-issues)
- [Data Flow Issues](#data-flow-issues)
- [Performance Issues](#performance-issues)
- [Common Error Patterns](#common-error-patterns)

---

## Troubleshooting Methodology

### The 5-Step Process

1. **Identify the Problem**
   - What's not working?
   - When did it start?
   - What changed recently?

2. **Check the Basics**
   - Are components running?
   - Are they reachable?
   - Are there errors in logs?

3. **Isolate the Component**
   - Narrow down to specific component
   - Test in isolation
   - Rule out other factors

4. **Gather Evidence**
   - Collect logs
   - Gather metrics
   - Check configurations

5. **Apply Fix & Verify**
   - Implement the fix
   - Monitor for improvement
   - Document for future

### The Split Half Method

1. Split the problem in half
2. Test one half
3. If works, test other half
4. If doesn't work, split that half

---

## Hub Issues

### Prometheus Not Starting

#### Symptoms
- Pod status: `CrashLoopBackOff` or `Error`
- Events show: `OOMKilled`, `Failed to mount volume`

#### Checks

**Step 1**: Check pod status
```bash
kubectl describe pod prometheus-0 -n monitoring
```

**Step 2**: Check logs
```bash
kubectl logs prometheus-0 -n monitoring --tail=100
```

**Step 3**: Check PVC
```bash
kubectl get pvc prometheus-pvc -n monitoring
kubectl describe pvc prometheus-pvc -n monitoring
```

#### Common Causes & Fixes

**Issue: OOMKilled**
```yaml
# Fix: Increase memory limits
prometheus:
  resources:
    limits:
      memory: "12Gi"  # Increase from 8Gi
```

**Issue: PVC not ready**
```bash
# Check storage class
kubectl get storageclass

# If storage class missing, create it
# See charts/monitoring/templates/storageclass-metrics.yaml
```

**Issue: ConfigMap error**
```yaml
# Fix: Validate prometheus.yml syntax
kubectl get configmap prometheus-config -n monitoring -o yaml

# Test config locally
promtool check config /path/to/prometheus.yml
```

**Issue: Port conflict**
```bash
# Check if port 9090 is in use
kubectl get svc -A | grep 9090

# Fix: Change service port or namespace
```

---

### Prometheus Not Scraping Targets

#### Symptoms
- Targets in `http://prometheus:9090/targets` show `DOWN` state
- Alerts firing: `InstanceDown`

#### Checks

**Step 1**: Check targets
```bash
curl http://prometheus.monitoring.svc:9090/api/v1/targets
```

**Step 2**: Check specific target
```bash
# Replace <job> and <instance> with actual values
curl 'http://prometheus.monitoring.svc:9090/api/v1/targets?scrapeUrl=http://<instance>:<port>'
```

**Step 3**: Test direct connection
```bash
kubectl exec -n monitoring -it prometheus-0 -- curl http://<target-service>:<port>/metrics
```

#### Common Causes & Fixes

**Issue: Target not reachable**
```bash
# Check service exists
kubectl get svc <service-name> -n <namespace>

# Check endpoint exists
kubectl get endpoints <service-name> -n <namespace>

# Fix: Create service/endpoint if missing
```

**Issue: RBAC denied**
```bash
# Check service account
kubectl describe sa <service-account> -n <namespace>

# Check role binding
kubectl describe clusterrolebinding <binding-name>

# Fix: Add missing permissions
```

**Issue: NetworkPolicy blocking**
```bash
# Check network policies
kubectl get networkpolicy -n <namespace>

# Fix: Add allow rules for monitoring namespace
```

**Issue: TLS certificate error**
```bash
# Check certificate
kubectl exec -n monitoring -it prometheus-0 -- openssl s_client -connect <target>:443

# Fix: Update scrape config to ignore TLS or add CA
```

---

### Loki Not Starting

#### Symptoms
- Pod status: `CrashLoopBackOff` or `Error`
- API returns errors

#### Checks

**Step 1**: Check pod status
```bash
kubectl describe pod loki-0 -n monitoring
```

**Step 2**: Check logs
```bash
kubectl logs loki-0 -n monitoring --tail=100
```

**Step 3**: Test API
```bash
curl http://loki.monitoring.svc:3100/ready
```

#### Common Causes & Fixes

**Issue: OOMKilled**
```yaml
# Fix: Increase memory limits
loki:
  resources:
    limits:
      memory: "6Gi"  # Increase from 4Gi
```

**Issue: Config validation error**
```yaml
# Fix: Validate Loki config
# Loki will fail to start on invalid config

# Check syntax:
kubectl get configmap loki-config -n monitoring -o yaml
```

**Issue: Storage not writable**
```bash
# Check PVC permissions
kubectl exec -n monitoring -it loki-0 -- ls -la /loki

# Fix: Resize PVC or check storage class
```

---

### Grafana Not Loading Dashboards

#### Symptoms
- Dashboards show "Error loading dashboard"
- Datasources show "Connection refused"
- Empty panels

#### Checks

**Step 1**: Check Grafana logs
```bash
kubectl logs deployment/grafana -n monitoring --tail=100
```

**Step 2**: Check datasources
```bash
curl http://grafana.monitoring.svc:3000/api/datasources
```

**Step 3**: Test datasource connection
```bash
# Test Prometheus
curl http://prometheus.monitoring.svc:9090/api/v1/query?query=up

# Test Loki
curl 'http://loki.monitoring.svc:3100/loki/api/v1/query?query={job=~".+"}'
```

#### Common Causes & Fixes

**Issue: Datasource down**
```bash
# Check if Prometheus/Loki are running
kubectl get pods -n monitoring

# Check service DNS
kubectl exec -n monitoring -it deployment/grafana -- wget -O- http://prometheus.monitoring.svc:9090/-/healthy

# Fix: Restart affected component
```

**Issue: Wrong UID (derivedFields not working)**
```yaml
# Fix: Ensure Prometheus datasource has UID
# See charts/monitoring/templates/grafana/configmap-datasources.yaml
datasources:
  - name: Prometheus
    uid: "prometheus"  # Must match Loki's derivedFields
```

**Issue: Dashboard JSON error**
```bash
# Fix: Import dashboard manually via UI
# Verify JSON syntax: https://jsonlint.com/

# Fix common issues:
# - Missing quotes
# - Trailing commas
# - Invalid escape characters
```

---

## Spoke Issues

### Alloy Not Pushing Metrics

#### Symptoms
- No metrics from spoke in hub Prometheus
- Alert: `TailscaleConnectivityLost`
- Alloy logs show remote_write errors

#### Checks

**Step 1**: Check Alloy logs
```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=alloy --tail=100 | grep prometheus
```

**Step 2**: Check hub connectivity
```bash
kubectl exec -n monitoring -it <alloy-pod> -- ping <hub-tailscale-ip>
curl http://<hub-tailscale-ip>:9090/-/healthy
```

**Step 3**: Check hub remote_write receiver
```bash
curl http://<hub-tailscale-ip>:9090/api/v1/write -X POST -v
# Should return 204 No Content on success
```

#### Common Causes & Fixes

**Issue: Tailscale disconnected**
```bash
# Check Tailscale status
tailscale status

# Fix: Restart Tailscale
# K8s: kubectl rollout restart daemonset/tailscale -n kube-system
# NixOS: sudo systemctl restart tailscaled
```

**Issue: Wrong hub endpoint**
```yaml
# Fix: Update hub endpoint
alloy.configMap.content: |-
  prometheus.remote_write "hub" {
    endpoint {
      url = "http://<correct-hub-ip>:9090/api/v1/write"
    }
  }
```

**Issue: NetworkPolicy blocking**
```bash
# Check network policies
kubectl get networkpolicy -n monitoring

# Fix: Add allow rules for Tailscale network
```

**Issue: Resource exhausted**
```bash
# Check pod status
kubectl describe pod <alloy-pod> -n monitoring

# Fix: Increase resource limits
alloy:
  resources:
    limits:
      memory: "1.5Gi"
      cpu: "750m"
```

---

### Alloy Not Pushing Logs

#### Symptoms
- No logs from spoke in hub Loki
- Log queries return empty results
- Alloy logs show write errors

#### Checks

**Step 1**: Check Alloy logs
```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=alloy --tail=100 | grep loki
```

**Step 2**: Check hub Loki API
```bash
curl http://<hub-tailscale-ip>:3100/ready

# Test push
curl -X POST http://<hub-tailscale-ip>:3100/loki/api/v1/push \
  -H 'Content-Type: application/json' \
  -d '{"streams":[{"stream":{"job":"test"},"values":[["'$(( $(date +%s) * 1000000000 ))'","test"]]}]}'
```

**Step 3**: Query Loki
```bash
logcli query '{job="test"}' --limit=10
```

#### Common Causes & Fixes

**Issue: High log volume rate-limited**
```bash
# Check Alloy logs for "rate limit" errors
kubectl logs -n monitoring -l app.kubernetes.io/name=alloy | grep "rate limit"

# Fix: Drop high-volume logs
loki.source.kubernetes "pods" {
  relabel_rules = '''
    drop_log_line {
      drop_label_value "pod", "log-spammer"
    }
  '''
}
```

**Issue: Label cardinality too high**
```bash
# Check for too many labels
logcli labels --from=1h

# Fix: Reduce labels in log source
# Drop high-cardinality labels
```

**Issue: Hub Loki storage full**
```bash
# Check hub Loki storage
kubectl exec -n monitoring loki-0 -- df -h /loki

# Fix: Reduce retention or expand PVC
```

---

## Data Flow Issues

### Metrics Not Arriving at Hub

#### Troubleshooting Steps

1. **Verify metrics at source**
   ```bash
   # Check Alloy metrics endpoint
   kubectl port-forward svc/alloy 9090:9090 -n monitoring
   curl http://localhost:9090/metrics
   ```

2. **Verify metrics are being sent**
   ```bash
   # Check remote_write metrics
   kubectl logs -n monitoring -l app.kubernetes.io/name=alloy | grep remote_write
   ```

3. **Verify hub is receiving**
   ```bash
   # From hub
   curl 'http://prometheus.monitoring.svc:9090/api/v1/query?query=up{cluster="<spoke-name>"}'
   ```

4. **Check hub Prometheus logs**
   ```bash
   kubectl logs prometheus-0 -n monitoring | grep remote_write
   ```

---

### Logs Not Arriving at Hub

#### Troubleshooting Steps

1. **Verify logs at source**
   ```bash
   # Check Alloy logs
   kubectl logs -n monitoring -l app.kubernetes.io/name=alloy | grep loki
   ```

2. **Verify logs are being sent**
   ```bash
   # Check write metrics
   kubectl logs -n monitoring -l app.kubernetes.io/name=alloy | grep loki.send
   ```

3. **Verify hub is receiving**
   ```bash
   # From hub
   logcli query '{cluster="<spoke-name>"}' --limit=10
   ```

4. **Check hub Loki logs**
   ```bash
   kubectl logs loki-0 -n monitoring | grep received
   ```

---

## Performance Issues

### Slow Prometheus Queries

#### Symptoms
- Dashboard load time >10s
- Query timeout errors
- Prometheus high CPU usage

#### Checks

**Step 1**: Check query duration
```bash
# From Prometheus UI, check query stats
# Stats → Query Stats

# Or via API
curl http://prometheus.monitoring.svc:9090/api/v1/query_stats
```

**Step 2**: Check series count
```bash
# Count number of series
curl 'http://prometheus.monitoring.svc:9090/api/v1/query?query=count({__name__=~".+"})'
```

**Step 3**: Check memory usage
```bash
kubectl exec prometheus-0 -n monitoring -- cat /proc/meminfo
```

#### Common Causes & Fixes

**Issue: Too many series**
```bash
# Identify high-cardinality metrics
curl 'http://prometheus.monitoring.svc:9090/api/v1/label/__name__/values'

# Fix: Drop high-cardinality metrics in scrape config
```

**Issue: Expensive range queries**
```bash
# Identify slow queries
# From Prometheus UI: Status → Query Stats

# Fix: Reduce query range, increase scrape interval
```

**Issue: Insufficient memory**
```yaml
# Fix: Increase memory limits
prometheus:
  resources:
    limits:
      memory: "12Gi"
```

---

### Slow Loki Queries

#### Symptoms
- Log queries timeout
- Empty results when data exists
- Loki high CPU usage

#### Checks

**Step 1**: Check query duration
```bash
# From Loki UI, check query stats
# Or add duration to logcli command
logcli query '{job=~".+"}' --stats --from=1h
```

**Step 2**: Check index size
```bash
# Check Loki stats
curl http://loki.monitoring.svc:3100/loki/api/v1/stats
```

**Step 3**: Check memory usage
```bash
kubectl exec loki-0 -n monitoring -- cat /proc/meminfo
```

#### Common Causes & Fixes

**Issue: Label cardinality too high**
```bash
# Check label cardinality
logcli labels --from=1h

# Fix: Reduce labels in log source
```

**Issue: Wide time range queries**
```bash
# Fix: Narrow query time range, use step parameter
logcli query '{job=~".+"}' --from=1h --step=1m
```

**Issue: Insufficient memory**
```yaml
# Fix: Increase memory limits
loki:
  resources:
    limits:
      memory: "6Gi"
```

---

## Common Error Patterns

### 503 Service Unavailable

**When**: Connecting to Prometheus/Loki/Grafana

**Likely Causes**:
1. Component is restarting (CrashLoopBackOff)
2. Component is overloaded (throttling)
3. Network partition

**Troubleshooting**:
```bash
# Check pod status
kubectl get pods -n monitoring

# Check pod resource limits
kubectl describe pod <pod-name> -n monitoring

# Check node resource usage
kubectl top nodes
```

---

### 504 Gateway Timeout

**When**: Long-running queries

**Likely Causes**:
1. Query too complex
2. Time range too large
3. Too many series/labels

**Troubleshooting**:
```bash
# Simplify query
# Reduce time range
# Add more label filters
```

---

### 404 Not Found

**When**: Accessing URLs

**Likely Causes**:
1. Wrong URL path
2. Component not exposed on service
3. Ingress/LoadBalancer misconfiguration

**Troubleshooting**:
```bash
# Check service ports
kubectl get svc <service-name> -n monitoring

# Check component ports
kubectl describe pod <pod-name> -n monitoring

# Verify URL path
# Prometheus: http://<service>:9090/api/v1/...
# Loki: http://<service>:3100/loki/api/v1/...
```

---

### 401 Unauthorized

**When**: Accessing Grafana or Alertmanager

**Likely Causes**:
1. Wrong password
2. Session expired
3. Authentication token invalid

**Troubleshooting**:
```bash
# Check secret
kubectl get secret monitoring-hub-secrets -n monitoring -o yaml

# Reset password
kubectl exec -n monitoring -it deployment/grafana -- \
  grafana-cli admin reset-admin-password <new-password>
```

---

## Related Documentation

- [Monitoring Runbook](./monitoring-runbook.md)
- [Monitoring Architecture](./monitoring-architecture.md)
- [Alert Rules Reference](./monitoring-alert-rules.md)
- [Resource Usage Guide](./monitoring-resources.md)

---

## Change Log

| Date | Version | Changes |
|-------|---------|---------|
| 2026-02-21 | 1.0 | Initial troubleshooting guide |
