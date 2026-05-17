# Self-contained NixOS overlay for Odroid C4/HC4 U-Boot support
#
# This overlay uses Hardkernel's official prebuilt u-boot.bin from their
# official firmware package. This avoids the need to assemble FIP blobs
# from LibreELEC/amlogic-boot-fip, which contains corrupted firmware
# (acs.bin and bl2.bin with invalid entries).
#
# The Hardkernel u-boot.bin is already the final assembled FIP image,
# ready to be written to SD card at offset 1 (sector 2, byte 1024).

let
  overlayDir = ./.;
  blobTarball = overlayDir + "/../blob/u-boot-odroidc4-189.tar.gz";
in
final: prev: {
  # U-Boot package — produces u-boot.bin ready for SD card flashing.
  #
  # Extracts the prebuilt FIP image (872,304 bytes) from Hardkernel's
  # official tarball (stored locally in blob/). Already properly assembled —
  # no download or encryption required.
  u-boot-odroid-c4 = final.stdenv.mkDerivation {
    pname = "u-boot-odroid-c4";
    version = "189";

    # Use local tarball directly as source
    src = blobTarball;

    # Unpack the tarball before copying
    unpackPhase = "tar xzf $src";

    installPhase = ''
      mkdir -p $out
      cp sd_fuse/u-boot.bin $out/u-boot.bin
    '';

    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;
  };
}
