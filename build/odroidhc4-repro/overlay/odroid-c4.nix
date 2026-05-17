# Self-contained NixOS overlay for Odroid C4/HC4 U-Boot support
#
# This creates a proper buildable U-Boot derivation using the same
# amlogic-boot-fip blobs that the odroid-c4/odroid-hc4 directories
# in LibreELEC/amlogic-boot-fip use.
#
# The HC4 and C4 share the same Amlogic G12A (S905X3) SoC, so the
# C4 defconfig and blobs work for both boards.
#
# Cross-compilation support:
# - On x86_64 hosts, uses pkgsCross.aarch64-multiplatform.stdenv to cross-compile U-Boot for aarch64
# - On aarch64 hosts (native), uses the native stdenv
# - Host tools (aml_encrypt_g12a, acs_tool.py, blx_fix.sh) are fetched via buildPackages
#   so they work on the build host regardless of target architecture

final: prev: {
  # Firmware blobs for Amlogic G12A (S905X3) from LibreELEC/amlogic-boot-fip
  # This provides architecture-neutral firmware blobs and x86_64 host tools
  # needed during the build (aml_encrypt_g12a, acs_tool.py, blx_fix.sh).
  # Defined in final so it's available via both final and buildPackages
  # for proper cross-compilation support.
  amlogic-boot-fip-odroid-c4 = final.fetchFromGitHub {
    owner = "LibreELEC";
    repo = "amlogic-boot-fip";
    rev = "4369a138ca24c5ab932b8cbd1af4504570b709df";
    sha256 = "sha256-VZBd3vqNgA+7EIHoinnkury4cpeCCa4OeoP1HIaL6DI=";
    postFetch = ''
      find $out -mindepth 1 -maxdepth 1 -type d ! -name "odroid-c4" ! -name "odroid-hc4" -exec rm -rf {} +
    '';
    meta.license = final.lib.licenses.unfreeRedistributableFirmware;
  };

  # Build U-Boot for Odroid C4/HC4 from source with proper FIP assembly.
  # Works for both native aarch64 builds and cross-compilation from x86_64.
  # For cross-compilation from x86_64, we pass a cross-compiled stdenv
  # since buildUBoot does not accept crossSystem/crossSystemConfig parameters.
  u-boot-odroid-c4 = final.buildUBoot {
    pname = "u-boot-odroid-c4";

    # Use a cross-compiled stdenv when building on x86_64 hosts.
    # When building on aarch64 or as part of a cross-compiled NixOS system,
    # final.stdenv is already aarch64 so we fall through to the native stdenv.
    stdenv =
      if final.stdenv.hostPlatform.system == "x86_64-linux" then
        final.pkgsCross.aarch64-multiplatform.stdenv
      else
        final.stdenv;

    meta.longDescription = ''
      Boot loader for the Hardkernel ODROID-C4/HC4.

      The HC4 and C4 share the same Amlogic G12A (S905X3) SoC, so the
      C4 defconfig works for both boards. This build uses the same
      amlogic-boot-fip blobs that LibreELEC uses.

      The build requires meson-tools (from buildPackages) to run aml_encrypt_g12a
      on the build host to assemble the final FIP binary.
    '';

    filesToInstall = [ "u-boot.bin" ];
    defconfig = "odroid-c4_defconfig";

    # G12A (S905X3) requires ATF for BL31 and encrypted boot blobs.
    # Host tools needed during the build (not for the target):
    # - bison/flex: U-Boot's config parser generator (HOSTCC tools)
    # - openssl: U-Boot's image tools (kwbimage, imx8mimage, imagetool)
    #   need openssl/evp.h for HOSTCC compilation
    # - python3: acs_tool.py and related build scripts
    # make is provided by stdenv and does not need to be listed.
    # These must come from buildPackages for proper cross-compilation.
    # U-Boot's buildUBoot function adds toolsDeps (ncurses, libuuid, gnutls, openssl)
    # to nativeBuildInputs when crossTools=false (default). When using a cross-compiled
    # stdenv, those get resolved as aarch64 packages — but HOSTCC tools need native.
    # We explicitly pull all toolsDeps from buildPackages to ensure they run on x86_64.
    nativeBuildInputs = with final.buildPackages; [
      bison
      flex
      openssl
      gnutls
      ncurses
      util-linux
      python3
    ];

    postBuild = ''
      # Copy firmware blobs and host tools from buildPackages.
      # Blobs are architecture-neutral; aml_encrypt_g12a is an x86_64 host binary.
      # Note: bl21.bin is NOT in the repo - blx_fix.sh generates it from bl2.bin + acs.bin
      mkdir -p $out tmp
      FIP=${final.buildPackages.amlogic-boot-fip-odroid-c4}/odroid-c4
      cp $FIP/{bl2.bin,bl30.bin,bl301.bin,bl31.img,blx_fix.sh,acs_tool.py,aml_encrypt_g12a,acs.bin} \
         u-boot.bin tmp/
      cd tmp

      # Process BL2: run acs_tool first (generates acs.bin), then blx_fix.sh
      # blx_fix.sh internally handles BL21 generation from bl2.bin + acs.bin
      python3 acs_tool.py bl2.bin bl2_acs.bin acs.bin 0
      bash -e blx_fix.sh bl2_acs.bin zero bl2_zero.bin acs.bin acs_zero.bin bl2_new.bin bl2
      [ -f zero ] && rm -f zero

      # Process BL30 (fix)
      bash -e blx_fix.sh bl30.bin zero bl30_zero.bin bl301.bin bl301_zero.bin bl30_new.bin bl30
      [ -f zero ] && rm -f zero

      # Encrypt BL2, BL30, BL31, and BL33 (U-Boot)
      ./aml_encrypt_g12a --bl2sig --input bl2_new.bin --output bl2.n.bin.sig
      ./aml_encrypt_g12a --bl3enc --input bl30_new.bin --output bl30_new.bin.enc
      ./aml_encrypt_g12a --bl3enc --input bl31.img --output bl31.img.enc
      ./aml_encrypt_g12a --bl3enc --input u-boot.bin --output bl33.bin.enc

      # Assemble final FIP image
      ./aml_encrypt_g12a --bootmk --output $out/u-boot.bin \
        --bl2 bl2.n.bin.sig --bl30 bl30_new.bin.enc --bl31 bl31.img.enc --bl33 bl33.bin.enc
    '';
  };
}
