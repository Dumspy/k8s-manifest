{ pkgs, ... }: {
  packages = with pkgs; [
    kubernetes-helm
    yamllint
    helm-ls
  ];

  # Single entrypoint for local dev and CI: `devenv tasks run validate:all`
  tasks = {
    "validate:lint".exec = "yamllint .";
    "validate:helm".exec = ''
      set -euo pipefail
      # Idempotent: already-registered on local reruns, fresh on CI
      helm repo add argo-helm https://argoproj.github.io/argo-helm 2>/dev/null || true
      helm repo add atlantis https://runatlantis.github.io/helm-charts 2>/dev/null || true
      for chart in charts/*/; do
        if [ ! -f "$chart/Chart.yaml" ]; then
          echo "Skipping non-chart: $chart"
          continue
        fi
        name=$(basename "$chart")
        echo "Validating: $name"
        helm dependency build "$chart" > /dev/null
        helm lint "$chart"
        helm template "$name" "$chart" --include-crds > /dev/null
      done
    '';
    "validate:all" = {
      after = [ "validate:lint" "validate:helm" ];
      exec = "echo 'All validations passed'";
    };
  };
}
