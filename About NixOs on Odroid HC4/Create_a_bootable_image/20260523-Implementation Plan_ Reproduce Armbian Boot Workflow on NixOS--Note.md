---
title:        '## Implementation Plan: Reproduce Armbian Boot Workflow on NixOS'
subtitle:     Note
author:       Jgetreu
date:         2026-05-23
lang:         en-US
---

## Implementation Plan: Reproduce Armbian Boot Workflow on NixOS

### Problem Summary

| | Armbian (booting) | Current NixOS (not booting) |
|---|---|---|
| **Sector 1 FIP** | `f0 f1 2e ef` (mainline U-Boot + ext4) | `c8 e6 c3 d7` (Hardkernel, FAT32 only) |
| **Partitions** | Single ext4 | FAT32 + ext4 |
| **boot.scr** | `/boot/boot.scr` on ext4 | FAT32 root |
| **Kernel** | `/boot/vmlinuz-...` on ext4 | FAT32 root (`/Image`) |

### Root Cause

The NixOS build uses a **prebuilt Hardkernel blob** that only supports FAT32. Armbian **builds its own FIP from upstream U-Boot** with ext4 support, properly assembled with `aml_encrypt_g12a` — the same method the HC4 ROM bootloader expects.

### The Key: The "repro" Approach That Was Already Working

Commit `2821715` shows a working `buildUBoot` approach that:
1. Fetches **LibreELEC/amlogic-boot-fip** (the same firmware blobs Armbian/Hardkernel use)
2. Builds **upstream U-Boot** from nixpkgs with `odroid-c4_defconfig`
3. **Assembles the FIP** in `postBuild` using `aml_encrypt_g12a --bootmk`
4. Produces a ROM-accepted FIP with ext4 support

This was deleted in `086f7f9` ("Remove failing build") but the code is still in git history and should be restored.

---

### Step 1: Restore the U-Boot Overlay

Restore `build/odroidhc4/overlay/odroid-c4.nix` from the repro version (commit `2821715`), with these updates:

**What to change from the old version:**
- Update `amlogic-boot-fip` rev if the LibreELEC repo has changed
- Ensure cross-compilation works with current nixpkgs 25.11
- Verify the `odroid-c4_defconfig` still applies to the G12B (S905X2) SoC in the HC4 (HC4 uses G12A S905X3, C4 defconfig was correct)

**What stays the same:**
- `final.buildUBoot` with `odroid-c4_defconfig`
- `amlogic-boot-fip-odroid-c4` from LibreELEC
- `postBuild` that runs `acs_tool.py` → `blx_fix.sh` → `aml_encrypt_g12a --bootmk`
- Cross-compilation via `pkgsCross.aarch64-multiplatform.stdenv` on x86_64

### Step 2: Switch Configuration to ext4 Boot

In `build/odroidhc4/configuration.nix`:

**Change:**
- **Remove FAT32 partition** — set `sdImage.firmwareSize = 0` or use single-partition layout
- **Place boot files on ext4** at `/boot/`:
  ```nix
  populateFirmwareCommands = ''
    cp ${config.boot.kernelPackages.kernel}/Image firmware/boot/Image
    cp ${config.boot.kernelPackages.kernel}/dtbs/${dtbFile} firmware/boot/dtb/${dtbFile}
    cp ${config.system.build.initialRamdisk}/initrd firmware/boot/initrd
    cp ${bootScript} firmware/boot/boot.scr
    cp ${uBootFip}/u-boot.bin firmware/boot/u-boot.bin
  '';
  ```
- **Update boot.cmd** to load from ext4 instead of FAT32:
  ```bash
  setenv bootargs "console=ttyS0,115200n8 console=tty0 root=LABEL=NIXOS_SD rw rootwait rootfstype=ext4"
  load mmc 0:1 ${kernelAddr} /boot/Image
  load mmc 0:1 ${fdtAddr} /boot/dtb/${dtbFile}
  load mmc 0:1 ${ramdiskAddr} /boot/initrd
  booti ${kernelAddr} ${ramdiskAddr}:${filesize} ${fdtAddr}
  ```
- **Disable extlinux** (not needed when using U-Boot's `boot.scr`)

**Remove:**
- `boot.loader.generic-extlinux-compatible.enable`
- FAT32 partition configuration
- `postBuildCommands` that writes U-Boot FIP to sector 1 (the `buildUBoot` derivation handles this)

### Step 3: Write FIP to Sector 1 in SD Image Build

In `sdImage.postBuildCommands`:
```nix
postBuildCommands = ''
  # Write U-Boot FIP to sector 1 of the SD image
  dd if=./firmware/u-boot.bin of=$img bs=512 seek=1 conv=notrunc
'';
```

### Step 4: Verify FIP Magic Bytes

After building, verify:
```bash
dd if=nixos-image-sd-card.img bs=512 skip=1 count=4 2>/dev/null | od -A n -t x1 | head -1
# Expected: f0 f1 2e ef (not c8 e6 c3 d7)
```

### Step 5: Build and Test

```bash
cd build/odroidhc4
nix build .#sdImage

# Decompress
zstd -dc result/sd-image/*.img.zst | dd of=/dev/sdX bs=4M status=progress

# On hardware:
# - Blue LED blinking = ✅ U-Boot found boot.scr
# - Serial console shows U-Boot booting from ext4
# - Kernel boots from ext4 partition
```

### Implementation Order

1. **First** — Restore and verify the overlay builds (just `nix build .#u-boot`)
2. **Second** — Update configuration for ext4 boot, verify config evaluates
3. **Third** — Build full SD image, verify FIP magic bytes
4. **Fourth** — Flash to SD card, test boot on hardware
5. **Fifth** — If boot.scr isn't found, add debug output to serial console

### Risks and Mitigations

| Risk | Mitigation |
|---|---|
| `amlogic-boot-fip` repo changed/hashed wrong | Check LibreELEC repo, update hash |
| `odroid-c4_defconfig` doesn't work for HC4 (G12B vs G12A) | Use `meson-sm1-odroid-hc4.dtb` — the SoC is G12A (S905X3) in the HC4, C4 defconfig is correct |
| Cross-compilation fails | The repro approach already handles this; test on x86_64 first |
| ext4 in U-Boot needs specific config | `odroid-c4_defconfig` from nixpkgs includes ext4; verify with `grep CONFIG_FS_EXT4` |

### Why This Works

The Armbian boot workflow is:
1. **ROM bootloader** → accepts any FIP with `0xd7c3e6c8` (Amlogic encryption marker) at sector 1
2. **Armbian's FIP** (`f0 f1 2e ef`) = upstream U-Boot + encrypted BL2/BL30/BL31/BL33, assembled by `aml_encrypt_g12a`
3. **U-Boot with ext4** → reads `boot.scr` from ext4 partition
4. **boot.scr** → loads kernel/initrd/dtb from ext4, boots with `booti`

The **repro overlay** does exactly steps 2-3 in the Nix build, producing the same FIP format that Armbian uses.

