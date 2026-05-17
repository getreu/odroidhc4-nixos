# Self-contained NixOS overlay for Odroid C4/HC4 U-Boot support
#
# Embeds the Armbian U-Boot binary into the Nix store at evaluation time
# using builtins.readFile.  This reads the file from the host filesystem
# during evaluation (before sandboxing), embedding its contents directly
# into the derivation.  Builders then receive the file as source input
# with no host path references, avoiding both sandbox and GC issues.

final: prev: {
  u-boot-armbian-hc4 =
    let
      # Read the binary at evaluation time on the host.
      # This is safe because it runs before any sandboxing.
      uBootBin = builtins.readFile "/usr/lib/linux-u-boot-current-odroidhc4/u-boot.bin";
    in
    final.runCommand "u-boot-armbian-hc4" { } ''
      mkdir -p $out
      echo "${uBootBin}" > $out/u-boot.bin
    '';
}
