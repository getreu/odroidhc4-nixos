---
title: README
subtitle: ""
author: Jgetreu
date: 2026-05-18
lang: en-US
sort_tag: ""
---

# Reproducible Odroid HC4 NixOS SD Image

## Goal

Build a **fully reproducible** NixOS SD image for the Odroid HC4 (and compatible C4),
where the bootloader is sourced from Hardkernel's official prebuilt firmware — not
corrupted LibreELEC blobs, not hardcoded store paths.

## The Solution: Hardkernel Official Firmware

We now use Hardkernel's **official prebuilt firmware** for the ODROID-C4:

- **Source**: `https://dn.odroid.com/RK809/ODROID-C4/U-boot/u-boot-odroidc4-189.tar.gz`
- **Released**: 2023-01-10 (rev 1.89)
- **Contents**: Already-assembled FIP image (872,304 bytes), ready for SD card flashing

No blob assembly. No `aml_encrypt_g12a`. No cross-compilation. Just a verified tarball
and a file copy.

## Project Structure

```
build/odroidhc4-repro/
├── flake.nix                     # Flake: nixosSystem, packages, devShells, checks
├── configuration.nix             # NixOS config: SD image, fan, SSH, extlinux
├── overlay/
│   └── odroid-c4.nix             # U-Boot derivation (51 lines, zero deps)
└── README.md                     # This file
```

### The Overlay (`overlay/odroid-c4.nix`)

```nix
# Source: Hardkernel official firmware tarball
u-boot-odroid-c4-src = final.fetchurl {
  url = "https://dn.odroid.com/RK809/ODROID-C4/U-boot/u-boot-odroidc4-189.tar.gz";
  sha256 = "sha256-ye7bEEVS/arUJDiS53tZYddmVGRfl8Bf6dGKa4sDYgQ=";
};

# Package: extracts u-boot.bin from the tarball
u-boot-odroid-c4 = final.stdenv.mkDerivation {
  src = final.u-boot-odroid-c4-src;
  installPhase = ''
    mkdir -p $out
    cp ${src}/sd_fuse/u-boot.bin $out/u-boot.bin
  '';
  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;
};
```

### Why This Works

1. **Reproducible** — hash-verified source, deterministic output
2. **Sandboxed** — no `enableSandbox = false`, no host path references
3. **Simple** — 51 lines, zero build dependencies
4. **Official** — from Hardkernel themselves, not a third-party fork
5. **Compatible** — the ODROID-C4 and HC4 share the same SoC (Amlogic G12A/S905X3)

## Build Instructions

```bash
cd build/odroidhc4-repro

# Build U-Boot only (fast — ~5 seconds)
nix build .#u-boot

# Verify the output
ls -la result/u-boot.bin
sha256sum result/u-boot.bin
# Expected: c5535a03f5399fdd574c4e9c2c94fa554d5adf9570dac88a4999800431d6ee58

# Check and evaluate the build configuration (fast)
nix flake check
nix build .#checks.x86_64-linux.nixosConfig 2>&1

# Build the full SD image (2-3 hours minutes depending on build system)
nohup nix build .#sdImage > build.log 2>&1 &

# Open a dev shell for editing
nix develop
```

## Using the Resulting Image

After the build completes, the compressed SD image is available at:

```
result/sd-image/nixos-image-sd-card-*.img.zst
```

For example: `result/sd-image/nixos-image-sd-card-25.11.20260514.d7a713c-aarch64-linux.img.zst`

### Flash to SD Card

1. **Identify your SD card** — ensure you select the correct device:

   ```bash
   lsblk
   # Example: /dev/sdX or /dev/mmcblk0
   ```

2. **Flash the image** (replace `/dev/sdX` with your actual device):

   This lasts some minutes depending on your SD card.

   ```bash
   cd odroidhc4/result/sd-image
   SD_CARD=/dev/sdX
   IMG=$(ls nixos-image-sd-card-*.img.zst)

   # Print hash of the uncompressed image (optional)
   zstd -dc "$IMG" | sha256sum

   # Copy the image on the SD card
   zstd -dc "$IMG" | sudo dd of="$SD_CARD" bs=4M status=progress conv=fsync
   ```


### First Boot

1. Insert the SD card into the Odroid HC4
2. Connect an Ethernet cable (for headless SSH access)
3. Power on the device
4. Wait 1–2 minutes for first-boot initialization

### Default Credentials

The image uses a **NixOS flake-based configuration**. Credentials depend on your `configuration.nix`:

- **Default root**: Use the password/policy defined in your NixOS configuration
- **SSH key access**: If configured, add your public key to `~/.ssh/authorized_keys`
- **Network**: The device obtains an IP via DHCP — check your router's client list

### SSH Access

```bash
# Find the device on your network (replace with your network range)
nmap -sn 192.168.1.0/24 | grep odroid

# Or check DHCP leases on your router
# Then SSH in:
ssh root@<device-ip>
```

### Updating the Image

When you modify `configuration.nix` or `flake.nix`:

```bash
# Rebuild the SD image
nix build .#sdImage

# Flash the new image (warning: erases the card)
cd result/sd-image
IMG=$(ls nixos-image-sd-card-*.img.zst)
zstd -dc "$IMG" | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

### Expanding the Root Filesystem

If your SD card is larger than the image partition, expand the root filesystem:

```bash
# Boot from the SD card, then run:
nixos-rebuild switch --boot-device /dev/mmcblk0
```

Or manually:

```bash
sudo sgdisk -e /dev/mmcblk0   # Resize partition to fill disk
sudo e2fsck -f /dev/mmcblk0p2  # Check filesystem
sudo resize2fs /dev/mmcblk0p2  # Expand filesystem
```

## Architecture

The Odroid HC4 uses the **Amlogic G12A (S905X3)** SoC, which requires a specialized
boot flow:

1. **BL2** (bootloader stage 2) → signed with `aml_encrypt_g12a`
2. **BL30** (TrustZone firmware) → encrypted
3. **BL31** (Armv8 Trusted Firmware) → encrypted
4. **BL33** (U-Boot itself) → encrypted
5. All four assembled into a **FIP (Firmware Image Package)** by `aml_encrypt_g12a`

Hardkernel's `u-boot-odroidc4-189.tar.gz` contains the **already-assembled FIP** as
`u-boot.bin` — 872,304 bytes of properly signed/encrypted binary ready to flash to
offset 1 (sector 2) of the SD card.

No assembly needed. No encryption needed. Just copy and boot.

---

## Hardkernel Firmware Details

- **URL**: `https://dn.odroid.com/RK809/ODROID-C4/U-boot/u-boot-odroidc4-189.tar.gz`
- **Tarball contents**:
  - `sd_fuse/u-boot.bin` — the prebuilt FIP image (872,304 bytes)
  - `sd_fuse/sd_fusing.sh` — Hardkernel's SD flashing script (not used by NixOS)
- **Release date**: 2023-01-10
- **Version**: 189 (rev 1.89)
- **License**: GPL-2.0+ (as declared by Hardkernel)

The SD card flashing procedure:

```bash
lsblk
sudo dd if=u-boot.bin of=/dev/<SDCARD> conv=fsync,notrunc bs=512 seek=1
```

NixOS SD images handle this automatically via the `sdImage` module.

---

## Key Files

| File                    | Purpose                                                 |
| ----------------------- | ------------------------------------------------------- |
| `flake.nix`             | Flake definition with nixosSystem, packages, devShells  |
| `configuration.nix`     | NixOS SD image config (fan, SSH, extlinux, boot script) |
| `overlay/odroid-c4.nix` | **Core file** — U-Boot derivation (51 lines)            |

---

## Troubleshooting

### Build fails with hash mismatch

The tarball URL or hash may have changed. Verify:

```bash
curl -sI "https://dn.odroid.com/RK809/ODROID-C4/U-boot/u-boot-odroidc4-189.tar.gz"
curl -sL "https://dn.odroid.com/RK809/ODROID-C4/U-boot/u-boot-odroidc4-189.tar.gz" | sha256sum
```

Update `sha256` in `overlay/odroid-c4.nix` if the hash differs.

### Can't fetch from dn.odroid.com

The Hardkernel CDN may be slow or blocked. Alternatives:

- Download the tarball manually and use `nix build --argstr src /path/to/file`
- Mirror to a reliable CDN (GitHub Releases, etc.)
- Ask Hardkernel for a mirror

### U-Boot won't boot after flashing

Verify the binary:

```bash
sha256sum result/u-boot.bin
# Expected: c5535a03f5399fdd574c4e9c2c94fa554d5adf9570dac88a4999800431d6ee58
# Size: 872304 bytes
```

If the hash doesn't match, the build is using corrupted data.
