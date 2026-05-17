{
  description = "NixOS SD image configuration for Odroid HC4 — reproducible build";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs =
    { self, nixpkgs }:
    let
      # The overlay providing buildable U-Boot for Odroid C4/HC4
      odroidOverlay = import ./overlay/odroid-c4.nix;

      # Supported systems
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
            sdImageModule = import (nixpkgs + "/nixos/modules/installer/sd-card/sd-image.nix");
          };
          modules = [
            ./configuration.nix
            {
              nixpkgs.overlays = [ odroidOverlay ];
              nixpkgs.config.allowUnfree = true;
            }
          ]
          ++ (args.modules or [ ]);
        };

      # Build SD image for the Odroid HC4 (aarch64 target).
      # On x86_64 hosts, sets nixpkgs.crossSystem so the entire
      # NixOS closure (kernel, initrd, U-Boot, etc.) is cross-compiled.
      # On aarch64 hosts, builds natively with no crossSystem.
      mkSdImage =
        buildSystem:
        let
          crossSystem =
            if buildSystem == "x86_64-linux" then
              {
                config = "aarch64-unknown-linux-gnu";
                system = "aarch64-linux";
              }
            else
              null;
        in
        (nixpkgs.lib.nixosSystem {
          system = buildSystem;
          specialArgs = {
            inherit nixpkgs odroidOverlay;
            sdImageModule = import (nixpkgs + "/nixos/modules/installer/sd-card/sd-image.nix");
          };
          modules = [
            ./configuration.nix
            {
              nixpkgs.overlays = [ odroidOverlay ];
              nixpkgs.config.allowUnfree = true;
            }
          ]
          ++ (if crossSystem != null then [ { nixpkgs.crossSystem = crossSystem; } ] else [ ]);
        }).config.system.build.sdImage;

    in
    {
      # ============================
      # NixOS System Configurations
      # ============================

      nixosSystem.odroid-hc4 = mkNixosSystem "aarch64-linux" { };

      # Cross-compiled system: runs on x86_64 host, targets aarch64
      nixosSystem.odroid-hc4-cross = mkNixosSystem "aarch64-linux" {
        modules = [
          {
            nixpkgs.crossSystem = {
              config = "aarch64-unknown-linux-gnu";
              system = "aarch64-linux";
            };
          }
        ];
      };

      # ============================
      # Package Derivations
      # ============================

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
          # SD image: cross-compile from x86_64, build natively on aarch64
          sdImage = mkSdImage system;

          # U-Boot package (for separate flashing via sd_fusing.sh)
          u-boot = pkgs.u-boot-odroid-c4;

          # Cross-compiled config closure (x86_64 host → aarch64 target)
          configClosureCross = mkSdImage system;

          # Default: U-Boot on x86_64 (fastest to build), sdImage on aarch64
          default =
            if system == "x86_64-linux" then
              self.packages.${system}.u-boot
            else
              self.packages.${system}.sdImage;
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
              echo "Odroid HC4 NixOS development environment (reproducible)"
              echo "======================================================="
              echo ""
              echo "Build SD image (native aarch64):"
              echo "  nix build .#sdImage"
              echo ""
              echo "Build U-Boot only (cross from x86_64):"
              echo "  nix build .#u-boot"
              echo ""
              echo "Build SD image (cross from x86_64):"
              echo "  nix build .#sdImage"
              echo "  nix build .#odroid-hc4-cross.config.system.build.sdImage"
              echo ""
              echo "Show config:"
              echo "  nix flake show"
              echo ""
              echo "Key files:"
              echo "  configuration.nix    - NixOS config"
              echo "  overlay/odroid-c4.nix - Buildable U-Boot derivation"
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
          # NixOS system without cross-compilation (native)
          cfg = (
            nixpkgs.lib.nixosSystem {
              inherit system;
              specialArgs = {
                inherit nixpkgs odroidOverlay;
                sdImageModule = import (nixpkgs + "/nixos/modules/installer/sd-card/sd-image.nix");
              };
              modules = [
                ./configuration.nix
                {
                  nixpkgs.overlays = [ odroidOverlay ];
                  nixpkgs.config.allowUnfree = true;
                }
              ];
            }
          );

          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = [ odroidOverlay ];
          };

          # For x86_64, also test cross-compiled derivation
          cfgCross =
            if system == "x86_64-linux" then
              nixpkgs.lib.nixosSystem {
                inherit system;
                specialArgs = {
                  inherit nixpkgs odroidOverlay;
                  sdImageModule = import (nixpkgs + "/nixos/modules/installer/sd-card/sd-image.nix");
                };
                modules = [
                  ./configuration.nix
                  {
                    nixpkgs.overlays = [ odroidOverlay ];
                    nixpkgs.config.allowUnfree = true;
                    nixpkgs.crossSystem = {
                      config = "aarch64-unknown-linux-gnu";
                      system = "aarch64-linux";
                    };
                  }
                ];
              }
            else
              null;
        in
        (
          {
            # Validate the native configuration evaluates correctly
            nixosConfig = cfg.config.system.build.toplevel;

            # Ensure U-Boot derivation exists and is not broken
            ubootDerivation = pkgs.u-boot-odroid-c4;
          }
          # On x86_64 only, also validate cross-compiled config evaluates
          // nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
            nixosConfigCross = cfgCross.config.system.build.toplevel;
          }
        )
      );
    };
}
