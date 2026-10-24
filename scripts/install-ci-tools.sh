#!/usr/bin/env bash
# Install the pinned binaries CI uses to run scripts/validate.sh.
# Local development gets the same tools from devenv.nix instead.
set -euo pipefail

HELM_VERSION=4.2.4
KUBECONFORM_VERSION=0.8.0
YAMLLINT_VERSION=1.37.1

BIN_DIR="${CI_TOOLS_DIR:-${HOME}/.local/ci-tools}/bin"
mkdir -p "$BIN_DIR"

arch=$(uname -m)
case "$arch" in
  x86_64)
    helm_arch=amd64
    helm_sha=c306b46f719b0a4da32d0f78ee21bf90ce8d602f15b22ab753f0674d1670a7f3
    kubeconform_sha=9bc2bffbf71f261128533edaf912153948b7ff238f9a531ae6d34466ec287883
    ;;
  aarch64 | arm64)
    helm_arch=arm64
    helm_sha=564de2191b881e9f71b5606b25345821ea1682f06ab90499d3ab22b530176da1
    kubeconform_sha=1f53fc8e81258197a35e8603054162a5af1de8c5af13746c71ab680d9534ed87
    ;;
  *)
    echo "unsupported architecture: ${arch}" >&2
    exit 1
    ;;
esac

download() {
  local url=$1 sha=$2 dest=$3
  local tmp
  tmp=$(mktemp)
  curl -fsSL "$url" -o "$tmp"
  echo "${sha}  ${tmp}" | sha256sum -c -
  mv "$tmp" "$dest"
}

if ! "$BIN_DIR/helm" version --short 2>/dev/null | grep -q "v${HELM_VERSION}"; then
  echo "installing helm ${HELM_VERSION}"
  work=$(mktemp -d)
  download "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${helm_arch}.tar.gz" "$helm_sha" "${work}/helm.tgz"
  tar -xzf "${work}/helm.tgz" -C "$work"
  install -m 0755 "${work}/linux-${helm_arch}/helm" "$BIN_DIR/helm"
  rm -rf "$work"
fi

if ! "$BIN_DIR/kubeconform" -v 2>/dev/null | grep -q "v${KUBECONFORM_VERSION}"; then
  echo "installing kubeconform ${KUBECONFORM_VERSION}"
  work=$(mktemp -d)
  url="https://github.com/yannh/kubeconform/releases/download/v${KUBECONFORM_VERSION}"
  url="${url}/kubeconform-linux-${helm_arch}.tar.gz"
  download "$url" "$kubeconform_sha" "${work}/kubeconform.tgz"
  tar -xzf "${work}/kubeconform.tgz" -C "$work"
  install -m 0755 "${work}/kubeconform" "$BIN_DIR/kubeconform"
  rm -rf "$work"
fi

if ! python3 -m yamllint --version 2>/dev/null | grep -q "^yamllint ${YAMLLINT_VERSION}$"; then
  echo "installing yamllint ${YAMLLINT_VERSION}"
  python3 -m pip install --user --disable-pip-version-check "yamllint==${YAMLLINT_VERSION}"
fi

if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$BIN_DIR" >> "$GITHUB_PATH"
  echo "${HOME}/.local/bin" >> "$GITHUB_PATH"
fi

echo "tools ready in ${BIN_DIR}"
