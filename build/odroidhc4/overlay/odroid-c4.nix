# Self-contained Nixpkgs overlay that adds Odroid C4/HC4 U-Boot support
# on top of upstream NixOS 25.11.
#
# Usage in flake.nix:
#   overlays.default = import ./overlay;
#
# This provides:
#   - pkgs.meson64-tools        : proprietary Amlogic Meson G12A firmware tools
#   - pkgs.firmwareOdroidC4     : Hardkernel firmware blobs (BL2, BL30, BL31, BL33)
#   - pkgs.ubootOdroidC4        : U-Boot FIP binary (BL2+BL30+BL31+BL33 packed)
#
# The Odroid HC4 uses the same Amlogic SM1/S905X3 (G12A) SoC as the Odroid C4,
# so the C4 U-Boot build works for HC4 as well.

final: prev:

let
  # Meson64 tools: proprietary tools for Amlogic Meson ARM64 platforms
  # Used by ubootOdroidC4 to sign and pack firmware blobs
  meson64-tools = prev.buildPackages.stdenv.mkDerivation rec {
    pname = "meson64-tools";
    version = "unstable-2020-08-03";

    src = prev.fetchFromGitHub {
      owner = "angerman";
      repo = pname;
      rev = "a2d57d11fd8b4242b903c10dca9d25f7f99d8ff0";
      sha256 = "1487cr7sv34yry8f0chaj6s2g3736dzq0aqw239ahdy30yg7hb2v";
    };

    nativeBuildInputs = with prev.buildPackages; [
      gcc
      git
      hostname
    ];

    buildInputs = with prev.buildPackages; [
      openssl
      bison
      flex
      bc
      python3
    ];

    preBuild = ''
      patchShebangs .
      substituteInPlace mbedtls/programs/fuzz/Makefile --replace "python2" "python"
      substituteInPlace mbedtls/tests/Makefile --replace "python2" "python"
    '';

    makeFlags = [ "PREFIX=$(out)/bin" ];

    meta = with prev.buildPackages.lib; {
      homepage = "https://github.com/angerman/meson64-tools";
      description = "Tools for Amlogic Meson ARM64 platforms";
      license = licenses.unfree;
      maintainers = with maintainers; [ aarapov ];
    };
  };

  # Hardkernel firmware for Odroid C4/HC4 (Amlogic G12A SoC)
  # Provides BL2, BL30, BL31, BL33 binaries and DDR firmware needed for U-Boot FIP
  firmwareOdroidC4 = prev.buildPackages.stdenv.mkDerivation rec {
    pname = "firmware-odroid-c4";
    version = "2015.01";

    src = prev.fetchFromGitHub {
      owner = "hardkernel";
      repo = "u-boot";
      rev = "90ebb7015c1bfbbf120b2b94273977f558a5da46";
      sha256 = "0kv9hpsgpbikp370wknbyj6r6cyhp7hng3ng6xzzqaw13yy4qiz9";
    };

    nativeBuildInputs = with prev.buildPackages; [
      git
      hostname
      gcc13
    ];

    postPatch = ''
      # Replace all /bin/pwd references with pwd for Nix sandbox compatibility
      find . -name "*.mk" -o -name "Makefile" | xargs sed -i 's|/bin/pwd|pwd|g'
    '';

    buildFlags = [
      "odroidc4_defconfig"
      "bl301.bin"
    ];

    installPhase = ''
      mkdir -p $out
      cp build/board/hardkernel/odroidc4/firmware/acs.bin          $out/
      cp build/scp_task/bl301.bin                                   $out/
      cp fip/g12a/aml_ddr.fw                                        $out/
      cp fip/g12a/bl2.bin                                           $out/
      cp fip/g12a/bl30.bin                                          $out/
      cp fip/g12a/bl31.img                                          $out/
      cp fip/g12a/ddr3_1d.fw                                        $out/
      cp fip/g12a/ddr4_1d.fw                                        $out/
      cp fip/g12a/ddr4_2d.fw                                        $out/
      cp fip/g12a/diag_lpddr4.fw                                    $out/
      cp fip/g12a/lpddr3_1d.fw                                      $out/
      cp fip/g12a/lpddr4_1d.fw                                      $out/
      cp fip/g12a/lpddr4_2d.fw                                      $out/
      cp fip/g12a/piei.fw                                           $out/
      cp sd_fuse/sd_fusing.sh                                       $out/
    '';

    meta = with prev.buildPackages.lib; {
      homepage = "https://www.hardkernel.com/";
      description = "Hardkernel firmware for Odroid C4/HC4 (G12A SoC)";
      license = licenses.unfreeRedistributableFirmware;
      maintainers = with maintainers; [ aarapov ];
    };
  };

  # U-Boot for Odroid C4/HC4 (Amlogic G12A/SM1 SoC)
  # This builds u-boot.bin — a full FIP binary: BL2+BL30+BL31+BL33 packed
  # Uses meson64-tools for signing and firmwareOdroidC4 for blobs
  buildUBoot =
    {
      version ? null,
      src ? null,
      filesToInstall,
      installDir ? "$out",
      defconfig,
      extraConfig ? "",
      extraPatches ? [ ],
      extraMakeFlags ? [ ],
      extraMeta ? { },
      ...
    }@args:
    prev.buildPackages.stdenv.mkDerivation (
      {
        pname = "uboot-${defconfig}";
        version = if src == null then "2022.01" else version;

        src =
          if src == null then
            prev.fetchurl {
              url = "ftp://ftp.denx.de/pub/u-boot/u-boot-2022.01.tar.bz2";
              sha256 = "sha256-gbRUMifbIowD+KG/XdvIE7C7j2VVzkYGTvchpvxoBBM=";
            }
          else
            src;

        patches = extraPatches;

        postPatch = ''
          patchShebangs tools
        '';

        nativeBuildInputs = with prev.buildPackages; [
          bc
          bison
          dtc
          flex
          openssl
          swig
          which
          (prev.buildPackages.python3.withPackages (p: [
            p.libfdt
            p.setuptools
          ]))
        ];

        depsBuildBuild = with prev.buildPackages; [
          gcc
          stdenv.cc
        ];

        hardeningDisable = [ "all" ];
        enableParallelBuilding = true;

        makeFlags = [
          "DTC=dtc"
          "CROSS_COMPILE=${prev.buildPackages.stdenv.cc.targetPrefix}"
        ]
        ++ extraMakeFlags;

        passAsFile = [ "extraConfig" ];

        configurePhase = ''
          runHook preConfigure
          make ${defconfig}
          cat $extraConfigPath >> .config
          runHook postConfigure
        '';

        installPhase = ''
          runHook preInstall
          mkdir -p ${installDir}
          cp ${prev.lib.concatStringsSep " " filesToInstall} ${installDir}
          mkdir -p "$out/nix-support"
          ${prev.lib.concatMapStrings (file: ''
            echo "file binary-dist ${installDir}/${builtins.baseNameOf file}" >> "$out/nix-support/hydra-build-products"
          '') filesToInstall}
          runHook postInstall
        '';

        dontStrip = true;

        meta =
          with prev.buildPackages.lib;
          {
            homepage = "http://www.denx.de/wiki/U-Boot/";
            description = "Boot loader for embedded systems";
            license = licenses.gpl2;
            maintainers = with maintainers; [
              bartsch
              dezgeg
              samueldr
              lopsided98
            ];
          }
          // extraMeta;
      }
      // builtins.removeAttrs args [ "extraMeta" ]
    );

in
{
  meson64-tools = meson64-tools;

  firmwareOdroidC4 = firmwareOdroidC4;

  ubootOdroidC4 = buildUBoot {
    defconfig = "odroid-c4_defconfig";

    postBuild = ''
      ${final.meson64-tools}/bin/pkg --type bl30 --output bl30_new.bin \
        ${final.firmwareOdroidC4}/bl30.bin ${final.firmwareOdroidC4}/bl301.bin
      ${final.meson64-tools}/bin/pkg --type bl2 --output bl2_new.bin \
        ${final.firmwareOdroidC4}/bl2.bin ${final.firmwareOdroidC4}/acs.bin

      ${final.meson64-tools}/bin/bl30sig --input bl30_new.bin \
        --output bl30_new.bin.g12a.enc --level v3
      ${final.meson64-tools}/bin/bl3sig --input  bl30_new.bin.g12a.enc \
        --output bl30_new.bin.enc --level v3 --type bl30
      ${final.meson64-tools}/bin/bl3sig --input ${final.firmwareOdroidC4}/bl31.img \
        --output bl31.img.enc --level v3 --type bl31
      ${final.meson64-tools}/bin/bl3sig --input u-boot.bin --compress lz4 \
        --output bl33.bin.enc --level v3 --type bl33 --compress lz4
      ${final.meson64-tools}/bin/bl2sig --input bl2_new.bin \
        --output bl2.n.bin.sig

      ${final.meson64-tools}/bin/bootmk --output u-boot.bin \
        --bl2 bl2.n.bin.sig --bl30 bl30_new.bin.enc --bl31 bl31.img.enc --bl33 bl33.bin.enc \
        --ddrfw1 ${final.firmwareOdroidC4}/ddr4_1d.fw \
        --ddrfw2 ${final.firmwareOdroidC4}/ddr4_2d.fw \
        --ddrfw3 ${final.firmwareOdroidC4}/ddr3_1d.fw \
        --ddrfw4 ${final.firmwareOdroidC4}/piei.fw \
        --ddrfw5 ${final.firmwareOdroidC4}/lpddr4_1d.fw \
        --ddrfw6 ${final.firmwareOdroidC4}/lpddr4_2d.fw \
        --ddrfw7 ${final.firmwareOdroidC4}/diag_lpddr4.fw \
        --ddrfw8 ${final.firmwareOdroidC4}/aml_ddr.fw \
        --ddrfw9 ${final.firmwareOdroidC4}/lpddr3_1d.fw \
        --level v3
    '';

    filesToInstall = [
      "u-boot.bin"
      "${final.firmwareOdroidC4}/sd_fusing.sh"
    ];
    extraMeta.platforms = [ "aarch64-linux" ];
  };
}
