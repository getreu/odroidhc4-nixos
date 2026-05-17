# Self-contained Nixpkgs overlay for Odroid C4/HC4 support
#
# NixOS 25.11 provides built-in support for Odroid C4/HC4 via:
#   - Upstream U-Boot with odroid-c4_defconfig support
#   - Device tree: meson-sm1-odroid-hc4.dtb
#   - SD image module that handles firmware partition population
#
# This overlay is intentionally empty — no custom U-Boot, meson64-tools,
# or firmware derivations are needed. The sd-image module handles everything.

final: prev: { }
