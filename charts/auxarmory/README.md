# auxarmory

Umbrella Helm chart for AuxArmory on Kubernetes.

## Components

This chart deploys:

- `web`
- `auth`
- `api`
- `worker-service`
- local `postgresql` dependency
- local `redis` dependency
- Argo Image Updater config for the four runtime images
- label-based `NetworkPolicy` resources

Public routing is expected to come from the shared Cloudflare Tunnel managed in `/home/nixos/Documents/infra-tofu`.

Recommended hostnames:

- `armory.rger.dev`
- `auth.armory.rger.dev`
- `api.armory.rger.dev`

## 1Password Layout

Create these 1Password items and point `values.yaml` at their item paths.
The current `values.yaml` uses placeholder item paths, so fill those in before rollout.

### Shared item

- `DATABASE_URL`
- `REDIS_URL`
- `INTERNAL_API_TOKEN`

### Web item

- `VITE_SENTRY_DSN`

### Auth item

- `BETTER_AUTH_SECRET`
- `SENTRY_DSN`
- `BATTLENET_CLIENT_ID`
- `BATTLENET_CLIENT_SECRET`
- `WARCRAFTLOGS_CLIENT_ID`
- `WARCRAFTLOGS_CLIENT_SECRET`

### API item

- `SENTRY_DSN`

### Worker item

- `SENTRY_DSN`
- `BATTLENET_CLIENT_ID`
- `BATTLENET_CLIENT_SECRET`
- `BATTLE_NET_ACCOUNT_TOKEN`

### Postgres item

- `POSTGRES_PASSWORD`

## Migration Hook

The migration hook is present but disabled by default through `migration.enabled=false`.

The intended execution path is to reuse the `api` image as an ArgoCD `PreSync` Job once that image is confirmed to support:

```bash
pnpm --filter @auxarmory/db db:migrate
```

If the current image cannot run that command as-is, the next step is to file the upstream issue captured in the deployment plan before enabling the hook here.

## Validation

```bash
helm dependency update charts/auxarmory
helm lint charts/auxarmory
helm template charts/auxarmory | kubectl apply --dry-run=client -f -
```
