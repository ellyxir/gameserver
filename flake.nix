# `nix develop` to start shell
# `nix flake update` to update all packages (inputs) 
{
  description = "elixir dev flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          beam28Packages.elixir_1_20
          beam28Packages.elixir-ls
          inotify-tools
          watchman
          git
        ];
      };
    };
}
