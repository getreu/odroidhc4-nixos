# Self-contained NixOS overlay for Odroid C4/HC4 U-Boot support
#
# Wraps the Armbian U-Boot binary into a proper Nix derivation using
# stdenv.mkDerivation with enableSandbox = false.  This allows the
# builder to access the hardcoded Nix store path that was added with
# `nix-store --add-fixed sha256`.
#
# The u-boot.bin file must already be present in the Nix store at
# /nix/store/yhq8qb5rlwg9mhi47mfpq149jh8m1mll-u-boot.bin on the
# build host (the Odroid HC4 running Armbian).

final: prev: {
  u-boot-armbian-hc4 = final.stdenv.mkDerivation {
    name = "u-boot-armbian-hc4";
    enableSandbox = false;
    phases = [ "installPhase" ];
    installPhase = ''
      mkdir -p $out
      cp /nix/store/yhq8qb5rlwg9mhi47mfpq149jh8m1mll-u-boot.bin $out/u-boot.bin
    '';
  };
}
