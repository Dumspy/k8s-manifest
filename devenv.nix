{ pkgs, ... }: {
  packages = with pkgs; [
    kubernetes-helm
    yamllint
    helm-ls
    kubeconform
  ];

  # Single entrypoint for local dev and CI: `devenv tasks run validate:all`
  tasks = {
    "validate:lint".exec = "yamllint .";

    "validate:helm".exec = ''
      set -euo pipefail
      helm repo add argo-helm https://argoproj.github.io/argo-helm --force-update
      helm repo add atlantis https://runatlantis.github.io/helm-charts --force-update
      out=$(mktemp -d)
      trap 'rm -rf "$out"' EXIT
      for chart in charts/*/; do
        [ -f "$chart/Chart.yaml" ] || continue
        name=$(basename "$chart")
        helm dependency build "$chart" --skip-refresh
        helm lint "$chart"
        helm template "$name" "$chart" --include-crds > "$out/$name.yaml"
      done
      kubeconform -ignore-missing-schemas -summary "$out" argo-apps unmanaged
    '';

    "validate:all" = {
      after = [ "validate:lint" "validate:helm" ];
      exec = "echo 'All validations passed'";
    };
  };
}
