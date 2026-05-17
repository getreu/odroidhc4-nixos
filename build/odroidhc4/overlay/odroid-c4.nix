# Self-contained NixOS overlay for Odroid C4/HC4 U-Boot support
#
# Embeds the Armbian U-Boot binary into the Nix store at evaluation time
# using builtins.readFile. proper Nix derivation using
# allowForeignPaths.  This reads the file directly from the host
# filesystem at build time rather than referencing a hardcoded store
# path that can be garbage collected.
#
# The file is read from the Armbian installation at:
#   /usr/lib/linux-u-boot-current-odroidhc4/u-boot.bin

final: prev: {
  u-boot-armbian-hc4 = final.runCommandLocal "u-boot-armbian-hc4" { } ''
    mkdir -p $out
    cp /usr/lib/linux-u-boot-current-odroidhc4/u-boot.bin $out/u-boot.bin
  '';
}
