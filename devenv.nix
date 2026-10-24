{ pkgs, ... }: {
  packages = with pkgs; [
    kubernetes-helm
    yamllint
    helm-ls
    kubeconform
    jq
  ];

  # CI and local dev run the same script. `devenv tasks run validate:all` is the
  # local entrypoint; partial task names run one check.
  tasks = {
    "validate:lint".exec = "bash scripts/validate.sh lint";
    "validate:helm".exec = "bash scripts/validate.sh helm";
    "validate:schema".exec = "bash scripts/validate.sh schema";
    "validate:images".exec = "bash scripts/validate.sh images";
    "validate:chart-versions".exec = "bash scripts/validate.sh versions";
    "validate:all".exec = "bash scripts/validate.sh";
  };
}
