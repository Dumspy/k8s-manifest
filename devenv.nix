{ pkgs, ... }: {
  packages = with pkgs; [
    kubernetes-helm
    yamllint
    helm-ls
    kubeconform
    jq
  ];

  # CI runs this same script.
  tasks = {
    "validate:all".exec = "bash scripts/validate.sh";
  };
}
