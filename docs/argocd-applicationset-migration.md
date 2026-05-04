# ArgoCD ApplicationSet Migration Rollout Plan

This document describes the step-by-step safe rollout for migrating from the `argo-apps/base.yml` app-of-apps pattern to ArgoCD `ApplicationSets` managed by the `charts/argocd` Helm chart.

## Pre-Migration Checklist

Before starting the migration, verify the following:

1. **All Applications are healthy and synced:**
   ```bash
   argocd app list
   ```
   Every app should show `Synced` and `Healthy`.

2. **Confirm `base.yml` does not have automated prune:**
   Check `argo-apps/base.yml` — it must NOT contain a `syncPolicy.automated.prune: true` block. If it does, disable auto-sync on the `base-app` Application in the ArgoCD UI before proceeding.

3. **Verify cluster access:**
   Ensure the `oci-cluster` cluster secret is present and healthy in ArgoCD.

## Migration Steps

### Step 1: Ensure ArgoCD is self-managed

`argo-apps/argocd.yaml` must exist as an ArgoCD Application independently of `base.yml` so it survives the removal of the app-of-apps wrapper.

If `argo-apps/argocd.yaml` is not already applied directly to the cluster:

```bash
kubectl apply -f argo-apps/argocd.yaml
```

Confirm it appears in `argocd app list` and is syncing successfully.

### Step 2: Deploy the ApplicationSets

Commit and merge the changes that add:
- `charts/argocd/templates/applicationset.yaml`
- Updated `charts/argocd/values.yaml` with `bootstrap.applicationSets`
- New app definition files under `apps/`

ArgoCD will sync the `argo-cd` Application (from `argo-apps/argocd.yaml`), which renders the chart and creates the `apps` ApplicationSet.

Verify the ApplicationSet is created:
```bash
kubectl get applicationsets -n argocd
```

### Step 3: Verify Application adoption

The ApplicationSets will generate `Application` resources using the same names as the existing apps. Because the names match, ArgoCD will update the existing Applications in-place rather than creating duplicates.

Verify each app is now tracked by its ApplicationSet:
```bash
argocd app list
```

Check the ArgoCD UI — each Application should show it is managed by an ApplicationSet.

### Step 4: Remove the legacy app-of-apps wrapper

Once all Applications are confirmed healthy and tracked by ApplicationSets, commit and merge the deletion of:
- `argo-apps/base.yml`
- `argo-apps/auxbot.yaml`
- `argo-apps/atlantis.yaml`
- `argo-apps/cloudflare-tunnel.yaml`
- `argo-apps/sample-app-oci.yaml`
- `argo-apps/auxarmormy-postgres.yaml`

Because `base.yml` does not have automated prune enabled, removing it from Git will not cascade-delete child Applications.

After the merge, manually delete the stale `base-app` Application object from ArgoCD if it still appears:
```bash
argocd app delete base-app --cascade=false
```

### Step 5: Final verification

Run a final health check:
```bash
argocd app list
```

Ensure all Applications remain `Synced` and `Healthy`. Confirm that:
- The `apps` ApplicationSet manages apps across all clusters
- `argo-cd` Application continues to manage itself

## Rollback

If anything goes wrong during the migration, follow these steps to revert:

1. **Restore deleted files:** Revert the commit that removed `argo-apps/base.yml` and the old Application manifests.
2. **Disable ApplicationSets:** Remove or comment out the `bootstrap.applicationSets` block in `charts/argocd/values.yaml` and sync.
3. **Delete ApplicationSet:**
   ```bash
   kubectl delete applicationset apps -n argocd
   ```
4. **Re-sync base.yml:** Manually sync the `base-app` Application in ArgoCD so it recreates any missing child Applications.

## Post-Migration Structure

After migration, the repository layout is:

```
argo-apps/
  argocd.yaml          # Self-managed ArgoCD Application
apps/
  auxbot/
    local-auxbot.yaml
  atlantis/
    local-atlantis.yaml
  cloudflare-tunnel/
    local-cloudflare-tunnel.yaml
  sample-app/
    oci-sample-app.yaml
  postgresql/
    oci-auxarmormy-postgres.yaml
charts/
  argocd/
    templates/
      applicationset.yaml
```
