# Monitoring Chart - Critical Issues Fixed

## Issues Resolved

### 1. ✅ Missing kube-state-metrics
**Problem**: Prometheus config references kube-state-metrics but deployment/service didn't exist

**Solution**:
- Created `templates/kube-state-metrics/deployment.yaml`
  - Uses `registry.k8s.io/kube-state-metrics:v2.14.0`
  - Includes ServiceAccount and RBAC
  - Health checks on `/healthz` endpoint
- Created `templates/kube-state-metrics/service.yaml`
  - ClusterIP service on port 8080
  - Properly labeled for Prometheus discovery

**Impact**: K8s API object metrics (pods, nodes, deployments, etc.) now collected

---

### 2. ✅ Missing Alert Rules
**Problem**: Prometheus config references `/etc/prometheus/alerts/*.yml` but no rules ConfigMap exists

**Solution**:
- Created `templates/prometheus/alerts.yaml` with three rule groups:

  **system-alerts**:
  - `InstanceDown` - Critical, 1m threshold
  - `HighMemoryUsage` - Warning, 85% threshold, 5m
  - `HighCPUUsage` - Warning, 80% threshold, 5m

  **storage-alerts**:
  - `LokiStorageFull` - Critical, 90% threshold, 5m
  - `PVCAboveThreshold` - Warning, 85% threshold, 10m

  **connectivity-alerts**:
  - `TailscaleConnectivityLost` - Critical, 2m

**Note**: Used `{{ "{{" }}$labels.xxx{{ "}}" }}` pattern to escape Helm template variables

**Impact**: Alerts now fire for system down, resource exhaustion, storage, and connectivity issues

---

### 3. ✅ Non-deterministic Image Tags
**Problem**: All components used `tag: "latest"` - violates AGENTS.md standards

**Solution**: Updated `values.yaml` with specific stable versions:

| Component | Repository | Previous | Fixed Version |
|------------|-------------|-----------|---------------|
| Prometheus | prom/prometheus | latest | v3.5.1 |
| Loki | grafana/loki | latest | v3.2.0 |
| Grafana | grafana/grafana | latest | 11.3.0 |
| Alertmanager | prom/alertmanager | latest | v0.31.1 |
| Alloy | grafana/alloy | latest | v1.13.1 |
| Kube-state-metrics | registry.k8s.io/kube-state-metrics | N/A | v2.14.0 |

**Impact**: Reproducible deployments, easier rollbacks, production-safe

---

### 4. ✅ Grafana Datasource UID Mismatch
**Problem**: Loki datasource references `datasourceUid: prometheus` but Prometheus has no UID

**Solution**: Added `uid: "prometheus"` to Prometheus datasource in `grafana/configmap-datasources.yaml`

```yaml
- name: Prometheus
  type: prometheus
  uid: "prometheus"  # Added this line
  access: proxy
  url: http://prometheus.monitoring.svc:9090
```

**Impact**: DerivedFields linking between Loki and Prometheus now works correctly

---

## Additional Observations

### ⚠️ Issue 5: 1Password Secret Mount
**Status**: Not applicable - doesn't need fixing

**Reason**: Prometheus doesn't need 1Password secrets since all configuration is in ConfigMaps.
This is actually **correct** and simpler than unnecessarily mounting secrets.

---

### ✅ Issue 6: Validation Commands
**Status**: Correctly implemented

**Reason**: Plan docs show auth examples, but implementation correctly uses Tailscale-only security model.
This is the **correct approach** per our architecture design.

---

## Validation Results

### Helm Lint
```
helm lint charts/monitoring
```
✅ Passed (0 errors, 0 failures)

### Dry-Run Test
```
helm template charts/monitoring | kubectl apply --dry-run=client -f -
```
✅ All resources created successfully
- 27 YAML templates rendered
- 23 Kubernetes resources created (dry run)

---

## File Changes Summary

**New Files Created**:
1. `charts/monitoring/templates/kube-state-metrics/deployment.yaml`
2. `charts/monitoring/templates/kube-state-metrics/service.yaml`
3. `charts/monitoring/templates/prometheus/alerts.yaml`

**Files Modified**:
1. `charts/monitoring/values.yaml` - Updated all image tags
2. `charts/monitoring/templates/prometheus/deployment.yaml` - Added alerts volume
3. `charts/monitoring/templates/grafana/configmap-datasources.yaml` - Added Prometheus UID

---

## Pre-Deployment Checklist

Before deploying to OCI cluster, ensure:

- [ ] 1Password vault item `monitoring-hub` created with:
  - `grafana_admin_password`
  - `alertmanager_discord_webhook`
  - `alertmanager_discord_critical_webhook`

- [ ] ArgoCD cluster context `oci-cluster` exists

- [ ] k3s cluster has sufficient storage (64GB per node)

---

## Post-Deployment Verification

```bash
# Check all pods are running
kubectl get pods -n monitoring

# Verify Prometheus targets
kubectl port-forward svc/prometheus 9090:9090 -n monitoring
curl http://localhost:9090/api/v1/targets

# Verify Grafana datasources
kubectl port-forward svc/grafana 3000:3000 -n monitoring
# Navigate to http://localhost:3000/datasources

# Verify alerts are loaded
curl http://localhost:9090/api/v1/rules

# Test connectivity (via Tailscale from remote system)
curl http://<HUB_TAILSCALE_IP>:9090/-/healthy
curl http://<HUB_TAILSCALE_IP>:3100/ready
```

---

## Ready for Production

✅ All critical issues resolved
✅ Helm lint passes
✅ Dry-run validation passes
✅ Non-deterministic tags eliminated
✅ Alert rules implemented
✅ Kube-state-metrics added
✅ Datasource linking fixed

**Status**: READY FOR DEPLOYMENT
