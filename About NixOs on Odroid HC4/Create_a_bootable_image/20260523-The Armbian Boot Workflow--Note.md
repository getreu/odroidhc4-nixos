---
title:        'The Armbian Boot Workflow'
subtitle:     Note
author:       Jgetreu
date:         2026-05-23
lang:         en-US
---

## The Armbian Boot Workflow

### 1. Sector 1: Custom Mainline FIP
| Magic | Origin |
|---|---|
| `f0 f1 2e ef` | Armbian's own signed FIP built from **mainline U-Boot** with ext4 support |

This is NOT the Hardkernel blob. Armbian builds its own FIP that the ROM bootloader accepts, but which has ext4 filesystem support compiled in.

### 2. Partition Layout: Single ext4
```
ext4    sector 8192+      (29.4 GB) — label "ROOTFS"
```
No FAT32 partition at all. Everything is on one ext4 partition.

### 3. Boot Script Location: `/boot/boot.cmd` → `/boot/boot.scr`
The file `/tmp/armbian-root/boot/boot.cmd` contains:
```bash
setenv initrd_high 0x20000000
setenv fdt_high 0x20000000
setenv disable_uboot_add_serial "false"
setenv disable_uboot_earlycon "false"
setenv stdout serial,vidconsole
setenv stdin serial,stdin

setenv verbosity "1"

setenv console "console=ttyS0/115200n8 console=tty0"
setenv disallow_reboot "reboot=hard"
setenv rootdev "/dev/${{interface}}0p1"
setenv rootfstype "ext4"
setenv rootflags "discard"
setenv default_bootfile "auto"
```

This is a **parameter initialization script** — it sets up environment variables. The actual kernel loading happens via `bootm` commands later (likely from `/boot/uEnv.txt` or an embedded U-Boot script).

### 4. Kernel and Initrd Locations
```
/tmp/armbian-root/boot/vmlinuz-6.18.10-current-meson64
/tmp/armbian-root/boot/initrd.img-6.18.10-current-meson64
/tmp/armbian-root/boot/dtb/
/tmp/armbian-root/boot/dtb/amlogic/meson-sm1-odroid-hc4.dtb
```

### 5. No extlinux.conf
Armbian doesn't use extlinux. It uses U-Boot's native `boot.scr` approach with `bootm` or `booti` commands.

## The Key Difference

| | Armbian | Current NixOS |
|---|---|---|
| **FIP at sector 1** | `f0 f1 2e ef` (mainline U-Boot + ext4) | `c8 e6 c3 d7` (Hardkernel, FAT32 only) |
| **Partition layout** | Single ext4 | FAT32 + ext4 |
| **boot.scr location** | `/boot/boot.scr` on ext4 | FAT32 root |
| **Kernel location** | `/boot/vmlinuz-...` on ext4 | FAT32 root (`/Image`) |
| **Initrd location** | `/boot/initrd.img-...` on ext4 | FAT32 root (`/initrd`) |

The **root blocker** is that we don't have `ubootOdroidC4` in nixpkgs, so we can't build Armbian's custom FIP from mainline U-Boot source. We're forced to use the Hardkernel blob which only knows FAT32.

## What Would Need to Change to Reproduce Armbian's Workflow

1. **Add `ubootOdroidC4` to nixpkgs** — build U-Boot from source for Odroid C4 with ext4 support
2. **Build Armbian's FIP** — create the signing wrapper that makes mainline U-Boot accepted by the ROM bootloader
3. **Remove FAT32 partition** — go back to single ext4 layout
4. **Place boot files on ext4** — `/boot/boot.scr`, `/boot/vmlinuz-...`, `/boot/initrd.img-...`

Until then, our FAT32 workaround is the only viable path.

