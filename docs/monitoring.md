# Monitoring System Documentation

**Version**: 1.0
**Last Updated**: 2026-02-21
**Purpose**: Complete documentation index for monitoring infrastructure

---

## Overview

This monitoring system provides centralized observability across all Kubernetes clusters and NixOS systems. It uses a Hub-and-Spoke architecture with Grafana Alloy as the unified collector, pushing metrics and logs to a central OCI cluster via Tailscale VPN.

### Key Components

- **Hub (OCI k3s)**: Prometheus, Loki, Grafana, Alertmanager
- **Spokes**: Grafana Alloy + Kube-state-metrics
- **Connectivity**: Tailscale VPN (100.64.0.0/10)
- **Security**: Tailscale ACLs + Kubernetes NetworkPolicies

---

## Documentation Index

### Operational Guides

| Document | Purpose | Audience |
|----------|---------|----------|
| [Monitoring Runbook](./monitoring-runbook.md) | Step-by-step procedures for common incidents | SRE/Operators |
| [Monitoring Troubleshooting](./monitoring-troubleshooting.md) | Systematic troubleshooting approaches | All users |
| [Monitoring Deployment](./monitoring-deployment.md) | Complete deployment procedures | DevOps/SRE |

### Reference Guides

| Document | Purpose | Audience |
|----------|---------|----------|
| [Monitoring Architecture](./monitoring-architecture.md) | System design and component overview | All users |
| [Alert Rules Reference](./monitoring-alert-rules.md) | Complete alert rule definitions | SRE/Operators |
| [Resource Usage Guide](./monitoring-resources.md) | Resource calculations and optimization | DevOps/SRE |

### Implementation Plans

| Document | Purpose | Status |
|----------|---------|--------|
| [Monitoring Implementation Plan](./monitoring-implementation-plan.md) | Original plan with phases | Approved |
| [Monitoring Chart Fixes](./monitoring-chart-fixes.md) | Critical issues resolved in hub chart | Complete |
| [Monitoring Agent Phase 3 Part A](./monitoring-agent-phase3-parta.md) | Spoke K8s cluster deployment | Complete |

---

## Quick Start

### For New Team Members

1. **Read Architecture** (10 minutes)
   - [Monitoring Architecture](./monitoring-architecture.md)
   - Understand Hub-and-Spoke design
   - Learn component roles

2. **Read Deployment Guide** (20 minutes)
   - [Monitoring Deployment](./monitoring-deployment.md)
   - Learn how to deploy hub and spokes
   - Understand validation steps

3. **Read Runbook** (30 minutes, as needed)
   - [Monitoring Runbook](./monitoring-runbook.md)
   - Bookmark for incident response
   - Familiarize with common scenarios

### For Incident Response

1. **Identify the Problem**
   - Check alerts in Grafana
   - Check hub Prometheus targets
   - Check hub Loki queries

2. **Consult Runbook**
   - [Monitoring Runbook](./monitoring-runbook.md)
   - Find relevant incident type
   - Follow resolution steps

3. **If Not in Runbook**
   - [Monitoring Troubleshooting](./monitoring-troubleshooting.md)
   - Follow systematic methodology
   - Gather evidence and apply fix

---

## Chart Structure

### Hub Chart

```
charts/monitoring/
├── Chart.yaml                          # Chart metadata (v0.1.0)
├── values.yaml                         # Configuration for all components
├── templates/
│   ├── prometheus/                      # Prometheus deployment
│   ├── loki/                           # Loki statefulset
│   ├── grafana/                         # Grafana deployment
│   ├── alertmanager/                    # Alertmanager deployment
│   ├── alloy/                          # Alloy daemonset (OCI logs)
│   ├── kube-state-metrics/              # KSM deployment
│   ├── networkpolicy.yaml               # Tailscale IP restriction
│   ├── storageclass-*.yaml             # Storage classes
│   ├── 1password-secret.yaml           # Hub credentials
│   └── _helpers.tpl                    # Helm helpers
```

### Spoke Agent Chart

```
charts/monitoring-agent/
├── Chart.yaml                          # Wrapper chart with dependencies
├── values.yaml                         # Base configuration
├── values-stages/                     # Environment overrides
│   ├── production.yaml
│   ├── staging.yaml
│   └── development.yaml
├── values-clusters/                    # Cluster-specific overrides
│   ├── homelab-k8s.yaml
│   └── euw1-production.yaml
├── templates/
│   └── 1password-secret.yaml           # Hub credentials (optional)
└── charts/                            # Downloaded dependencies
    ├── alloy-*.tgz
    └── kube-state-metrics-*.tgz
```

---

## Resource Summary

### Hub Resources (OCI Cluster)

| Component | Memory | CPU | Storage |
|-----------|---------|-----|---------|
| Prometheus | 8Gi | 2K | 30Gi |
| Loki | 4Gi | 1K | 20Gi |
| Grafana | 512Mi | 200m | 0Gi |
| Alertmanager | 512Mi | 200m | 0Gi |
| Alloy (OCI) | 256Mi | 200m | 0Gi |
| Kube-state-metrics | 256Mi | 200m | 0Gi |
| **Total** | **~14Gi** | **~3.8K** | **50Gi** |

**Per Node (3 nodes)**: ~2.4Gi / 4.7Gi CPU, 50Gi storage distributed

### Spoke Resources (Per Node)

| Environment | Memory | CPU |
|------------|---------|-----|
| Production | 1Gi | 500m |
| Staging | 512Mi | 300m |
| Development | 256Mi | 200m |

---

## Alerts Summary

### Alert Groups

| Group | Alerts | Severity |
|-------|--------|----------|
| System | InstanceDown, HighMemoryUsage, HighCPUUsage | Critical/Warning |
| Storage | LokiStorageFull, PVCAboveThreshold | Critical/Warning |
| Connectivity | TailscaleConnectivityLost | Critical |

### Alert Routing

- **Discord**: All alerts (every 4 hours)
- **Discord Critical**: Critical alerts with @everyone (every 1 hour)

---

## Common Tasks

### Check System Health

```bash
# Hub cluster
kubectl get pods -n monitoring
kubectl top nodes

# Spoke cluster
kubectl get pods -n monitoring
kubectl top pods -n monitoring

# NixOS
sudo systemctl status alloy
sudo journalctl -u alloy -n 50
```

### Access Grafana

```bash
# Port forward
kubectl port-forward svc/grafana 3000:3000 -n monitoring

# Open browser
open http://localhost:3000
```

### Query Metrics

```bash
# Via Prometheus API
curl 'http://prometheus.monitoring.svc:9090/api/v1/query?query=up'

# Via Grafana
# Open Grafana → Explore
```

### Query Logs

```bash
# Via Loki CLI (from hub)
logcli query '{job=~".+"}' --limit=100

# Via Grafana
# Open Grafana → Explore → Loki
```

### Silence Alerts

```bash
# Via Alertmanager API
curl -X POST http://alertmanager.monitoring.svc:9093/api/v2/silences \
  -H 'Content-Type: application/json' \
  -d '{
    "matchers": [{"name": "alertname", "value": "InstanceDown"}],
    "startsAt": "2026-02-21T12:00:00Z",
    "endsAt": "2026-02-21T13:00:00Z",
    "createdBy": "operator",
    "comment": "Maintenance window"
  }'

# Via Grafana UI
# Navigate to Alerting → Alert Rules → Silence
```

---

## Support and Escalation

### Contact Information

- **On-Call**: (TBD)
- **Engineering**: (TBD)
- **Infrastructure**: (TBD)
- **Security**: (TBD)

### When to Escalate

1. **Critical incident not resolved in 30 minutes**
2. **Data loss or corruption**
3. **Security breach or compromise**
4. **Hub cluster completely down**
5. **Multiple spokes disconnected**

---

## Future Improvements

### Planned Enhancements

- [ ] Add Grafana dashboard provisioning from Git
- [ ] Implement Prometheus recording rules for query optimization
- [ ] Add Thanos for long-term storage
- [ ] Implement alert silencing via API
- [ ] Add synthetic monitoring
- [ ] Implement anomaly detection
- [ ] Add distributed tracing (Tempo)
- [ ] Create runbook for common issues

### Scaling Considerations

- [ ] Add hub HA (multiple Prometheus/Loki instances)
- [ ] Implement sharding for large-scale deployments
- [ ] Add caching layer for frequently accessed data
- [ ] Implement query federation for cross-cluster queries

---

## Glossary

| Term | Definition |
|-------|------------|
| **Hub** | Central monitoring cluster (OCI) that receives and stores data |
| **Spoke** | Remote system (K8s cluster or NixOS VM) that pushes data to hub |
| **Tailscale** | VPN service providing secure private network (100.64.0.0/10) |
| **LGTM** | Loki, Grafana, Tempo, Mimir - Grafana observability stack |
| **Alloy** | Grafana Alloy - unified collector for metrics and logs |
| **KSM** | Kube-state-metrics - K8s API object metrics |
| **remote_write** | Push-based metrics ingestion method |
| **Series** | Unique time series (metric name + label combination) |

---

## Contributing

### Documentation Updates

To update documentation:

1. **Edit the relevant file**
   ```bash
   vim docs/<file>.md
   ```

2. **Commit changes**
   ```bash
   git add docs/
   git commit -m "docs: update <file>"
   git push
   ```

3. **Update version number**
   - Increment version in all affected files
   - Add entry to Change Log

---

## Related Links

- **Implementation Plan**: [monitoring-implementation-plan.md](./monitoring-implementation-plan.md)
- **Chart Fixes**: [monitoring-chart-fixes.md](./monitoring-chart-fixes.md)
- **Phase 3 Part A**: [monitoring-agent-phase3-parta.md](./monitoring-agent-phase3-parta.md)
- **GitHub Repository**: https://github.com/Dumspy/k8s-manifest

---

## Version History

| Date | Version | Changes |
|-------|---------|---------|
| 2026-02-21 | 1.0 | Initial documentation index |

---

**Status**: ✅ Production Ready
