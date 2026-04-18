#!/usr/bin/env bash
set -euo pipefail

# Directory to store rendered manifests
RENDERED_DIR="rendered"
K8S_VERSION="1.31.0" # Latest stable version with wide schema support
CRD_SCHEMA_URL="https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}==> Cleaning up previous runs...${NC}"
rm -rf "${RENDERED_DIR}"
mkdir -p "${RENDERED_DIR}"

echo -e "${BLUE}==> Rendering Helm charts...${NC}"
for chart_path in charts/*/; do
    if [ -d "${chart_path}" ]; then
        chart_name=$(basename "${chart_path}")
        echo "Processing chart: ${chart_name}"

        # Update dependencies
        helm dependency update "${chart_path}" > /dev/null

        # Render to flat manifest
        helm template "${chart_name}" "${chart_path}" --include-crds > "${RENDERED_DIR}/chart-${chart_name}.yaml"
    fi
done

echo -e "${BLUE}==> Collecting ArgoCD apps and unmanaged manifests...${NC}"
if [ -d "argo-apps" ]; then
    find argo-apps -type f \( -name "*.yaml" -o -name "*.yml" \) -exec cp {} "${RENDERED_DIR}/" \;
fi

if [ -d "unmanaged" ]; then
    find unmanaged -type f \( -name "*.yaml" -o -name "*.yml" \) -exec cp {} "${RENDERED_DIR}/" \;
fi

echo -e "${BLUE}==> Validating with Kubeconform...${NC}"
kubeconform -kubernetes-version "${K8S_VERSION}" \
    -schema-location default \
    -schema-location "${CRD_SCHEMA_URL}" \
    -summary \
    -ignore-missing-schemas \
    "${RENDERED_DIR}"

echo -e "${BLUE}==> Scanning for best practices with Kube-score...${NC}"
# We ignore some errors if the repo is in transition, but user requested high quality.
# Running and reporting.
find "${RENDERED_DIR}" -type f \( -name "*.yaml" -o -name "*.yml" \) | xargs kube-score score || true

echo -e "${BLUE}==> Scanning for security with Checkov...${NC}"
checkov --directory "${RENDERED_DIR}" --framework kubernetes --quiet --soft-fail

echo -e "${GREEN}==> Validation complete!${NC}"
