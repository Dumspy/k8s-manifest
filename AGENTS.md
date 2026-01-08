# AGENTS.md - Coding Agent Guidelines

This document provides guidelines for AI coding agents working in this Kubernetes GitOps repository.

## Project Overview

**Type:** Kubernetes Infrastructure-as-Code (GitOps)
**Stack:** Helm 3, ArgoCD, 1Password Operator, YAML
**Repository:** github.com/Dumspy/k8s-manifest

### Structure
```
k8s-manifest/
├── argo-apps/          # ArgoCD Application manifests
│   ├── base.yml        # App-of-apps pattern base
│   ├── argocd.yaml     # Self-managed ArgoCD
│   └── auxbot.yaml     # Auxbot application
└── charts/             # Helm charts
    ├── argocd/         # ArgoCD wrapper chart (v0.2.7)
    └── auxbot/         # Custom auxbot chart (v0.1.3)
```

## Build, Lint, and Test Commands

### Helm Chart Operations

```bash
# Lint charts (check for issues)
helm lint charts/argocd
helm lint charts/auxbot

# Template charts (render without installing)
helm template charts/argocd
helm template charts/auxbot
helm template argocd charts/argocd -n argocd  # with release name

# Update dependencies
helm dependency update charts/argocd

# Package charts
helm package charts/argocd
helm package charts/auxbot

# Validate with dry-run
helm install test-release charts/auxbot --dry-run --debug
```

### Kubernetes Validation

```bash
# Validate YAML syntax (client-side)
kubectl apply --dry-run=client -f argo-apps/

# Validate against cluster (server-side, recommended)
kubectl apply --dry-run=server -f argo-apps/

# Validate rendered Helm templates
helm template charts/auxbot | kubectl apply --dry-run=client -f -

# Validate single file
kubectl apply --dry-run=client -f argo-apps/auxbot.yaml
```

### Testing Strategy

Since this is an infrastructure repository, testing focuses on validation:

1. **Syntax validation:** `helm lint` and `kubectl apply --dry-run`
2. **Template rendering:** `helm template` to verify output
3. **ArgoCD validation:** Check sync status after commit
4. **Manual verification:** Observe Slack notifications for deployment status

**No unit tests or test frameworks are present in this repository.**

## Code Style Guidelines

### YAML Formatting

**Indentation:** 2 spaces (YAML standard)
```yaml
# Correct
metadata:
  name: example
  labels:
    app: myapp

# Incorrect
metadata:
    name: example  # 4 spaces - wrong
```

**Line length:** Max 120 characters
**Line endings:** Unix-style (LF)
**Trailing whitespace:** Remove all trailing whitespace

### Quotes

- **String values:** Use quotes when necessary for special characters, numbers as strings, or clarity
- **Boolean values:** Unquoted (`true`, `false`, not `"true"`)
- **Numeric values:** Unquoted (`8080`, not `"8080"`)

```yaml
# Good
name: my-service
port: 8080
enabled: true
version: "1.0"  # Quote when string representation needed

# Avoid
name: "my-service"  # Unnecessary quotes
port: "8080"        # This becomes a string, not a number
```

### Naming Conventions

**Resources:**
- Use lowercase with hyphens: `my-service`, `auxbot-controller`
- Be descriptive and consistent: `auxbot-deployment`, not `dep1`

**Helm Charts:**
- Chart names: lowercase, hyphens (e.g., `auxbot`, `argocd`)
- Template files: descriptive, resource type (e.g., `deployment.yaml`, `rbac.yaml`)

**Labels:**
```yaml
# Standard Kubernetes labels
app.kubernetes.io/name: auxbot
app.kubernetes.io/instance: auxbot-production
app.kubernetes.io/version: "0.1.3"
app.kubernetes.io/component: controller
app.kubernetes.io/part-of: auxbot
app.kubernetes.io/managed-by: Helm
```

### Helm Templates

**Values references:**
```yaml
# Good - clear hierarchy
{{ .Values.controller.image.repository }}

# Avoid deeply nested or unclear references
{{ .Values.a.b.c.d.e.f }}
```

**Conditionals:**
```yaml
# Use proper spacing
{{- if .Values.enabled }}
enabled: true
{{- end }}

# Not: {{-if .Values.enabled}}  # Missing space
```

**Comments:**
```yaml
# Provide context for non-obvious values
# ArgoCD requires insecure mode for NodePort without TLS
server:
  insecure: "true"
```

### Version Management

**Chart versions:**
- Follow SemVer (e.g., `0.1.3`)
- Bump version in `Chart.yaml` for every change
- Update `appVersion` when application version changes

**Container images:**
- Avoid `:latest` in production
- Use specific tags or digests: `ghcr.io/dumspy/auxbot-controller:v1.2.3`

```yaml
# Good
image:
  repository: ghcr.io/dumspy/auxbot-controller
  tag: "v1.2.3"

# Avoid in production
image:
  repository: ghcr.io/dumspy/auxbot-controller
  tag: latest  # Non-deterministic
```

## Error Handling and Security

### Secrets Management

**Always use 1Password Operator for secrets:**
```yaml
apiVersion: onepassword.com/v1
kind: OnePasswordItem
metadata:
  name: auxbot-secrets
spec:
  itemPath: "vaults/your-vault-id/items/your-item-id"
```

**Never commit secrets to Git:**
- No hardcoded tokens, passwords, API keys
- No `.env` files with credentials
- Use 1Password references in manifests

### Resource Limits

**Always define resource requests and limits:**
```yaml
resources:
  requests:
    memory: "256Mi"
    cpu: "100m"
  limits:
    memory: "512Mi"
    cpu: "500m"
```

### Health Checks

**Define liveness and readiness probes:**
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
```

## GitOps Workflow

### Making Changes

1. **Create feature branch:** `git checkout -b feature/description`
2. **Edit charts or manifests**
3. **Validate locally:** Run lint and dry-run commands
4. **Commit changes:** Clear, descriptive commit messages
5. **Push to remote:** `git push origin feature/description`
6. **ArgoCD auto-syncs** when merged to `main` branch

### Commit Messages

Follow conventional commits format:
```
feat(auxbot): add readiness probe
fix(argocd): correct notification template syntax
chore(charts): bump auxbot version to 0.1.4
docs: update README with setup instructions
```

### Testing Changes

Before committing:
```bash
# 1. Lint the chart
helm lint charts/auxbot

# 2. Render templates
helm template auxbot charts/auxbot -n production

# 3. Validate against cluster
helm template auxbot charts/auxbot -n production | kubectl apply --dry-run=server -f -

# 4. Check for YAML syntax errors
kubectl apply --dry-run=client -f argo-apps/auxbot.yaml
```

## Common Tasks

### Adding a New Application

1. Create Helm chart in `charts/new-app/`
2. Create ArgoCD application manifest in `argo-apps/new-app.yaml`
3. Reference chart in ArgoCD manifest
4. Validate and commit
5. ArgoCD will auto-sync from main branch

### Updating Application

1. Modify `charts/app/values.yaml` or templates
2. Bump chart version in `Chart.yaml`
3. Validate with `helm lint` and `kubectl apply --dry-run`
4. Commit and push
5. Monitor Slack notifications for deployment status

### Debugging ArgoCD Issues

```bash
# Check application status
kubectl get applications -n argocd

# View application details
kubectl describe application auxbot -n argocd

# Check ArgoCD logs
kubectl logs -n argocd deployment/argocd-server
```

## Important Notes

- **No CI/CD pipelines exist:** All validation must be done manually before committing
- **Slack notifications configured:** Deployment events sent to Slack automatically
- **Self-healing enabled:** ArgoCD will auto-correct drift from Git state
- **Main branch is production:** All commits to main deploy immediately
- **1Password Operator required:** Cluster must have operator installed for secrets
