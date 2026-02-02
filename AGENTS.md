# AGENTS.md

Kubernetes Infrastructure-as-Code using Helm 3 and ArgoCD.

## Quick Commands

```bash
# Validate before committing
helm lint charts/<chart-name>
helm template charts/<chart-name> | kubectl apply --dry-run=client -f -
```

## Git Workflow

- **Simple changes**: Commit directly to main
- **Complex changes**: Feature branch → PR → merge

## Standards

### YAML Formatting
- 2 spaces indentation
- Max 120 character lines
- Quote strings only when needed: `version: "1.0"`
- Don't quote numbers/booleans: `port: 8080`, `enabled: true`

### Naming
- Charts/resources: lowercase-hyphens (`auxbot-controller`)
- Template files: descriptive (`deployment.yaml`)

### Chart.yaml
```yaml
version: 0.1.4      # Bump for every change
appVersion: "1.2.3"  # Update when app changes
```

### Container Images
```yaml
# Good: specific tag
tag: "v1.2.3"

# Bad: non-deterministic
tag: latest
```

### Helm Templates
```yaml
{{ .Values.controller.image.repository }}  # Clear hierarchy
{{- if .Values.enabled }}                   # Proper spacing
```

## Secrets Management

**ALL secrets MUST use the 1Password Operator. No exceptions.**

```yaml
apiVersion: onepassword.com/v1
kind: OnePasswordItem
metadata:
  name: app-secrets
spec:
  itemPath: "vaults/vault-name/items/item-name"
```

**Never commit:**
- Hardcoded tokens, passwords, API keys
- `.env` files with credentials
- Kubernetes Secrets with `data:` or `stringData:` fields

## Resources & Health Checks

### Required for All Containers
```yaml
resources:
  requests:
    memory: "256Mi"
    cpu: "100m"
  limits:
    memory: "512Mi"
    cpu: "500m"

livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
```

## Commit Messages

```
feat(auxbot): add readiness probe
fix(argocd): correct notification template
chore(charts): bump auxbot to 0.1.4
```

## Adding an Application

1. Create chart: `mkdir charts/new-app` (Chart.yaml, values.yaml, templates/)
2. Create ArgoCD app: `argo-apps/new-app.yaml`
3. Validate: `helm lint && kubectl apply --dry-run=client`
4. Commit → ArgoCD auto-syncs from main
