# Documentation

This folder contains implementation plans and documentation for the k8s-manifest infrastructure.

## Documents

### [Monitoring Infrastructure Implementation Plan](./monitoring-implementation-plan.md)

Comprehensive plan for setting up centralized monitoring infrastructure across multiple clusters.

**Status**: Planning phase  
**Last Updated**: 2026-02-14

**Key Components**:
- Centralized monitoring hub on OCI cluster
- Prometheus, Grafana, Loki, Alloy
- Multi-cluster support (hub + agents)
- Custom Helm charts (no external dependencies)

**Quick Links**:
- [Architecture Overview](./monitoring-implementation-plan.md#architecture)
- [Implementation Phases](./monitoring-implementation-plan.md#implementation-phases)
- [Resource Allocation](./monitoring-implementation-plan.md#resource-allocation)

## Adding New Documentation

1. Create a new `.md` file in this directory
2. Update this README with a link to the new document
3. Include date and status in the document header
