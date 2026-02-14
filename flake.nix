{
  description = "k8s manifest development environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-24.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    flake-utils,
    nixpkgs,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs { inherit system; };
      in {
        devShell = pkgs.mkShell rec {
          name = "k8s-manifest";

          packages = with pkgs; [
            helm-ls
          ];
        };
      }
    );
}
