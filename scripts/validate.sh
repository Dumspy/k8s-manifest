#!/usr/bin/env bash
set -euo pipefail

# Config
RENDERED_DIR="rendered"
K8S_VERSION="1.31.0"
CRD_SCHEMA_URL="https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"

# Clean
rm -rf "${RENDERED_DIR}" && mkdir -p "${RENDERED_DIR}"

# Render charts
for chart in charts/*/; do
    [ -d "$chart" ] || continue
    name=$(basename "$chart")
    echo "Rendering: $name"
    helm dependency update "$chart" > /dev/null
    helm template "$name" "$chart" --include-crds > "${RENDERED_DIR}/chart-$name.yaml"
done

# Collect manifests
[ -d "argo-apps" ] && find argo-apps -type f \( -name "*.yaml" -o -name "*.yml" \) -exec cp {} "${RENDERED_DIR}/" \;
[ -d "unmanaged" ] && find unmanaged -type f \( -name "*.yaml" -o -name "*.yml" \) -exec cp {} "${RENDERED_DIR}/" \;

# Validate
echo "Validating manifests..."
kubeconform -kubernetes-version "${K8S_VERSION}" \
    -schema-location default \
    -schema-location "${CRD_SCHEMA_URL}" \
    -summary \
    -ignore-missing-schemas \
    "${RENDERED_DIR}"
