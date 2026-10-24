# Security review

2026-10-24. Single-owner homelab: Helm charts synced by Argo CD from `main`, secrets via the 1Password Operator. The person who can merge here already has the cluster. Findings below are things that bite if a GitHub credential, a GHCR push, or a 1Password item leaks, or if `Dumspy/infra-tofu` is ever writable by someone else. They are not an outside-attacker-in-the-cluster story.

No live secret is committed. The tree and full git history have no private keys and no cloud, GitHub, or Slack tokens. Old Burrito `stringData` was only `provider: github` and a repo URL. 1Password vault and item IDs are identifiers, not credentials. Nothing needs rotation because it was in git.

## Worth doing later

### Atlantis will apply without review, and a PR can define the workflow. Medium.

`charts/atlantis/values.yaml:6` limits Atlantis to `github.com/Dumspy/infra-tofu`. That part is right. The server repo config does not match the rest of a one-person setup:

- `charts/atlantis/values.yaml:18-25` uses `id: /.*/`, `apply_requirements: []`, `allowed_overrides: [workflow, apply_requirements]`, and `allow_custom_workflows: true`.
- Provider credentials are env vars from `opentofu-provider-secrets` (`values.yaml:88-90`, `charts/atlantis/templates/secrets.yaml:11-19`).
- The GitHub App key is mounted at `/var/secrets/github-app/key.pem` (`values.yaml:14`, `values.yaml:52-64`), and `--write-git-creds` (`values.yaml:94-96`) writes VCS credentials onto the pod.

If you are the only person who can comment on that repo, this is you applying your own infra. It matters if the repo is public or you add a collaborator: a comment can apply with no approval, and an `atlantis.yaml` in the PR can `run` arbitrary commands that see the cloud credentials and the GitHub App key. The webhook secret is in 1Password (`values.yaml:47-50`), not git.

Leave it until you know `infra-tofu` does not rely on custom workflows. Then set `apply_requirements: [approved, mergeable]`, turn custom workflows off, and point `id` at that one repo. The Service is already ClusterIP (`values.yaml:67-69`). The upstream chart defaults to NodePort; do not drop that override.

### Auxbot deploys `latest` into the same namespace as the tunnel token. Medium.

`charts/auxbot/values.yaml:2-5` is `ghcr.io/dumspy/auxbot-controller:latest` with `pullPolicy: Always`. The image updater follows that tag (`charts/auxbot/templates/image-updater.yaml:11-18`), and the ApplicationSet will not revert the parameter (`charts/argocd/templates/applicationset.yaml:10-15`). Workers are `ghcr.io/dumspy/auxbot-worker:latest` (`values.yaml:22`) and are not even updated by the image updater.

The controller Role can create pods in its namespace (`values.yaml:47-55`). Auxbot and the tunnel both use `production` (`apps/auxbot/local-auxbot.yaml:2-3`, `apps/cloudflare-tunnel/local-cloudflare-tunnel.yaml:2-3`), so a bad controller image can mount the tunnel token. Pin both images. Moving the tunnel to its own namespace is the other half, whenever you next touch it. A `securityContext` on the controller is optional and easy to get wrong without knowing the image user; skipped on purpose.

### The OCI cluster credential is a static cluster-admin token. Medium, and expected.

`unmanaged/oci-cluster/argocd-serviceaccount.yaml:17-21` is `*` on every resource and non-resource URL. `argocd-serviceaccount.yaml:37-44` asks Kubernetes for a non-expiring ServiceAccount token, which `charts/argocd/templates/cluster-secret.yaml` syncs from 1Password. Argo CD on the home cluster is also cluster-admin via the upstream chart. That is how this setup manages the other cluster.

Do not rebuild it. The practical note is that the 1Password item and the Secret in the `argocd` namespace are full admin on OCI until you delete the token Secret and update the item. This PR only stops that ServiceAccount from automounting into a future pod. The file is unmanaged, so it does nothing until you apply it, and applying it does not rotate the token.

### CI. Low.

`.github/workflows/ci.yaml` has no `permissions` block and pins `actions/checkout`, `cachix/install-nix-action`, and `cachix/cachix-action` to tags. `nix profile add nixpkgs#devenv` does not follow `devenv.lock`. Chart dependencies themselves are digest-pinned. Not edited here; another change is already on the workflow. For this repo the annoying case is a compromised action plus a token that can push `main`, which Argo CD would sync. `permissions: contents: read` and SHA pins are enough.

## Fine for this homelab

- GitHub SSO does not restrict the org (`charts/argocd/values.yaml:37-47`). `policy.default` is empty (`values.yaml:50-55`), so a random GitHub user who logs in gets no role. Admin is your own email. The local admin user is still on via the chart default. Leave it.
- `server.insecure: true` (`values.yaml:48-49`) behind the tunnel is normal. The Service is ClusterIP.
- The ApplicationSet trusts `apps/*/*.yaml` for project, revision, cluster, and namespace (`charts/argocd/templates/applicationset.yaml:16-56`), and everything uses the `default` project. You are the only committer. An AppProject would be ceremony until someone else can merge.
- The PostgreSQL chart is not deployed. If you use it again: the role is forced to `SUPERUSER` (`charts/postgresql/templates/statefulset.yaml:60-66`), the Service has no NetworkPolicy (`charts/postgresql/templates/service-postgres.yaml`), and the image is `postgres:16.9-alpine` (`charts/postgresql/values.yaml:3-5`), which is old. Also, omitting `onePassword.itemPath` falls back to a shared item id (`charts/postgresql/templates/1password-item.yaml:11`). None of that is worth a change while nothing runs it.
- Redis password on the process command line (`charts/auxbot/templates/redis-statefulset.yaml:37-38`), tag pins instead of digests, no cluster-wide default-deny, no Argo CD resource limits, sync errors copied to Slack. Real in a larger cluster, not worth the outage risk here.

## What this PR actually changes

Kept, because they do not change how the process serves traffic:

- cloudflared does not mount a ServiceAccount token (`charts/cloudflare-tunnel/templates/deployment.yaml:20`). Chart `0.2.1`.
- Redis does not mount one either (`charts/auxbot/templates/redis-statefulset.yaml:20`). The existing ingress allowlist is unchanged. Chart `0.1.8`.
- PostgreSQL does not mount one (`charts/postgresql/templates/statefulset.yaml:22`). Nothing deploys this chart today. Chart `0.3.4`.
- The Argo CD app tracks `main` instead of `HEAD` (`argo-apps/argocd.yaml:21`).
- `argocd-manager` will not automount its token (`unmanaged/oci-cluster/argocd-serviceaccount.yaml:11`). Apply by hand if you want it on the OCI cluster.

Reverted after review, because they could break the only ingress or the cache for little gain on a homelab:

- cloudflared read-only root, explicit uid 65532, scratch volumes, a dedicated ServiceAccount, and a deny-all ingress NetworkPolicy. The image is already non-root. A bad write path or a metrics scrape you actually use would drop the tunnel.
- Redis deny-all egress. Ingress from the controller was already the useful control.
