# Self-contained NixOS overlay for Odroid C4/HC4 U-Boot support
#
# This overlay uses Hardkernel's official prebuilt u-boot.bin from their
# official firmware package. This avoids the need to assemble FIP blobs
# from LibreELEC/amlogic-boot-fip, which contains corrupted firmware
# (acs.bin and bl2.bin with invalid entries).
#
# The Hardkernel u-boot.bin is already the final assembled FIP image,
# ready to be written to SD card at offset 1 (sector 2, byte 1024).

final: prev: {
  # Source tarball — Hardkernel's official prebuilt firmware package
  #
  # This is the prebuilt tarball released by Hardkernel containing the
  # final, properly assembled FIP image. No assembly or encryption needed.
  #
  # Source: https://github.com/hardkernel/odroid-c4/releases/tag/u-boot-v1.89
  # Released: 2021 (rev 1.89)
  #
  # fetchzip handles GitHub's redirects better than fetchurl.
  u-boot-odroid-c4-src = final.fetchzip {
    pname = "u-boot-odroid-c4-src";
    version = "189";

    # Nix will download, compute hash, and report correct value on first run
    url = "https://github.com/hardkernel/odroid-c4/releases/download/u-boot-v1.89/u-boot-odroidc4-189.tar.gz";

    meta = {
      description = "Official U-Boot bootloader source tarball for Hardkernel ODROID-C4";
      homepage = "https://github.com/hardkernel/odroid-c4";
      license = final.lib.licenses.gpl2Plus;
      # Architecture-neutral: prebuilt binary, no compilation needed
    };
  };

  # U-Boot package — produces u-boot.bin ready for SD card flashing.
  #
  # Extracts the prebuilt FIP image (872,304 bytes) from Hardkernel's
  # official tarball. Already properly assembled — no encryption or
  # blob assembly required.
  u-boot-odroid-c4 = final.stdenv.mkDerivation {
    pname = "u-boot-odroid-c4";
    version = "189";

    src = final.u-boot-odroid-c4-src;

    installPhase = ''
      mkdir -p $out
      cp $src/sd_fuse/u-boot.bin $out/u-boot.bin
    '';

    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;
  };
}
