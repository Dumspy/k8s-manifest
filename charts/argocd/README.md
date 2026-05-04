# ArgoCD Helm Chart

This chart deploys ArgoCD along with the `argocd-image-updater` and bootstraps ApplicationSets for cluster-wide app management.

## Dependencies

| Chart | Version | Repository |
|---|---|---|
| argo-cd | 9.5.11 | https://argoproj.github.io/argo-helm |
| argocd-image-updater | 1.1.4 | https://argoproj.github.io/argo-helm |

## ApplicationSet Bootstrap

The chart can generate ArgoCD `ApplicationSets` from the `bootstrap` values. Each ApplicationSet uses a Git file generator to discover app definition files across the repository.

### Values

```yaml
bootstrap:
  repoURL: https://github.com/Dumspy/k8s-manifest
  applicationSets:
    - name: apps
      env: all
      branch: HEAD
      path: "apps/*/*.yaml"
```

| Field | Description |
|---|---|
| `bootstrap.repoURL` | Git repository URL scanned by the ApplicationSets |
| `bootstrap.applicationSets` | List of ApplicationSets to create |
| `bootstrap.applicationSets[].name` | Name of the ApplicationSet |
| `bootstrap.applicationSets[].env` | Environment label for the ApplicationSet |
| `bootstrap.applicationSets[].branch` | Git branch (or revision) to scan |
| `bootstrap.applicationSets[].path` | Glob pattern for app definition files |
| `bootstrap.applicationSets[].excludePath` | Optional glob pattern to exclude |

### App Definition File Format

Each file discovered by the Git generator must be a YAML file containing the following fields:

```yaml
name: <application-name>
namespace: <target-namespace>
project: <argocd-project>
chart_path: <path-to-helm-chart-in-repo>
targetRevision: <git-revision>
value_file1: <primary-values-file>
value_file2: <optional-secondary-values-file>
cluster: <argocd-cluster-name>
notifications:
  - <notification-event>
```

App files are organized under `apps/<chart-name>/<cluster-prefix>-<app-name>.yaml`.

### Cluster Field

- For the local cluster, use `cluster: in-cluster`
- For external clusters registered in ArgoCD, use the cluster secret name (e.g., `oci-cluster`)

## Fresh Bootstrap

To install ArgoCD on a brand new cluster from scratch:

1. Install the chart manually:

```bash
helm dependency update charts/argocd
helm install argocd charts/argocd -n argocd --create-namespace
```

2. Once ArgoCD is running and the UI is accessible, apply the self-managing Application manifest so ArgoCD manages its own deployment going forward:

```bash
kubectl apply -f argo-apps/argocd.yaml
```

After this step, any future changes to `charts/argocd` (including ApplicationSet updates) will be automatically synced by ArgoCD itself.

## Notifications

Notification templates and triggers are configured under `argo-cd.notifications` in `values.yaml`. Slack tokens are sourced from the 1Password Operator.
