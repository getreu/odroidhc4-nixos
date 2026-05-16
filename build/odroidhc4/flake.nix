{
  description = "NixOS SD image configuration for Odroid HC4";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs =
    { self, nixpkgs }:
    let
      # The overlay providing ubootOdroidC4, firmwareOdroidC4, and meson64-tools
      odroidOverlay = import ./overlay/odroid-c4.nix;

      # Supported systems for this flake
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forSystem = f: nixpkgs.lib.genAttrs systems (system: f system);

      # Common NixOS system builder
      mkNixosSystem =
        system: args:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit nixpkgs odroidOverlay;
          };
          modules = [
            ./configuration.nix
            {
              nixpkgs.overlays = [ odroidOverlay ];
            }
          ]
          ++ (args.modules or [ ]);
        };

    in
    {
      # ============================
      # NixOS System Configurations
      # ============================

      # For building an SD image that boots on the Odroid HC4
      # This targets aarch64-linux (the HC4's native architecture)
      nixosSystem.odroid-hc4 = mkNixosSystem "aarch64-linux" { };

      # For building from an x86_64 host with cross-compilation
      # Note: cross-building for ARM can be problematic with NixOS
      # native aarch64 builds are preferred
      nixosSystem.odroid-hc4-cross = mkNixosSystem "x86_64-linux" {
        modules = [
          {
            crossSystem = {
              config = "aarch64-unknown-linux-gnu";
              system = "aarch64-linux";
            };
          }
        ];
      };

      # ============================
      # Package Derivations
      # ============================

      # The SD image derivation (what we actually want)
      packages = forSystem (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = [ odroidOverlay ];
          };
        in
        {
          # Rebuild the NixOS configuration to get the SD image
          sdImage =
            (nixpkgs.lib.nixosSystem {
              inherit system;
              specialArgs = { inherit nixpkgs odroidOverlay; };
              modules = [
                ./configuration.nix
                {
                  nixpkgs.overlays = [ odroidOverlay ];
                }
              ];
            }).config.system.build.sdImage;

          # Individual components for reference
          ubootOdroidC4 = pkgs.ubootOdroidC4;
          firmwareOdroidC4 = pkgs.firmwareOdroidC4;
          meson64-tools = pkgs.meson64-tools;
          ubootTools = pkgs.ubootTools;

          # The system closure (for reference/debugging)
          configClosure =
            (nixpkgs.lib.nixosSystem {
              inherit system;
              specialArgs = { inherit nixpkgs odroidOverlay; };
              modules = [
                ./configuration.nix
                {
                  nixpkgs.overlays = [ odroidOverlay ];
                }
              ];
            }).config.system.build.toplevel;
        }
      );

      # ============================
      # Dev Shells
      # ============================

      devShells = forSystem (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = [ odroidOverlay ];
          };
        in
        {
          default = pkgs.mkShell {
            name = "odroid-hc4-dev";
            description = "Development shell for Odroid HC4 NixOS configuration";
            packages = with pkgs; [
              nixfmt-rfc-style
              nil
              alejandra
              mdbook
            ];
            shellHook = ''
              echo "Odroid HC4 NixOS development environment"
              echo "======================================="
              echo "Configuration: ./configuration.nix"
              echo "Overlay: ./overlay/odroid-c4.nix"
              echo ""
              echo "Build SD image:"
              echo "  nix build .#sdImage"
              echo ""
              echo "Show config:"
              echo "  nix flake show"
              echo "  nixos-rebuild show-config"
            '';
          };
        }
      );

      # ============================
      # Formatters
      # ============================

      formatter = forSystem (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = [ odroidOverlay ];
          };
        in
        pkgs.alejandra
      );

      # ============================
      # Checks (for CI)
      # ============================

      checks = forSystem (
        system:
        let
          cfg = (
            nixpkgs.lib.nixosSystem {
              inherit system;
              specialArgs = { inherit nixpkgs odroidOverlay; };
              modules = [
                ./configuration.nix
                {
                  nixpkgs.overlays = [ odroidOverlay ];
                }
              ];
            }
          );
        in
        {
          # Validate the configuration
          nixosConfig = cfg;

          # Ensure key attributes exist
          keyAttributes =
            assert cfg.config.hardware.deviceTree.filter == "meson-sm1-odroid-hc4.dtb";
            assert cfg.config.sdImage.firmwareSize == 64;
            assert cfg.config.sdImage.compressImage;
            true;
        }
      );
    };
}
