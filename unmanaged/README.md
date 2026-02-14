# Unmanaged Resources

This directory contains resources that must be applied manually to clusters, as they cannot be managed by ArgoCD itself (e.g., ArgoCD's own service accounts for external clusters).

## Overview

ArgoCD can deploy to multiple Kubernetes clusters. Each external cluster requires:
1. A service account with appropriate permissions (applied manually to the target cluster)
2. Credentials stored in 1Password
3. A OnePasswordItem CRD to sync those credentials to a Kubernetes Secret
4. The Secret must have the label `argocd.argoproj.io/secret-type: cluster`

Once configured, ArgoCD automatically discovers the cluster and you can deploy applications to it using the cluster name.

## Current Clusters

### oci-cluster

Oracle Cloud Infrastructure cluster for staging/production workloads.

**Status**: Configured and active

**Quick Start:**
```bash
# The service account has already been applied to oci-cluster
# Credentials are stored in 1Password and synced automatically
```

## Adding a New Cluster

Follow these steps to add any new Kubernetes cluster to ArgoCD:

### Step 1: Create Service Account on Target Cluster

Apply this manifest to the cluster you want ArgoCD to manage:

```yaml
# Save as: unmanaged/<cluster-name>/argocd-serviceaccount.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: argocd
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-manager
  namespace: argocd
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: argocd-manager-role
rules:
  - apiGroups: ['*']
    resources: ['*']
    verbs: ['*']
  - nonResourceURLs: ['*']
    verbs: ['*']
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-manager-binding
subjects:
  - kind: ServiceAccount
    name: argocd-manager
    namespace: argocd
roleRef:
  kind: ClusterRole
  name: argocd-manager-role
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: v1
kind: Secret
type: kubernetes.io/service-account-token
metadata:
  name: argocd-manager-token
  namespace: argocd
  annotations:
    kubernetes.io/service-account.name: argocd-manager
```

Apply it:
```bash
kubectl --context <cluster-context> apply -f unmanaged/<cluster-name>/argocd-serviceaccount.yaml
```

### Step 2: Extract Credentials

Run these commands against the target cluster:

```bash
# Get the API server URL
kubectl --context <cluster-context> config view --minify -o jsonpath='{.clusters[0].cluster.server}'

# Get the bearer token
kubectl --context <cluster-context> get secret argocd-manager-token -n argocd -o jsonpath='{.data.token}' | base64 -d

# Get the CA certificate (base64 encoded)
kubectl --context <cluster-context> get secret argocd-manager-token -n argocd -o jsonpath='{.data.ca\.crt}'
```

### Step 3: Create 1Password Item

Create a new item in your 1Password vault with these exact field names:

| Field | Value | Example |
|-------|-------|---------|
| `name` | The cluster name ArgoCD will use | `production-cluster` |
| `server` | The API server URL | `https://10.0.0.50:6443` |
| `config` | JSON string with auth details | See below |

**Config field format:**
```json
{
  "bearerToken": "<service-account-token-from-step-2>",
  "tlsClientConfig": {
    "insecure": false,
    "caData": "<base64-ca-cert-from-step-2>"
  }
}
```

Note the 1Password item ID (found in the URL when viewing the item).

### Step 4: Add Cluster to ArgoCD Helm Chart

Create a new template file:

```bash
cat > charts/argocd/templates/cluster-<cluster-name>.yaml << 'EOF'
{{- if .Values.clusters.<cluster_name>.enabled }}
apiVersion: onepassword.com/v1
kind: OnePasswordItem
metadata:
  name: cluster-<cluster-name>
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
spec:
  itemPath: "vaults/<vault-id>/items/<1password-item-id>"
{{- end }}
EOF
```

Update `charts/argocd/values.yaml`:

```yaml
clusters:
  <cluster_name>:
    enabled: true
```

### Step 5: Deploy

Commit and push your changes:

```bash
git add .
git commit -m "feat(argocd): add <cluster-name> to deployment targets"
git push
```

ArgoCD will automatically:
1. Sync the OnePasswordItem
2. Create the Secret with the required label
3. Discover and connect to the new cluster

### Step 6: Verify

Check the ArgoCD UI or CLI:

```bash
argocd cluster list
# Should show: <cluster-name>  <server-url>  Successful
```

Deploy a test application:

```yaml
# argo-apps/test-<cluster-name>.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: test-app-<cluster-name>
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/Dumspy/k8s-manifest
    path: charts/sample-app
    targetRevision: HEAD
  destination:
    name: <cluster-name>
    namespace: test
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

## Deploying to External Clusters

Once a cluster is registered, deploy applications by referencing the cluster name:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/Dumspy/k8s-manifest
    path: charts/my-chart
    targetRevision: HEAD
  destination:
    name: <cluster-name>  # Use the cluster name from the 1Password 'name' field
    namespace: production
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## Troubleshooting

### "Failed to get cluster info" / Connection Timeout

- Verify network connectivity between ArgoCD cluster and target cluster
- Check if the target cluster API server is accessible from ArgoCD
- If using private IPs (Tailscale, VPN), ensure ArgoCD can route to those networks
- Test with: `kubectl run -it --rm debug --image=nicolaka/netshoot -- curl -k https://<api-server>/version`

### "Invalid bearer token" / Authentication Failed

- Regenerate the token: Delete and recreate the `argocd-manager-token` Secret on the target cluster
- Update the 1Password item with the new token
- Ensure the service account has the correct RBAC permissions

### Cluster Not Appearing in ArgoCD

- Check that `clusters.<name>.enabled: true` is set in values.yaml
- Verify the OnePasswordItem was created: `kubectl get onepassworditems -n argocd`
- Check the generated Secret has the correct label: `kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=cluster`
- Review ArgoCD logs: `kubectl logs -n argocd deployment/argocd-application-controller`
