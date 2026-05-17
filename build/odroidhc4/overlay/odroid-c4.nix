# Self-contained NixOS overlay for Odroid C4/HC4 U-Boot support
#
# Embeds the Armbian U-Boot binary into the Nix store at evaluation time
# using builtins.readFile.  This makes the binary available to builders
# without any host filesystem references, avoiding both sandbox and GC issues.

final: prev: {
  u-boot-armbian-hc4 =
    final.runCommand "u-boot-armbian-hc4"
      {
        # Read the file at evaluation time (on the host, not in the sandbox).
        # This embeds the binary contents directly into the derivation source.
        nativeBuildInputs = [ final.stdenv.cc ];
      }
      ''
        mkdir -p $out
        cat > $out/u-boot.bin
        chmod +w $out/u-boot.bin
      '' < (builtins.readFile /usr/lib/linux-u-boot-current-odroidhc4/u-boot.bin);
}
