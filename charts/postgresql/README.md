# postgresql

This chart deploys a single PostgreSQL instance with persistent storage.

It includes:

- A PostgreSQL `StatefulSet`
- Internal services for the database pod
- A `OnePasswordItem` for the database password

Shared chart defaults live in `values.yaml`. Deployment-specific overrides live in `deployments/*.yaml`.

## Deployment Overrides

Create one override file per database deployment under `deployments/` and reference it from ArgoCD with `valueFiles`.

Example override for the OCI `auxarmormy` deployment:

```yaml
database:
  name: auxarmormy
  user: auxarmormy

onePassword:
  itemPath: vaults/p364xm4f4uub6cfyzweulklgwa/items/knuooys23mo5jluzxkct5fgeyi
```

This keeps shared storage, resource, and image defaults in the chart while letting each deployment use its own database name, user, and secret item.

## 1Password Requirements

The chart creates a `OnePasswordItem` named `<release-name>-secret` using:

- `onePassword.itemPath`, typically from a deployment override in `deployments/*.yaml`

That 1Password item must expose this field:

- `password`: password for the PostgreSQL user defined by `database.user`

## How The Secret Is Used

The `password` key is consumed by:

- PostgreSQL startup, as `POSTGRES_PASSWORD`
- The password sync hook in the StatefulSet

## Expected 1Password Item Shape

At minimum, the referenced 1Password item should include a field named `password`.

Example:

```text
Item: postgres-db
Field: password = <strong password>
```

## Template Fallback

If `onePassword.itemPath` is omitted, the template falls back to:

```yaml
onePassword:
  itemPath: vaults/ksplpxkiblaftafiljqytehbcy/items/postgres-cluster
```

`database.name`, `database.user`, and `onePassword.itemPath` are typically set per deployment in `deployments/*.yaml`.

Example ArgoCD values files:

```yaml
valueFiles:
  - values.yaml
  - deployments/auxarmormy.yaml
```

## Services

- `{{ .Release.Name }}-headless` supports the StatefulSet network identity.
- `{{ .Release.Name }}-direct` is the stable client service for PostgreSQL access.
