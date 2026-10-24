#!/usr/bin/env bash
# Checks shared by CI and `devenv tasks run validate:all`.
#
#   bash scripts/validate.sh                 # everything
#   bash scripts/validate.sh lint|helm|schema|images|versions
#
# Chart versions use VALIDATE_GIT_BASE when set. Pull requests use
# GITHUB_BASE_REF and pushes use GITHUB_EVENT_BEFORE. Otherwise a branch is
# compared to origin/main, and a dirty worktree on main is compared to HEAD.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

# Helm 4.2.4 reports Kubernetes client v1.36. Schemas exist for this release.
KUBERNETES_VERSION=1.36.0
# datreeio/CRDs-catalog commit. OnePasswordItem, Argo CD, and ImageUpdater are in it.
CRD_CATALOG_SHA=501527ab9c40c827144c8f45945b25a023e344ce

usage() {
  echo "usage: bash scripts/validate.sh [all|lint|helm|schema|images|versions]" >&2
}

require() {
  local tool
  for tool in "$@"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "required tool not on PATH: ${tool}" >&2
      exit 1
    fi
  done
}

# Return 0 when the file contains a floating latest image tag.
file_has_latest() {
  local file=$1
  local hits
  hits=$(grep -nEi \
    -e '^[[:space:]]*tag:[[:space:]]*["'\'']?latest["'\'']?[[:space:]]*(#.*)?$' \
    -e ':latest([^[:alnum:]_.@+-]|$)' \
    "$file" || true)
  if [ -z "$hits" ]; then
    return 1
  fi
  local line
  while IFS= read -r line; do
    printf 'latest image tag: %s:%s\n' "$file" "$line" >&2
  done <<< "$hits"
  return 0
}

scan_tree_images() {
  local failed=0
  local path file
  for path in "$@"; do
    [ -e "$path" ] || continue
    while IFS= read -r -d '' file; do
      if file_has_latest "$file"; then
        failed=1
      fi
    done < <(find "$path" -type f \( -name '*.yaml' -o -name '*.yml' \) \
      ! -path '*/charts/*/charts/*' -print0)
  done
  return "$failed"
}

# Return 0 when new is strictly greater than old (GNU sort -V).
version_is_newer() {
  local old=$1 new=$2 lowest
  [ "$new" != "$old" ] || return 1
  lowest=$(printf '%s\n%s\n' "$old" "$new" | sort -V | sed -n '1p')
  [ "$lowest" = "$old" ]
}

chart_version_of() {
  awk '
    /^version:[[:space:]]*/ {
      value = $2
      gsub(/["'\'']/, "", value)
      print value
      exit
    }
  ' "$1"
}

self_test() {
  local tmp
  tmp=$(mktemp -d)
  printf 'tag: "latest"\n' > "$tmp/bad-tag.yaml"
  printf 'image: "ghcr.io/example/app:latest"\n' > "$tmp/bad-image.yaml"
  printf 'tag: "sha-75af7f4"\nimage: "redis:8.8.2"\nignoreTags:\n  - latest\n' > "$tmp/ok.yaml"
  if ! file_has_latest "$tmp/bad-tag.yaml" >/dev/null 2>&1; then
    echo "self-test failed: tag latest was accepted" >&2
    exit 1
  fi
  if ! file_has_latest "$tmp/bad-image.yaml" >/dev/null 2>&1; then
    echo "self-test failed: image:latest was accepted" >&2
    exit 1
  fi
  if file_has_latest "$tmp/ok.yaml" >/dev/null 2>&1; then
    echo "self-test failed: pinned tag was rejected" >&2
    exit 1
  fi
  version_is_newer 0.1.7 0.1.8
  if version_is_newer 0.1.7 0.1.7 || version_is_newer 0.1.7 0.1.6; then
    echo "self-test failed: version comparison" >&2
    exit 1
  fi
  rm -rf "$tmp"
  echo "self-test: ok"
}

cmd_lint() {
  require yamllint
  echo "==> yamllint"
  yamllint .
}

add_helm_repos() {
  local repos url name
  repos=$(awk '
    /^[[:space:]]*repository:[[:space:]]*https?:\/\// {
      url = $2
      gsub(/["'\'']/, "", url)
      print url
    }
  ' charts/*/Chart.yaml | sort -u)
  if [ -z "$repos" ]; then
    return 0
  fi
  while IFS= read -r url; do
    [ -n "$url" ] || continue
    name=$(printf '%s' "$url" | sed -E 's#^https?://##; s#[^A-Za-z0-9]+#-#g; s#^-+##; s#-+$##')
    helm repo add "$name" "$url" --force-update
  done <<< "$repos"
}

render_charts() {
  require helm
  if [ -n "${RENDER_DIR:-}" ] && [ -d "${RENDER_DIR}/charts" ]; then
    return 0
  fi
  RENDER_DIR=$(mktemp -d)
  mkdir -p "${RENDER_DIR}/charts" "${RENDER_DIR}/static"
  add_helm_repos

  local chart name out
  local found=0
  for chart in charts/*/; do
    [ -f "${chart}/Chart.yaml" ] || continue
    found=1
    name=$(basename "$chart")
    echo "==> helm ${name}"
    helm dependency build "$chart" --skip-refresh
    helm lint "$chart"
    out="${RENDER_DIR}/charts/${name}.yaml"
    helm template "$name" "$chart" --include-crds > "$out"
    if ! grep -q '^kind:' "$out"; then
      echo "helm template produced no resources for ${name}" >&2
      exit 1
    fi
  done
  if [ "$found" -eq 0 ]; then
    echo "no charts under charts/" >&2
    exit 1
  fi

  local root file dest
  for root in argo-apps unmanaged; do
    [ -d "$root" ] || continue
    while IFS= read -r -d '' file; do
      dest="${RENDER_DIR}/static/${file}"
      mkdir -p "$(dirname "$dest")"
      cp "$file" "$dest"
    done < <(find "$root" -type f \( -name '*.yaml' -o -name '*.yml' \) -print0)
  done
}

cmd_helm() {
  render_charts
  echo "helm: lint and template ok"
}

cmd_schema() {
  require kubeconform jq
  render_charts
  local cache="${ROOT}/.cache/kubeconform"
  local json status=0
  mkdir -p "$cache"
  json=$(mktemp)
  echo "==> kubeconform (kubernetes ${KUBERNETES_VERSION})"
  local catalog="https://raw.githubusercontent.com/datreeio/CRDs-catalog/${CRD_CATALOG_SHA}"
  local schema_tpl='{{ .Group }}/{{ .ResourceKind }}_{{ .ResourceAPIVersion }}.json'
  kubeconform \
    -kubernetes-version "$KUBERNETES_VERSION" \
    -schema-location default \
    -schema-location "${catalog}/${schema_tpl}" \
    -cache "$cache" \
    -summary \
    -verbose \
    -ignore-missing-schemas \
    -skip CustomResourceDefinition \
    -output json \
    "$RENDER_DIR" > "$json" || status=$?

  jq -r '.summary | "valid=\(.valid) invalid=\(.invalid) errors=\(.errors) skipped=\(.skipped)"' \
    "$json" | sed 's/^/kubeconform: /'
  echo "kubeconform: skipping CustomResourceDefinition (no document schema in kubernetes-json-schema)"
  jq -r '
    [ .resources[]
      | select(.status == "statusValid")
      | select(
          .kind == "OnePasswordItem"
          or .kind == "Application"
          or .kind == "ApplicationSet"
          or .kind == "AppProject"
          or .kind == "ImageUpdater"
        )
      | .kind
    ]
    | group_by(.)
    | .[]
    | "kubeconform schema ok: \(.[0]) x\(length)"
  ' "$json"

  jq -r '
    .resources[]
    | select(.status == "statusInvalid" or .status == "statusError")
    | "\(.filename): \(.kind) \(.name): \(.msg) \(.validationErrors // [])"
  ' "$json" >&2

  local kind name version file
  while IFS="$(printf '\t')" read -r kind name version file; do
    [ -n "$kind" ] || continue
    case "$kind" in
      CustomResourceDefinition)
        ;;
      OnePasswordItem | Application | ApplicationSet | AppProject | ImageUpdater)
        echo "schema missing for ${kind} ${name}; the pinned CRD catalog should contain it" >&2
        status=1
        ;;
      *)
        echo "kubeconform skipped unknown kind: ${kind} ${name} (${version}) ${file}"
        ;;
    esac
  done < <(jq -r '
    .resources[]
    | select(.status == "statusSkipped")
    | [.kind, .name, .version, .filename]
    | @tsv
  ' "$json")

  rm -f "$json"
  if [ "$status" -ne 0 ]; then
    echo "kubeconform failed" >&2
    exit 1
  fi
}

cmd_images() {
  echo "==> image tags"
  scan_tree_images charts argo-apps apps unmanaged
  render_charts
  scan_tree_images "$RENDER_DIR"
}

zero_sha() {
  [[ "$1" =~ ^0+$ ]]
}

chart_worktree_dirty() {
  local changes
  changes=$(
    git diff --name-only HEAD -- charts
    git ls-files --others --exclude-standard -- charts
  )
  [ -n "$changes" ]
}

resolve_git_base() {
  local candidate=""
  if [ -n "${VALIDATE_GIT_BASE:-}" ] && ! zero_sha "$VALIDATE_GIT_BASE"; then
    candidate=$VALIDATE_GIT_BASE
  elif [ -n "${GITHUB_BASE_REF:-}" ]; then
    candidate="origin/${GITHUB_BASE_REF}"
  elif [ -n "${GITHUB_EVENT_BEFORE:-}" ] && ! zero_sha "$GITHUB_EVENT_BEFORE"; then
    candidate=$GITHUB_EVENT_BEFORE
  fi

  if [ -n "$candidate" ]; then
    if git rev-parse --verify --quiet "${candidate}^{commit}" >/dev/null; then
      git rev-parse --verify "${candidate}^{commit}"
      return 0
    fi
    if [ "${GITHUB_ACTIONS:-}" = "true" ] && [ "${GITHUB_EVENT_NAME:-}" != "workflow_dispatch" ]; then
      echo "cannot resolve chart-version base ${candidate}" >&2
      return 1
    fi
  fi

  if git rev-parse --verify --quiet origin/main >/dev/null; then
    local mb head
    mb=$(git merge-base HEAD origin/main)
    head=$(git rev-parse HEAD)
    if [ "$mb" != "$head" ]; then
      printf '%s\n' "$mb"
      return 0
    fi
  fi

  if chart_worktree_dirty; then
    git rev-parse HEAD
    return 0
  fi
  printf '\n'
}

chart_changed() {
  local name=$1 base=$2
  if [ -n "$(git diff --name-only "$base" -- "charts/${name}")" ]; then
    return 0
  fi
  if [ -n "$(git ls-files --others --exclude-standard -- "charts/${name}")" ]; then
    return 0
  fi
  return 1
}

cmd_versions() {
  require git
  echo "==> chart versions"
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
      echo "chart versions: not a git checkout" >&2
      exit 1
    fi
    echo "chart versions: not a git checkout; skipped"
    return 0
  fi

  local base
  if ! base=$(resolve_git_base); then
    exit 1
  fi
  if [ -z "$base" ]; then
    echo "chart versions: nothing to compare; skipped"
    return 0
  fi
  echo "chart versions: comparing to ${base}"

  local failed=0 chart name new_version old_text old_version
  for chart in charts/*/; do
    [ -f "${chart}/Chart.yaml" ] || continue
    name=$(basename "$chart")
    if ! chart_changed "$name" "$base"; then
      continue
    fi
    new_version=$(chart_version_of "${chart}/Chart.yaml")
    if [ -z "$new_version" ]; then
      echo "charts/${name}/Chart.yaml has no version" >&2
      failed=1
      continue
    fi
    if ! old_text=$(git show "${base}:charts/${name}/Chart.yaml" 2>/dev/null); then
      echo "charts/${name}: new chart at version ${new_version}"
      continue
    fi
    old_version=$(printf '%s\n' "$old_text" | chart_version_of /dev/stdin)
    if [ -z "$old_version" ]; then
      echo "charts/${name}: could not read base version" >&2
      failed=1
      continue
    fi
    if ! version_is_newer "$old_version" "$new_version"; then
      echo "charts/${name}: Chart.yaml version ${new_version} is not greater than ${old_version}" >&2
      failed=1
    else
      echo "charts/${name}: ${old_version} -> ${new_version}"
    fi
  done
  if [ "$failed" -ne 0 ]; then
    exit 1
  fi
}

cmd_all() {
  self_test
  cmd_lint
  cmd_versions
  cmd_images
  cmd_schema
  echo "all validations passed"
}

cleanup() {
  if [ -n "${RENDER_DIR:-}" ] && [ -d "$RENDER_DIR" ]; then
    rm -rf "$RENDER_DIR"
  fi
}
trap cleanup EXIT

command=${1:-all}
case "$command" in
  all) cmd_all ;;
  lint) cmd_lint ;;
  helm) cmd_helm ;;
  schema) cmd_schema ;;
  images) cmd_images ;;
  versions) cmd_versions ;;
  -h | --help | help) usage ;;
  *)
    usage
    exit 2
    ;;
esac
