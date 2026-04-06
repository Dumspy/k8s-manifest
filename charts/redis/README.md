# redis

This chart deploys a single Redis instance with persistent storage.

It includes:

- A Redis `StatefulSet`
- A headless service for the StatefulSet network identity
- A stable ClusterIP client service

Default scheduling targets the same `role: database` node pool as PostgreSQL.

When used as a dependency inside an umbrella chart, set `fullnameOverride` so the client service name is predictable, for example:

```yaml
redis:
  fullnameOverride: auxarmory-redis
```

That gives you a stable in-cluster endpoint such as `redis://auxarmory-redis:6379`.
