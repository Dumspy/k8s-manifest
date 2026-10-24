# Security review

Review date: 2026-10-24. Scope is this repository: Helm 3 charts `argocd`, `atlantis`, `auxbot`, `cloudflare-tunnel`, and `postgresql`; Argo CD Application and ApplicationSet wiring; unmanaged manifests; CI. Secrets are supposed to come from the 1Password Operator.

This was a static review of the tree and of every git blob reachable from all refs. Nothing was checked against a live cluster, so tunnel ingress rules, Pod Security admission, and the visibility of `Dumspy/infra-tofu` are not confirmed here. `.github/workflows` was not modified; another change is already editing that workflow.

## Critical

No committed live secret needs rotation.

The working tree has no `Secret` `data` or `stringData`, no private keys, and no cloud, GitHub, or Slack tokens. A scan of all 352 git blobs (private-key headers, `AKIA` access keys, `ghp_` / `github_pat_` tokens, Slack tokens, JWTs, and password or token assignments) found the same. The only historical `stringData` was in the removed Burrito chart and held `provider: github` plus a repository URL, not credentials.

1Password vault and item IDs are committed. Those identify items; they are not the item contents. They are a low finding below. The high findings are about credentials that already live in the clusters (Atlantis environment, tunnel token, Argo CD cluster token), not about values stored in git.

## Remediated in this PR

These were clear-cut and low risk for the running workloads. Chart versions were bumped where a chart changed.

### R1. cloudflared ran without a container security context and published metrics to the cluster

**Severity:** Medium, fixed.

**Evidence:** `charts/cloudflare-tunnel/templates/deployment.yaml:20-44`, `charts/cloudflare-tunnel/templates/serviceaccount.yaml:8`, `charts/cloudflare-tunnel/templates/networkpolicy.yaml:11-16`.

**Impact:** The image is distroless and already `USER 65532`, but the pod did not say so. A container escape or a future image default of root would have kept every capability, writable root, and privilege escalation. Metrics listen on `0.0.0.0:2000` (`deployment.yaml:59-60`) with no Service in front of them, so any pod could scrape tunnel metrics. The default ServiceAccount token was mounted even though cloudflared does not call the Kubernetes API.

**Fix:** The pod now runs as uid/gid 65532, drops all capabilities, sets `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, and `seccompProfile: RuntimeDefault`. Writable `emptyDir` volumes cover `/tmp` and `/home/nonroot`. A dedicated ServiceAccount has `automountServiceAccountToken: false`. A NetworkPolicy denies all ingress. Kubelet probes are not subject to NetworkPolicy, so `/ready` still works. The existing `net.ipv4.ping_group_range` sysctl is unchanged and matches uid 65532.

**Residual risk:** If this build writes anywhere other than `/tmp` or `/home/nonroot`, the pod will not become ready and the tunnel will drop when the chart syncs. Token mode does not need a credentials file, and upstream distroless images are built for this. Watch the rollout. Metrics scrapes from another namespace now fail until an explicit ingress rule is added. Chart version `0.2.1`.

### R2. Redis mounted an API token and had unrestricted egress

**Severity:** Low, fixed.

**Evidence:** `charts/auxbot/templates/redis-statefulset.yaml:20`, `charts/auxbot/templates/redis-networkpolicy.yaml:11-25`.

**Impact:** Redis does not call the API. A compromised Redis process still had a ServiceAccount token for the namespace and could open egress. Ingress was already limited to the controller.

**Fix:** `automountServiceAccountToken: false` on the pod. The NetworkPolicy now denies all egress. Chart version `0.1.8`.

### R3. PostgreSQL mounted an API token

**Severity:** Low, fixed.

**Evidence:** `charts/postgresql/templates/statefulset.yaml:22`.

**Impact:** The database does not call the API. The mounted default token was an unnecessary credential in a process that also holds `POSTGRES_PASSWORD`.

**Fix:** `automountServiceAccountToken: false`. No security context was added: `postgres:16.9-alpine` starts as root and drops to uid 70, and forcing `runAsNonRoot` can break first-time volume setup. Chart version `0.3.4`.

### R4. The OCI Argo CD manager ServiceAccount mounted its cluster-admin token

**Severity:** Low, fixed in git only.

**Evidence:** `unmanaged/oci-cluster/argocd-serviceaccount.yaml:11`, matching example in `unmanaged/README.md:49`.

**Impact:** The ServiceAccount exists so a separately issued token Secret can be copied into 1Password. It is not a pod identity. With the default automount, any future pod that used `argocd-manager` would receive the cluster-admin token.

**Fix:** `automountServiceAccountToken: false` on the ServiceAccount. This does not delete or rotate the existing `argocd-manager-token` Secret, and it does not shrink the ClusterRole. Unmanaged manifests are not synced by Argo CD; someone has to apply this file on the OCI cluster. The wildcard ClusterRole remains finding H2.

### R5. The Argo CD self-management Application tracked `HEAD`

**Severity:** Low, fixed.

**Evidence:** `argo-apps/argocd.yaml:21`.

**Impact:** `HEAD` follows the repository default branch. The app files under `apps/` already pin `main`. A default-branch change would have moved Argo CD itself.

**Fix:** `targetRevision: main`. The same pin was applied to the copy-paste examples in `unmanaged/README.md` and `charts/argocd/README.md`. The dependency table in that README was also updated to the chart versions in `charts/argocd/Chart.yaml` (10.10.2 and image-updater 1.3.1).

## High

### H1. Atlantis can run unapproved, repo-defined commands with infrastructure credentials

**Evidence:**

- Allowlist is one repo: `charts/atlantis/values.yaml:6`
- Server repo config matches every repo id, requires nothing before apply, and allows the repo to replace that policy and define workflows: `charts/atlantis/values.yaml:18-25`
- Provider credentials are injected into the environment: `charts/atlantis/values.yaml:88-90` and `charts/atlantis/templates/secrets.yaml:11-19`
- GitHub App private key is mounted at `/var/secrets/github-app/key.pem`: `charts/atlantis/values.yaml:14` and `charts/atlantis/values.yaml:52-64`
- `--write-git-creds` writes VCS credentials onto the pod filesystem: `charts/atlantis/values.yaml:94-96`
- Webhook secret is taken from 1Password key `github_secret`: `charts/atlantis/values.yaml:47-50`
- No `--gh-team-allowlist` and no user allowlist in `extraArgs`

**Impact:** Atlantis is the automation identity for OpenTofu. With `apply_requirements: []`, a commenter can apply without an approving review. With `allow_custom_workflows: true` and `allowed_overrides: [workflow, apply_requirements]`, an `atlantis.yaml` in a pull request can `run` arbitrary commands in that pod. Those commands see `opentofu-provider-secrets`, the GitHub App private key, and the git credentials written by `--write-git-creds`. That is infrastructure-admin and GitHub App compromise, not just a bad plan.

Who can trigger it: GitHub delivers comments through the webhook, and the webhook secret is not in git. Upstream defaults still refuse fork PRs and draft PRs. There is no team or user allowlist in this chart, so anyone who can comment on `Dumspy/infra-tofu` can plan and apply. If that repo is public, or if comment access is broader than the people who should change infrastructure, treat this as a standing admin backdoor. `orgAllowlist` does limit *which* repo, and that part is right. The server-side `id: /.*/` block becomes the policy for every repo later added to the allowlist.

The Service is ClusterIP (`charts/atlantis/values.yaml:67-69`) and ingress is disabled. `ATLANTIS_ATLANTIS_URL` is `https://atlantis.rger.dev` (`values.yaml:13`), so the UI is expected to be published by the tunnel. Tunnel routes are not in this repo (H6).

**Recommendation:** Do this in `infra-tofu` and this chart together, not as a silent sync.

- Set `apply_requirements: [approved, mergeable]`.
- Set `allow_custom_workflows: false` and `allowed_overrides: []` unless a reviewed server-side workflow is required.
- Change `id: /.*/` to `github.com/Dumspy/infra-tofu` so a wider allowlist does not inherit this policy.
- Set a GitHub team allowlist for who may comment `atlantis apply`.
- Keep the webhook secret in 1Password and confirm GitHub is configured to sign webhooks with it.
- Drop `--write-git-creds` unless Atlantis must push commits.
- Put Cloudflare Access (or equivalent) in front of `atlantis.rger.dev`.
- Set `atlantis.serviceAccount.mount: false` after confirming OpenTofu does not use in-cluster Kubernetes auth. Chart 6.16.1 defaults `serviceAccount.mount` to `true`, and this values file does not override it.
- Add a container `securityContext` with `runAsNonRoot`, `allowPrivilegeEscalation: false`, and `capabilities.drop: ["ALL"]`. The chart already runs the pod as uid 100. Do not set `readOnlyRootFilesystem` until plan/apply write paths (`/atlantis`, provider plugin cache) are mounted as volumes. An earlier `containerSecurityContext` block was removed as unused; on chart 6.16.1 that key is real and currently `{}`.

Not changed here: flipping apply requirements or custom workflows will stop the current workflow if `infra-tofu` depends on them.

### H2. The OCI cluster credential is a non-expiring cluster-admin token

**Evidence:** `unmanaged/oci-cluster/argocd-serviceaccount.yaml:17-21` (apiGroups, resources, and verbs are `*`, plus all non-resource URLs) and `unmanaged/oci-cluster/argocd-serviceaccount.yaml:37-44` (`kubernetes.io/service-account-token`). The same shape is the documented template at `unmanaged/README.md:56-59` and `unmanaged/README.md:75-82`. The token is synced into the Argo CD cluster by `charts/argocd/templates/cluster-secret.yaml:1-9`.

**Impact:** This is the credential Argo CD uses for the whole OCI cluster. A legacy service-account token Secret does not expire. Anyone who can read that Secret in the `argocd` namespace, or the 1Password item `m7oer7uouziqmucown5hau6zk4`, can act as cluster-admin on OCI until the Secret is deleted and the item updated. The in-cluster Argo CD install is also cluster-admin: chart 10.10.2 defaults `createClusterRoles: true`, and `charts/argocd/values.yaml` does not narrow it. That part is normal for Argo CD. The extra problem is the static token on the second cluster, and the README teaching every new cluster to copy the wildcard role.

**Recommendation:** Keep Argo CD's in-cluster controller as cluster-admin. For OCI, prefer a short-lived credential or an exec/identity provider if one exists for that cluster. If the bearer token has to stay, put an expiry process around it: recreate `argocd-manager-token`, update the 1Password item, and confirm Argo CD reconnects. Do not grant `nonResourceURLs: ["*"]` unless something actually calls those endpoints. Apply the automount change from R4 on the cluster; that change does not rotate this token.

Not changed here: shrinking this ClusterRole from git can break sync of arbitrary app resources, and the live object is not managed by Argo CD.

### H3. Production auxbot tracks `latest`, and its controller can mint pods beside the tunnel token

**Evidence:**

- Controller tag `latest` and `pullPolicy: Always`: `charts/auxbot/values.yaml:2-5`
- Worker image `ghcr.io/dumspy/auxbot-worker:latest`: `charts/auxbot/values.yaml:22`
- Image updater follows that tag with strategy `digest`: `charts/auxbot/templates/image-updater.yaml:11-18`
- ApplicationSet ignores helm parameter and values drift, so self-heal will not put the tag back: `charts/argocd/templates/applicationset.yaml:10-15`
- Controller ServiceAccount can create, update, and delete pods, services, and deployments in its namespace: `charts/auxbot/values.yaml:47-55`, bound by `charts/auxbot/templates/rbac.yaml:10-34`
- Controller and tunnel share `namespace: production`: `apps/auxbot/local-auxbot.yaml:2-3`, `apps/cloudflare-tunnel/local-cloudflare-tunnel.yaml:2-3`
- Controller has no `securityContext` and must keep its API token: `charts/auxbot/templates/deployment.yaml:20-24`
- Controller Service is ClusterIP but has no NetworkPolicy: `charts/auxbot/templates/service.yaml:8-18`

**Impact:** `updateStrategy: digest` still tracks the tag it is given. Every push to `ghcr.io/dumspy/auxbot-controller:latest` becomes the production Deployment, and a pod restart pulls `latest` even without the updater. The worker tag is not in the ImageUpdater at all; the controller will run whatever `latest` is when it creates a worker.

Creating a pod does not require `get` on secrets. A compromised controller or worker can start a pod that mounts `cloudflare-tunnel-secret` (the tunnel token) and the auxbot Discord and Sentry secret. Both live in `production`. There is no Pod Security label in this repo, so those pods are not forced to drop privileges. The controller's own API and gRPC ports are reachable from any pod in the cluster.

**Recommendation:**

- Pin the controller and the worker to immutable tags or digests. Point the ImageUpdater at a semver range, not at `latest`.
- Move `cloudflare-tunnel` to its own namespace so the auxbot Role cannot mount the tunnel token.
- After H3's image pin is in place, add a controller `securityContext` (`runAsNonRoot`, drop all capabilities, `allowPrivilegeEscalation: false`, seccomp). Do not set `readOnlyRootFilesystem` until the image's write paths are known. An unmerged branch proposed uid 65532 and a read-only root; it never landed, so it was treated as unvalidated.
- Add a NetworkPolicy that allows only the clients that actually call ports 3000 and 50051.
- Label the namespace with a Pod Security admission level once the workloads in it satisfy it. The tunnel chart now matches the restricted profile except that safe sysctl; the controller does not.

Not changed here: retagging `latest` or adding `runAsNonRoot` can crash the controller on the next sync.

### H4. The ApplicationSet trusts app files for project, revision, cluster, and namespace

**Evidence:** `charts/argocd/templates/applicationset.yaml:16-56` and `charts/argocd/values.yaml:3-7`. Every current app sets `project: default` (for example `apps/auxbot/local-auxbot.yaml:4`). There is no `AppProject` manifest in the repo. The self-managed app also uses the default project: `argo-apps/argocd.yaml:17`.

**Impact:** The generator only reads `apps/*/*.yaml` on `main`, and `repoURL` is fixed to this repository. That is the right trust boundary for *which* repo. The file contents still choose `project`, `chart_path`, `targetRevision`, `cluster`, and `namespace`. Sync is automated with prune, self-heal, and `CreateNamespace=true`. The built-in `default` project allows every repo, every cluster, and cluster-scoped resource kinds.

A pull request that changes only an app file can set `targetRevision` to another branch of this repo. Reviewers who look at `main` do not see the chart that will be applied. Prune plus `CreateNamespace` means that file can also delete resources the chart no longer renders and can create namespaces. `ignoreApplicationDifferences` (`applicationset.yaml:10-15`) then lets a live edit of helm values or parameters stick; self-heal will not revert an image the updater, or an attacker with patch access to the Application, wrote in.

**Recommendation:**

- Render `targetRevision` from the ApplicationSet branch (`main`), not from `{{ .targetRevision }}`, or allow only refs that match a reviewed pattern.
- Stop templating `project` from the file. Create an AppProject whose `sourceRepos` is only `https://github.com/Dumspy/k8s-manifest`, whose destinations are the known cluster and namespace pairs, and whose `clusterResourceWhitelist` is empty unless a chart truly needs cluster-scoped objects.
- Narrow `ignoreApplicationDifferences` to the image-updater parameter keys instead of all helm values and parameters.

Not changed here: the app-file fields are the current contract, and locking them changes how every app is generated.

### H5. CI is an unpinned supply chain in front of an auto-synced cluster

**Evidence:** `.github/workflows/ci.yaml:1-26`. This file was not edited.

**Impact:** The workflow has no `permissions:` block, so the job token inherits the repository default. `actions/checkout@v5` persists that token in the git config. The job then runs three tag-pinned third-party actions (`actions/checkout@v5`, `cachix/install-nix-action@v31`, `cachix/cachix-action@v16`) and `nix profile add nixpkgs#devenv`, which follows the action's nixpkgs rather than `devenv.lock`. A moved tag or a compromised action runs in this workflow.

Argo CD syncs `main` automatically (`charts/argocd/templates/applicationset.yaml:51-56`, `argo-apps/argocd.yaml:28-31`). If the default token can push contents, a compromised CI step can push a chart to `main` and the cluster will apply it as cluster-admin (H2, H4). `pull_request_target` is not used, and no workflow `secrets` are passed through. That removes the fork-PR secret path; it does not pin the actions.

`devenv.lock` does pin nixpkgs (`rev` `42f17a57f4f6e33b3de3dca0a2a5ea5233169d02`) and devenv for `devenv shell`. `devenv.yaml` itself tracks `nixpkgs-unstable`. Chart dependencies are pinned by digest in `charts/argocd/Chart.lock` and `charts/atlantis/Chart.lock`, and `devenv.nix` builds them with `helm dependency build`, which checks that digest. Those pins are doing their job.

**Recommendation:** Leave the workflow edit to the change already in flight. The target shape is:

- `permissions: contents: read` at workflow scope
- actions pinned to full commit SHAs
- install devenv from the lockfile rev, not `nixpkgs#devenv` on a floating channel
- `persist-credentials: false` on checkout
- a secret scan (gitleaks or trufflehog) on pull requests
- no write token anywhere on this workflow

### H6. PostgreSQL is a superuser listener with no network policy, on an old image

**Evidence:**

- No `securityContext` on the pod or container: `charts/postgresql/templates/statefulset.yaml:21-28` (only the automount flag from R3)
- The chart user is altered to `LOGIN SUPERUSER` on every start: `charts/postgresql/templates/statefulset.yaml:60-66`
- Password is only `POSTGRES_PASSWORD` from 1Password: `charts/postgresql/templates/statefulset.yaml:42-46`
- Client Service has no type (ClusterIP) and there is no NetworkPolicy: `charts/postgresql/templates/service-postgres.yaml:1-13`
- Image is `postgres:16.9-alpine`: `charts/postgresql/values.yaml:3-5`
- No TLS settings anywhere in the chart

**Impact:** Nothing under `apps/` points at this chart today (the OCI auxarmormy app was removed). The chart is still the template for the next database. When it is deployed, any pod in the cluster can open TCP 5432. Authentication is a password, the role is superuser, and the postStart hook puts the password back to superuser if someone revokes it. The official image entrypoint expects to start as root and drop to uid 70 on Alpine (not uid 999). Docker Hub's scan summary for `16.9-alpine` shows a large vulnerability set (displayed totals 13 / 101 / 74 / 16 / 1 in Docker Hub's critical / high / medium / low / unknown order). That tag was last pushed more than a year before this review. Current `16-alpine` builds PostgreSQL 16.13. Those scan totals were not re-verified CVE by CVE.

The password also appears on the `psql` command line during the hook (`statefulset.yaml:65`), so it is visible in the process table for the duration of the hook.

**Recommendation:** Before the next deploy, add a NetworkPolicy that allows only the application namespace, create a non-superuser role for the application and stop re-granting `SUPERUSER` on start, bump the image to the current 16.x Alpine tag and then pin the digest, and terminate TLS if clients cross a node boundary. Add `seccompProfile: RuntimeDefault`, `allowPrivilegeEscalation: false`, and `capabilities.drop: ["ALL"]` without `runAsNonRoot` first; add `runAsUser: 70` only after checking that existing volume data is owned by uid 70. Do not set `readOnlyRootFilesystem` without emptyDirs for `/tmp` and `/var/run/postgresql`.

Not changed here: a version bump restarts the database, and a non-root or non-superuser change can refuse to boot an existing volume.

## Medium

### M1. Argo CD SSO is not bound to the GitHub org, and the local admin user is still on

**Evidence:** Dex GitHub connector has no `orgs` list: `charts/argocd/values.yaml:37-47`. `policy.default` is empty and the only admin binding is one personal mailbox: `charts/argocd/values.yaml:50-55`. `configs.cm` does not set `admin.enabled`, so chart 10.10.2 keeps the default `admin.enabled: true`. `server.insecure` is `true`: `charts/argocd/values.yaml:48-49`. The server Service type is ClusterIP (`charts/argocd/values.yaml:26-28`) and there is no NetworkPolicy.

**Impact:** Any GitHub account can finish OAuth. Empty `policy.default` means that account gets no role, which is the right outcome, and it is one values edit away from `role:readonly` for the world. Admin is a single Gmail address rather than a GitHub team. The local `admin` user still exists; its password is in `argocd-initial-admin-secret` and bypasses GitHub. `server.insecure` means session and API traffic are HTTP on the cluster network. That is acceptable only while Cloudflare terminates TLS and no other path reaches the Service. Any pod can open that HTTP port today.

`exec.enabled` defaults to false in this chart version and is not turned on. That part is fine.

**Recommendation:** Add the GitHub org (and team, if applicable) to the Dex connector. Bind admin to a GitHub team via `groups`, not a mailbox. After confirming SSO works, set `admin.enabled: "false"` and delete `argocd-initial-admin-secret`. Keep `server.insecure` only if the tunnel is the sole client, and add a NetworkPolicy that allows ingress from the tunnel namespace only.

Not changed here: disabling admin or tightening SSO can lock operators out if the Dex item or org name is wrong.

### M2. Tunnel routes and Access policy are not in git

**Evidence:** The tunnel is token-based and remotely managed. The only route hint in-repo is the public URL `https://atlantis.rger.dev` (`charts/atlantis/values.yaml:13`) and the Argo CD URL `https://argocd.rger.dev` inside notification templates (`charts/argocd/values.yaml:36` and `charts/argocd/values.yaml:90`). `charts/cloudflare-tunnel` stores the token via `charts/cloudflare-tunnel/templates/1password-item.yaml:7` and does not render ingress rules.

**Impact:** This repo cannot answer which internal Services are on the internet, or whether Cloudflare Access sits in front of Argo CD and Atlantis. A tunnel token is enough to run that tunnel. Combined with H1 and M1, a published hostname without Access is an unauthenticated UI (Atlantis) or a GitHub-login UI (Argo CD) on the public internet. R1 stops cluster-local metrics access; it does not describe the edge.

**Recommendation:** Either commit a locally managed `config.yml` (ingress hostnames and origins) or commit a rendered export of the remote tunnel next to the chart, and require Cloudflare Access for `argocd.rger.dev` and `atlantis.rger.dev`. Keep the token in 1Password.

### M3. Redis puts its password on the process command line

**Evidence:** `charts/auxbot/templates/redis-statefulset.yaml:31-38` and `charts/auxbot/templates/redis-statefulset.yaml:42-47`.

**Impact:** Kubelet expands `$(REDIS_PASSWORD)` into the container args. The password is then in `/proc/1/cmdline` on the node and in any debug copy of the process list. The NetworkPolicy and `requirepass` still matter; they do not hide the argv. The container security context drops capabilities and runs as uid 999 (`redis-statefulset.yaml:21-26` and `redis-statefulset.yaml:61-65`) but the root filesystem is writable, so a Redis flaw that writes a binary under the image filesystem is not blocked.

**Recommendation:** Mount a config or ACL file from the 1Password-generated Secret and pass `--requirepass-file` or `include` that file. Add `readOnlyRootFilesystem: true` with the existing `/data` volume and an `emptyDir` for `/tmp`. Confirm the Redis build does not also write a pidfile under `/var/run` before setting the read-only root.

Not changed here: a bad Redis flag crashes the only cache the controller uses.

### M4. No default-deny NetworkPolicy for the other workloads

**Evidence:** The only policies are `charts/auxbot/templates/redis-networkpolicy.yaml` and `charts/cloudflare-tunnel/templates/networkpolicy.yaml`. Absent for the auxbot controller (`charts/auxbot/templates/service.yaml`), Atlantis, PostgreSQL (`charts/postgresql/templates/service-postgres.yaml`), and Argo CD.

**Impact:** Redis ingress and cloudflared ingress are the only restricted paths. Everything else accepts cluster-wide connections: auxbot API and gRPC, Atlantis port 80, PostgreSQL 5432 when deployed, and Argo CD server HTTP. Egress from the controller, Atlantis, cloudflared, and PostgreSQL is unrestricted, which is expected for those roles and worth narrowing later (controller to the API and Discord, Atlantis to GitHub and provider APIs, cloudflared to Cloudflare).

**Recommendation:** Add a namespace default-deny and then allow the specific peers. Do the controller and Argo CD policies together with M1 and H3 so probes and the tunnel origin are not cut.

### M5. Running images are tag-pinned, not digest-pinned

**Evidence:** `charts/auxbot/values.yaml:31-32` (`redis:8.8.2`), `charts/cloudflare-tunnel/values.yaml:2-4` (`cloudflare/cloudflared:2026.10.0`), `charts/postgresql/values.yaml:3-5` (`postgres:16.9-alpine`), `charts/atlantis/values.yaml:2-3` (`v0.48.1`), `charts/argocd/Chart.yaml:6-12` (upstream charts choose their own tags). H3 covers `latest`.

**Impact:** A moved tag on Docker Hub or GHCR changes what the cluster runs on the next pull. Chart locks pin the Helm chart tarball (`charts/argocd/Chart.lock`, `charts/atlantis/Chart.lock`), not the container images inside those charts. Argo CD's own images therefore move when the upstream chart moves, which is at least reviewed as a chart bump. Redis, cloudflared, Postgres, and Atlantis are not.

**Recommendation:** Pin digests for Redis, cloudflared, Postgres, and Atlantis at the next planned rollout. Prefer that over rewriting tags in this PR, because a digest change rolls every pod, including PostgreSQL.

### M6. Argo CD and the image updater have no resource limits, and updater writes are sticky

**Evidence:** `charts/argocd/values.yaml` sets image-updater registries (`lines 9-18`) and notification config, and does not set `resources` for `argo-cd` or `argocd-image-updater`. Chart 10.10.2 defaults those to empty. Drift ignore is `charts/argocd/templates/applicationset.yaml:10-15`. The updater's only rule in-repo is the auxbot ImageUpdater, `charts/auxbot/templates/image-updater.yaml`.

**Impact:** A hot repo-server or controller can consume the node with no limit. The image updater's own ServiceAccount comes from the upstream chart and can patch Applications. Because helm parameters are ignored by self-heal, a bad updater write is not reverted. Today the only ImageUpdater object targets auxbot, which limits the intended scope, not the updater's RBAC.

**Recommendation:** Set requests and limits on `server`, `repo-server`, `application-controller`, `dex`, and the image updater using the chart's resource keys, sized from current usage. Restrict the updater's RBAC to the Applications it should mutate, if the chart allows it.

Not changed here: guessed limits can OOM Argo CD and stop all syncs.

### M7. Sync errors are copied into Slack

**Evidence:** `charts/argocd/values.yaml:114-118` and `charts/argocd/values.yaml:146-150`. The Slack token itself is a 1Password item, and the chart does not create that Secret: `charts/argocd/values.yaml:56-59`, `charts/argocd/templates/notifications/1password-item.yaml`.

**Impact:** `operationState.message` and `health.message` are posted to the `deployments` channel. A failed manifest that echoes a secret value, or an error that includes an internal hostname and a token, lands in Slack. The token handling is otherwise in good shape.

**Recommendation:** Keep the 1Password item. Truncate or drop the message block, or route failure details to a private channel.

## Low

### L1. 1Password vault and item IDs are committed

**Evidence:** The vault `ksplpxkiblaftafiljqytehbcy` and item ids are in `charts/auxbot/templates/1password-item.yaml:7`, `charts/atlantis/templates/secrets.yaml:9` and `:19`, `charts/cloudflare-tunnel/templates/1password-item.yaml:7`, `charts/argocd/templates/cluster-secret.yaml:9`, `charts/argocd/templates/github-sso-1password-item.yaml` via `charts/argocd/values.yaml:23`, `charts/argocd/templates/notifications/1password-item.yaml:7`, and the PostgreSQL fallback in `charts/postgresql/templates/1password-item.yaml:11`. A second vault id `p364xm4f4uub6cfyzweulklgwa` remains in `charts/postgresql/README.md:25` for a removed deployment.

**Impact:** The ids are not credentials. They tell an attacker who has stolen the 1Password Connect token exactly which items hold the cluster token, the GitHub App key, the tunnel token, and SSO. The operator token is not in this repo.

**Recommendation:** No rotation solely because the ids are in git. Do rotate the Connect token, the cluster bearer token, the GitHub App key, and the tunnel token if the Connect token has ever been exposed. Moving ids to values files does not reduce this.

### L2. PostgreSQL silently falls back to a shared item path

**Evidence:** `charts/postgresql/templates/1password-item.yaml:11` and the documented fallback in `charts/postgresql/README.md:60-65`.

**Impact:** A release that forgets `onePassword.itemPath` attaches `vaults/ksplpxkiblaftafiljqytehbcy/items/postgres-cluster`. That id is not in the opaque form used by the other items. If the item exists, two databases share a password. If it does not, the pod fails waiting for the Secret.

**Recommendation:** `required` the value. `devenv.nix` runs `helm template` with chart defaults, so making it required also means teaching that task to pass a dummy `-f` for PostgreSQL. That is why it was left as-is.

### L3. Template YAML is excluded from yamllint

**Evidence:** `.yamllint:18-20` ignores `charts/*/templates/*.yaml`. `devenv.nix` still renders every chart with `helm template`.

**Impact:** Indentation and structure bugs in templates are caught only when Helm can render them. Helm rendering is the stronger check. The ignore does not hide values files or unmanaged manifests.

**Recommendation:** Keep Helm rendering. Drop the ignore if `yamllint` is taught to skip Go templates another way, or lint rendered output.

### L4. Redis and PostgreSQL do not configure TLS

**Evidence:** Redis args in `charts/auxbot/templates/redis-statefulset.yaml:32-38` enable protected mode and a password, not TLS. PostgreSQL args in `charts/postgresql/templates/statefulset.yaml:29-33` set connection and buffer limits only.

**Impact:** Passwords travel in cleartext to any pod that is allowed to connect. Redis is restricted to the controller namespace-locally. PostgreSQL is not (H6).

**Recommendation:** TLS on PostgreSQL before it is exposed beyond the node. Redis TLS is less urgent while the NetworkPolicy stays.

### L5. No PodDisruptionBudgets

**Evidence:** No `PodDisruptionBudget` manifests. cloudflared runs 2 replicas (`charts/cloudflare-tunnel/values.yaml:7`). Redis and PostgreSQL are single replica.

**Impact:** A voluntary eviction can drop the only database or cache. The tunnel can survive one eviction. This is availability, not an access-control bug.

**Recommendation:** A PDB of `minAvailable: 1` for cloudflared. Do not PDB a single-replica database in a way that blocks node drain forever.

## What is in good shape

- Current secrets are `OnePasswordItem` resources. No live token was found in git history.
- Atlantis, auxbot, the tunnel, and Argo CD Services that this repo sets are ClusterIP. Atlantis ingress is off. The upstream Atlantis chart defaults the Service to `NodePort` and ingress to enabled; `charts/atlantis/values.yaml:66-73` overrides both. Keep that override.
- Redis already runs as non-root uid 999, drops capabilities, uses seccomp, sets `allowPrivilegeEscalation: false`, and restricts ingress to the controller.
- Auxbot RBAC is a namespace `Role`, not a `ClusterRole`.
- The ApplicationSet `repoURL` is fixed to this repository.
- `exec.enabled` is left at the chart default of false.
- Helm dependencies for Argo CD and Atlantis are digest-pinned in `Chart.lock`.
- CI does not use `pull_request_target` and does not pass repository secrets into steps.
- Resource requests and limits are set on auxbot, Redis, cloudflared, PostgreSQL, and Atlantis.

## Left for review

| Item | Why it was not changed |
|---|---|
| H1 Atlantis repo policy | Can block applies and custom workflows the infra repo already uses |
| H2 Wildcard ClusterRole and static token | Live object is unmanaged; narrowing it can break sync. Rotation has to happen on the cluster and in 1Password |
| H3 `latest` and controller `securityContext` | Can crash production auxbot; worker and controller image users were not verified |
| H4 ApplicationSet contract | Changes how every app is generated |
| H5 CI workflow | Another change is already editing `.github/workflows` |
| H6 PostgreSQL hardening and image bump | Restarts the database and can refuse to boot existing data |
| M1 SSO org restriction and disabling admin | Can lock operators out |
| M2 Tunnel ingress in git | Routes live in Cloudflare, not in this chart |
| M3 Redis password file and read-only root | Wrong flag takes down the cache |
| M6 Argo CD resource limits | Wrong limits stop all syncs |
