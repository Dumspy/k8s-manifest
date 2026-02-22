# Monitoring Deployment Guide

**Version**: 1.0
**Last Updated**: 2026-02-21
**Purpose**: Complete deployment procedures for monitoring system

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Hub Deployment](#hub-deployment)
- [Spoke Deployment](#spoke-deployment)
- [Post-Deployment Validation](#post-deployment-validation)
- [Upgrade Procedures](#upgrade-procedures)
- [Rollback Procedures](#rollback-procedures)

---

## Prerequisites

### Infrastructure Requirements

#### Hub (OCI Cluster)
- **Kubernetes**: k3s v1.27+
- **Nodes**: 3 nodes minimum
- **Resources per node**:
  - CPU: 2 cores minimum
  - RAM: 8GB minimum (64GB total for 3 nodes)
  - Storage: 64GB per node (k3s local-path)

#### Spoke (K8s Cluster)
- **Kubernetes**: v1.23+
- **Nodes**: 1-3 nodes
- **Resources per node**:
  - CPU: 1 core minimum
  - RAM: 2GB minimum
  - Network: Tailscale connectivity

#### Spoke (NixOS VMs)
- **OS**: NixOS 23.05+
- **Resources**:
  - CPU: 1 core minimum
  - RAM: 512MB minimum
  - Network: Tailscale connectivity

### Software Requirements

#### Hub Cluster
- **kubectl**: v1.23+
- **Helm**: v3.12+
- **ArgoCD**: v2.7+
- **1Password operator**: v1.5+

#### Spoke Clusters
- **kubectl**: v1.23+
- **Helm**: v3.12+
- **ArgoCD**: v2.7+
- **Tailscale**: v1.60+
- **1Password operator**: v1.5+ (optional)

#### NixOS VMs
- **NixOS**: 23.05+
- **Tailscale**: v1.60+
- **Grafana Alloy**: v1.13.1+

### Network Requirements

#### Tailscale Configuration

**Hub Setup**:
```bash
# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Connect to tailnet
sudo tailscale up --authkey=<auth-key>

# Note the Tailscale IP (e.g., 100.64.0.2)
tailscale status --json | jq '.Self.TailscaleIPs[0]'
```

**Spoke Setup**:
```bash
# Install Tailscale (same as hub)
# Connect to same tailnet
# Ensure spoke can reach hub: ping 100.64.0.2
```

**ACL Configuration**:
```
{
  "tagOwners": {
    "tag:hub": ["admin@example.com"],
    "tag:spoke": ["admin@example.com"]
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

### 1Password Setup

#### Create Vault

1. Log in to 1Password CLI
```bash
op account add
op signin <email> <secret-key>
```

2. Create vault: `infrastructure`

#### Create Hub Secrets

**Item**: `monitoring-hub`
```
Fields:
  - grafana_admin_password (generate strong password)
  - alertmanager_discord_webhook (Discord webhook URL)
  - alertmanager_discord_critical_webhook (Discord webhook URL for @everyone)
```

#### Create Spoke Secrets (Optional)

**Item**: `monitoring-spoke`
```
Fields:
  - hub_endpoint (optional, can set in values)
  - cluster_name (optional, can set in values)
```

---

## Hub Deployment

### Step 1: Prepare Cluster

```bash
# Add ArgoCD cluster context (if not added)
argocd cluster add <oci-cluster-kubeconfig> --name oci-cluster

# Verify cluster connection
argocd cluster list
```

### Step 2: Create Storage Classes (k3s)

**Note**: k3s local-path storage is typically pre-configured. Check if exists:
```bash
kubectl get storageclass

# If missing, create from chart
kubectl apply -f charts/monitoring/templates/storageclass-metrics.yaml
kubectl apply -f charts/monitoring/templates/storageclass-logs.yaml
```

### Step 3: Create 1Password Secrets

**Via Operator** (automatic):
- ArgoCD will apply `1password-secret.yaml`
- Operator will sync 1Password item to Kubernetes Secret

**Manual Verification**:
```bash
# Check secret created
kubectl get secret monitoring-hub-secrets -n monitoring -o yaml

# Verify fields exist
kubectl get secret monitoring-hub-secrets -n monitoring -o jsonpath='{.data}'
```

### Step 4: Deploy ArgoCD Application

```bash
# Apply ArgoCD application
kubectl apply -f argo-apps/monitoring.yaml

# Verify application created
argocd app get monitoring-hub

# Wait for sync to complete
argocd app wait monitoring-hub --timeout 600
```

### Step 5: Verify Deployment

```bash
# Check all pods are running
kubectl get pods -n monitoring

# Expected output:
# NAME                                  READY   STATUS    RESTARTS   AGE
# alertmanager-7d4d8f9b9-km2jv          1/1     Running   0          5m
# alloy-7d4d8f9b9-km2jv-<node-id>     1/1     Running   0          5m
# grafana-7d4d8f9b9-km2jv              1/1     Running   0          5m
# kube-state-metrics-7d4d8f9b9-km2jv     1/1     Running   0          5m
# loki-0                                1/1     Running   0          5m
# prometheus-7d4d8f9b9-km2jv             1/1     Running   0          5m
```

### Step 6: Access Grafana

```bash
# Port forward Grafana
kubectl port-forward svc/grafana 3000:3000 -n monitoring

# Open browser: http://localhost:3000

# Login with admin credentials
# Username: admin
# Password: from 1Password
```

### Step 7: Verify Datasources

**Via Grafana UI**:
1. Navigate to Configuration → Datasources
2. Verify Prometheus and Loki datasources exist
3. Test connection for each datasource

**Via API**:
```bash
curl http://grafana.monitoring.svc:3000/api/datasources
```

### Step 8: Verify Metrics

```bash
# Check Prometheus targets
kubectl port-forward svc/prometheus 9090:9090 -n monitoring

# Open browser: http://localhost:9090/targets
# Verify all targets are UP

# Check metrics via API
curl 'http://localhost:9090/api/v1/query?query=up'
```

### Step 9: Verify Alerts

```bash
# Check Alertmanager
kubectl port-forward svc/alertmanager 9093:9093 -n monitoring

# Open browser: http://localhost:9093
# Verify Discord webhooks configured

# Test alert (force one)
# See Alert Rules Reference guide
```

---

## Spoke Deployment

### Step 1: Prepare Cluster

```bash
# Add ArgoCD cluster context
argocd cluster add <spoke-kubeconfig> --name <spoke-name>

# Verify cluster connection
argocd cluster list

# Verify Tailscale connectivity
ping <hub-tailscale-ip>
```

### Step 2: Configure Values

**Option A: Use Cluster File**

1. Create cluster-specific values file:
```bash
vim charts/monitoring-agent/values-clusters/<spoke-name>.yaml
```

2. Configure:
```yaml
global:
  clusterName: "my-spoke-cluster"
  environment: "production"
  hubEndpoint: "100.64.0.2"  # Replace with actual hub IP

alloy:
  resources:
    limits:
      memory: "1Gi"  # Adjust for cluster size
```

**Option B: Use Inline Values**

1. Prepare values in ArgoCD application
```yaml
helm:
  values: |
    global:
      clusterName: "my-spoke-cluster"
      hubEndpoint: "100.64.0.2"
```

### Step 3: Deploy ArgoCD Application

**With Cluster File**:
```bash
kubectl apply -f argo-apps/monitoring-agent-<spoke-name>.yaml
```

**With Inline Values**:
```bash
kubectl apply -f argo-apps/monitoring-agent-<spoke-name>.yaml
```

### Step 4: Verify Deployment

```bash
# Check ArgoCD sync
argocd app get monitoring-agent-<spoke-name>

# Wait for sync
argocd app wait monitoring-agent-<spoke-name> --timeout 600

# Check pods
kubectl get pods -n monitoring

# Expected output:
# NAME                              READY   STATUS    RESTARTS   AGE
# alloy-<hash>                      1/1     Running   0          5m
# kube-state-metrics-<hash>         1/1     Running   0          5m
```

### Step 5: Verify Connectivity to Hub

```bash
# Check Alloy logs for remote_write
kubectl logs -n monitoring -l app.kubernetes.io/name=alloy --tail=100 | grep remote_write

# Expected: No errors, successful sends

# Check hub Prometheus for spoke metrics
# From hub cluster
curl 'http://prometheus.monitoring.svc:9090/api/v1/query?query=up{cluster="<spoke-name>"}'

# Expected: {"status":"success","data":{"resultType":"vector","result":[{"metric":{"cluster":"<spoke-name>",...},"value":[timestamp,"1"]}]}}
```

---

## NixOS Deployment

### Step 1: Enable Tailscale

```nix
{ config, pkgs, ... }:
{
  services.tailscale = {
    enable = true;
  };
}
```

### Step 2: Configure Alloy

```nix
{ config, pkgs, ... }:
{
  services.alloy = {
    enable = true;
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
          url = "http://100.64.0.2:9090/api/v1/write"  # Replace with actual hub IP
        }
        external_labels = {
          cluster = "homelab-nixos"
          host = "${config.networking.hostName}"
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
          url = "http://100.64.0.2:3100/loki/api/v1/push"  # Replace with actual hub IP
        }
      }
    '';
  };
}
```

### Step 3: Apply Configuration

```bash
# Rebuild NixOS configuration
sudo nixos-rebuild switch

# Reboot if required
sudo reboot
```

### Step 4: Verify Deployment

```bash
# Check Alloy service status
sudo systemctl status alloy

# Check Alloy logs
sudo journalctl -u alloy -n 100

# Verify metrics in hub
# From hub cluster
curl 'http://prometheus.monitoring.svc:9090/api/v1/query?query=up{cluster="homelab-nixos"}'
```

---

## Post-Deployment Validation

### Hub Validation Checklist

- [ ] All pods are running (`kubectl get pods -n monitoring`)
- [ ] PVCs are bound (`kubectl get pvc -n monitoring`)
- [ ] Prometheus targets are UP (`http://prometheus:9090/targets`)
- [ ] Loki is receiving logs (`logcli query '{job=~".+"}'`)
- [ ] Grafana datasources are connected (`http://grafana:3000/api/datasources`)
- [ ] Alerts are evaluated (`http://prometheus:9090/rules`)
- [ ] Discord webhooks are working (test alert)
- [ ] Tailscale connectivity from spoke (ping hub)

### Spoke Validation Checklist

- [ ] Alloy pods are running (`kubectl get pods -n monitoring`)
- [ ] Alloy logs show no errors (`kubectl logs -n monitoring -l app.kubernetes.io/name=alloy`)
- [ ] Metrics visible in hub Prometheus (`up{cluster="<spoke>"}`)
- [ ] Logs visible in hub Loki (`{cluster="<spoke>"}`)
- [ ] External labels set correctly (`up{cluster="<spoke>"}`)
- [ ] Network connectivity to hub verified

---

## Upgrade Procedures

### Hub Upgrade

**Step 1: Update chart**
```bash
cd charts/monitoring

# Update Chart.yaml version
vim Chart.yaml
# Increment version: 0.1.0 → 0.1.1
```

**Step 2: Update dependencies (if any)**
```bash
# Currently, hub chart has no external dependencies
```

**Step 3: Update values**
```bash
vim values.yaml
# Update image tags, resource limits, etc.
```

**Step 4: Test locally**
```bash
# Lint chart
helm lint .

# Dry-run
helm template . | kubectl apply --dry-run=client -f -
```

**Step 5: Commit and push**
```bash
git add .
git commit -m "feat(monitoring): upgrade to v0.1.1"
git push
```

**Step 6: ArgoCD will sync automatically**
```bash
# Monitor sync progress
argocd app get monitoring-hub

# Wait for sync
argocd app wait monitoring-hub
```

**Step 7: Verify upgrade**
```bash
# Check pods are running
kubectl get pods -n monitoring

# Check new version is deployed
kubectl describe pod prometheus-0 -n monitoring | grep Image
```

### Spoke Upgrade

**Step 1: Update chart dependencies**
```bash
cd charts/monitoring-agent

helm dependency update
```

**Step 2: Update values**
```bash
# Update base values
vim values.yaml

# Or update cluster-specific values
vim values-clusters/<spoke>.yaml

# Or update stage values
vim values-stages/production.yaml
```

**Step 3: Test locally**
```bash
# Lint chart
helm lint .

# Dry-run
helm template . \
  --set global.clusterName=test \
  --set global.hubEndpoint=100.64.0.2 | kubectl apply --dry-run=client -f -
```

**Step 4: Commit and push**
```bash
git add .
git commit -m "feat(monitoring-agent): upgrade to v0.1.1"
git push
```

**Step 5: ArgoCD will sync automatically**
```bash
# Monitor sync progress
argocd app get monitoring-agent-<spoke-name>

# Wait for sync
argocd app wait monitoring-agent-<spoke-name>
```

---

## Rollback Procedures

### Hub Rollback

**Via ArgoCD**:
```bash
# Get application history
argocd app history monitoring-hub

# Sync to previous revision
argocd app rollback monitoring-hub --revision=<prev-revision>
```

**Via Helm**:
```bash
# Get release history
helm history monitoring -n monitoring

# Rollback to previous version
helm rollback monitoring <prev-revision> -n monitoring
```

**Manual Rollback**:
```bash
# 1. Scale down deployments
kubectl scale deployment prometheus --replicas=0 -n monitoring
kubectl scale deployment loki --replicas=0 -n monitoring
# etc.

# 2. Restore previous chart version
git checkout <prev-commit>

# 3. Apply
helm install monitoring ./charts/monitoring -n monitoring

# 4. Scale up
kubectl scale deployment prometheus --replicas=1 -n monitoring
```

### Spoke Rollback

**Via ArgoCD**:
```bash
# Get application history
argocd app history monitoring-agent-<spoke-name>

# Sync to previous revision
argocd app rollback monitoring-agent-<spoke-name> --revision=<prev-revision>
```

**Via Helm**:
```bash
# Get release history
helm history monitoring-agent -n monitoring

# Rollback to previous version
helm rollback monitoring-agent <prev-revision> -n monitoring
```

---

## Disaster Recovery

### Hub Data Loss

**Scenario**: Prometheus or Loki PVC corrupted/deleted

**Recovery Steps**:

1. **Identify data loss**
   ```bash
   kubectl get pvc -n monitoring
   kubectl describe pvc prometheus-pvc -n monitoring
   ```

2. **Scale down component**
   ```bash
   kubectl scale deployment prometheus --replicas=0 -n monitoring
   ```

3. **Delete PVC**
   ```bash
   kubectl delete pvc prometheus-pvc -n monitoring
   ```

4. **Scale up component** (new PVC created)
   ```bash
   kubectl scale deployment prometheus --replicas=1 -n monitoring
   ```

5. **Restore from backup** (if available)
   ```bash
   # External backup system handles this
   # Follow backup restore procedures
   ```

### Hub Cluster Loss

**Scenario**: Entire OCI cluster down

**Recovery Steps**:

1. **Spokes buffer data**
   - Alloy buffers metrics/logs for a period
   - No immediate data loss

2. **Deploy new hub cluster**
   - Follow hub deployment procedures

3. **Update spoke hub endpoints**
   - Update `hubEndpoint` in spoke values
   - ArgoCD will sync and reconnect

4. **Spokes push buffered data**
   - Data will eventually arrive at new hub

---

## Related Documentation

- [Monitoring Runbook](./monitoring-runbook.md)
- [Monitoring Architecture](./monitoring-architecture.md)
- [Alert Rules Reference](./monitoring-alert-rules.md)
- [Resource Usage Guide](./monitoring-resources.md)
- [Troubleshooting Guide](./monitoring-troubleshooting.md)

---

## Change Log

| Date | Version | Changes |
|-------|---------|---------|
| 2026-02-21 | 1.0 | Initial deployment guide |
