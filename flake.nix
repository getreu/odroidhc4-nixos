{
  description = "Development environment for Odroid HC4 migration project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forSystem = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      devShells = forSystem (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
        in
        {
          default = pkgs.mkShell {
            name = "odroid-hc4-dev";
            packages = with pkgs; [
              claude-code
              nixfmt
              nil
              alejandra
            ];
            shellHook = ''
              echo "Odroid HC4 migration dev environment"
              echo "===================================="
              echo ""
              echo "  claude-code    - Anthropic CLI (unfree)"
              echo "  alejandra      - Nix formatter"
              echo "  nixfmt         - Nix format checker"
              echo "  nil            - Nix language server"
              echo ""
              echo "Build SD image:"
              echo "  cd build/odroidhc4 && nix build .#sdImage"
            '';
          };
        }
      );

      formatter = forSystem (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
        in
        pkgs.alejandra
      );
    };
}
