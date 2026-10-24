#!/usr/bin/env bash
# Shared by CI and `devenv tasks run validate:all`.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Helm 4.2.4 speaks Kubernetes 1.36. The catalog pin has OnePassword and Argo schemas.
k8s_version=1.36.0
crd_catalog=501527ab9c40c827144c8f45945b25a023e344ce

chart_version() {
  awk '/^version:/{gsub(/["'\'']/, "", $2); print $2; exit}' "$1"
}

echo "==> yamllint"
yamllint .

echo "==> chart versions"
if [ -n "${GITHUB_BASE_REF:-}" ]; then
  base="origin/${GITHUB_BASE_REF}"
elif [ -n "${GITHUB_EVENT_BEFORE:-}" ] && [[ ! ${GITHUB_EVENT_BEFORE} =~ ^0+$ ]]; then
  base=$GITHUB_EVENT_BEFORE
elif git rev-parse --verify --quiet origin/main >/dev/null; then
  base=$(git merge-base HEAD origin/main)
  [ "$base" = "$(git rev-parse HEAD)" ] && base=HEAD
else
  base=HEAD
fi
if ! git rev-parse --verify --quiet "${base}^{commit}" >/dev/null; then
  echo "chart version base not found: ${base}" >&2
  exit 1
fi
echo "comparing to ${base}"
for chart in charts/*/; do
  [ -f "${chart}/Chart.yaml" ] || continue
  name=$(basename "$chart")
  changed=$(
    git diff --name-only "$base" -- "charts/${name}"
    git ls-files --others --exclude-standard -- "charts/${name}"
  )
  [ -n "$changed" ] || continue
  new=$(chart_version "${chart}/Chart.yaml")
  [ -n "$new" ] || {
    echo "charts/${name}/Chart.yaml has no version" >&2
    exit 1
  }
  if ! old_text=$(git show "${base}:charts/${name}/Chart.yaml" 2>/dev/null); then
    echo "charts/${name}: new chart ${new}"
    continue
  fi
  old=$(printf '%s\n' "$old_text" | chart_version /dev/stdin)
  lowest=$(printf '%s\n%s\n' "$old" "$new" | sort -V | sed -n '1p')
  if [ "$new" = "$old" ] || [ "$lowest" != "$old" ]; then
    echo "charts/${name}: version ${new} is not greater than ${old}" >&2
    exit 1
  fi
  echo "charts/${name}: ${old} -> ${new}"
done

echo "==> helm"
helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm repo add atlantis https://runatlantis.github.io/helm-charts --force-update
render=$(mktemp -d)
trap 'rm -rf "$render"' EXIT
for chart in charts/*/; do
  [ -f "${chart}/Chart.yaml" ] || continue
  name=$(basename "$chart")
  echo "lint ${name}"
  helm dependency build "$chart" --skip-refresh
  helm lint "$chart"
  helm template "$name" "$chart" --include-crds > "${render}/${name}.yaml"
done

echo "==> image tags"
if find charts argo-apps apps unmanaged "$render" \
  -type f \( -name '*.yaml' -o -name '*.yml' \) ! -path 'charts/*/charts/*' -print0 |
  xargs -0 -r grep -nEi \
    -e '^[[:space:]]*tag:[[:space:]]*["'\'']?latest["'\'']?[[:space:]]*(#.*)?$' \
    -e ':latest([^[:alnum:]_.@+-]|$)'
then
  echo "image tags must be pinned; latest is not allowed" >&2
  exit 1
fi

echo "==> kubeconform"
schema="https://raw.githubusercontent.com/datreeio/CRDs-catalog/${crd_catalog}"
schema="${schema}/{{ .Group }}/{{ .ResourceKind }}_{{ .ResourceAPIVersion }}.json"
report=$(mktemp)
status=0
kubeconform \
  -kubernetes-version "$k8s_version" \
  -schema-location default \
  -schema-location "$schema" \
  -summary \
  -verbose \
  -ignore-missing-schemas \
  -skip CustomResourceDefinition \
  -output json \
  "$render" argo-apps unmanaged > "$report" || status=$?

jq -r '.summary | "valid=\(.valid) invalid=\(.invalid) errors=\(.errors) skipped=\(.skipped)"' "$report"
jq -r '
  .resources[]
  | select(.status == "statusInvalid" or .status == "statusError")
  | "\(.filename): \(.kind) \(.name): \(.msg)"
' "$report" >&2
# CustomResourceDefinition has no document schema upstream. Anything else skipped is named here.
# OnePassword and Argo kinds must have a schema or the catalog pin is wrong.
jq -r '
  .resources[]
  | select(.status == "statusSkipped" and .kind != "CustomResourceDefinition")
  | "skipped \(.kind) \(.name)"
' "$report"
if jq -e '
  .resources[]
  | select(.status == "statusSkipped")
  | select(
      .kind == "OnePasswordItem" or .kind == "Application" or .kind == "ApplicationSet"
      or .kind == "AppProject" or .kind == "ImageUpdater"
    )
' "$report" >/dev/null; then
  echo "a required CRD was skipped; update the catalog pin" >&2
  exit 1
fi
exit "$status"
