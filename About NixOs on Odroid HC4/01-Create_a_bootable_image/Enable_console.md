# Odroid HC4 NixOS Migration — Full Context Summary

## Hardware & Goal

- **Device:** Hardkernel ODROID HC4
- **SoC:** Amlogic Meson SM1 (S905X3, G12A), aarch64
- **Goal:** Build a reproducible NixOS SD image for the HC4, migrating from a working Armbian system
- **Armbian reference kernel:** `6.18.10-current-meson64` (custom kernel with working HDMI/display support)

## Project Structure

```
/home/jgetreu/dev2/Armbian2Nixos-migration/
├── build/odroidhc4/
│   ├── flake.nix               # Flake: nixosSystem, packages, devShells
│   ├── configuration.nix       # NixOS system config (main config)
│   ├── README.md               # Extensive build docs
│   ├── flake.lock              # nixpkgs nixos-25.11
│   ├── serial-console-params.txt
│   ├── blob/
│   │   ├── arbian-fip-extraction.md
│   │   └── armbian-fip-odroid-hc4.bin   # Prebuilt FIP (1.3 MB)
│   └── overlay/
│       └── odroid-c4.nix       # Overlay: u-boot-odroid-c4 from FIP
├── scripts/                    # empty
├── result/                     # empty
├── Images/                     # empty
├── ROOT/                       # empty
└── About NixOs on Odroid HC4/  # Historical notes/documentation
```

## Current Build Architecture

The build uses:

- **nixpkgs nixos-25.11** (commit `d7a713c0`, lastModified `1778737229`)
- **Cross-compilation:** builds aarch64 kernel/initrd on x86_64 host via `nixpkgs.crossSystem`
- **Kernel:** Uses the **mainline NixOS kernel** (current stable from nixpkgs, likely 6.12.x or similar) — NOT a meson-specific kernel
- **Device tree:** `meson-sm1-odroid-hc4.dtb` (from kernel dtbs, at `dtbs/amlogic/meson-sm1-odroid-hc4.dtb`)

### SD Image Layout (matches Armbian)

| Sector | Content                      | Notes                                                     |
| ------ | ---------------------------- | --------------------------------------------------------- |
| 0      | MBR (partition table)        | type 0x83 Linux, sig 0x55aa                               |
| 1-2586 | U-Boot FIP (~1.3 MB)         | magic `f0 f1 2e ef`, extracted from working Armbian image |
| 8192+  | Single ext4 partition (root) | LABEL=NIXOS_SD                                            |

**No FAT32 partition.** All boot files live on ext4 at `/boot/`:

- `Image` — kernel
- `initrd` — initramfs
- `boot/dtb/meson-sm1-odroid-hc4.dtb` — device tree
- `boot.scr` — compiled U-Boot boot script

### Boot Script (boot.cmd → boot.scr)

The boot script loaded by U-Boot:

```
setenv bootargs "console=ttyS0,115200n8 console=tty0 root=LABEL=NIXOS_SD rw rootwait rootfstype=ext4"
load mmc 0:1 0x34000000 /boot/Image
load mmc 0:1 0x04080000 /boot/dtb/meson-sm1-odroid-hc4.dtb
load mmc 0:1 0x32000000 /boot/initrd
booti 0x34000000 0x32000000 0x04080000
```

Memory addresses chosen above the 1.3 MB FIP to avoid overlap.

## Current `configuration.nix` Content

```nix
{ config, lib, pkgs, sdImageModule, ... }:
let
  dtbFile = "meson-sm1-odroid-hc4.dtb";
  kernelAddr = "0x34000000";
  fdtAddr = "0x04080000";
  ramdiskAddr = "0x32000000";
in
{
  system.stateVersion = "25.11";

  # No grub, no extlinux
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = false;

  # Kernel parameters (LATEST — HDMI doesn't work, serial doesn't work)
  boot.kernelParams = [
    "console=tty0"
    "root=LABEL=NIXOS_SD"
    "rootfstype=ext4"
    "rootwait"
  ];

  # Hardware
  hardware.deviceTree.filter = dtbFile;

  hardware.fancontrol.enable = lib.mkDefault true;
  hardware.fancontrol.config = lib.mkDefault ''...'';

  # Filesystems
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
  };

  # SD Image module
  imports = [ sdImageModule ];
  sdImage = {
    rootVolumeLabel = "NIXOS_SD";
    compressImage = true;
    expandOnBoot = true;
    populateRootCommands = ''
      mkdir -p ./files/boot/dtb
      cp ${config.boot.kernelPackages.kernel}/Image           ./files/boot/Image
      cp ${config.boot.kernelPackages.kernel}/dtbs/amlogic/${dtbFile} ./files/boot/dtb/${dtbFile}
      cp ${config.system.build.initialRamdisk}/initrd        ./files/boot/initrd
      cp ${bootScript}                                        ./files/boot/boot.scr
    '';
  };

  # Custom single-partition image assembly
  system.build.finalSdImage = pkgs.stdenv.mkDerivation {
    # MBR + FIP + ext4 rootfs → zstd compressed .img.zst
    # (see full source in configuration.nix installPhase)
  };

  # Networking
  networking.interfaces.eth0.useDHCP = true;
  users.users.root.initialPassword = "nixos";
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "yes";

  # IP print service
  systemd.services.print-ip = { ... };

  # Console login
  # getty@tty1 — ENABLED
  # getty@ttyS0 — ENABLED at 115200 baud
  systemd.services."getty@tty1" = { enable = true; };
  systemd.services."getty@ttyS0" = {
    enable = true;
    serviceConfig.ExecStart = lib.mkForce [
      ""
      "${pkgs.util-linux}/bin/agetty --login-program ${pkgs.shadow}/bin/login 115200 ttyS0 vt102"
    ];
  };

  # Login banner
  environment.etc."issue".text = ''
    ========================================
    Odroid HC4  |  NixOS
    Serial:   ttyS0  115200 baud  8N1
    Display:  tty1            (HDMI)
    Network:  eth0 (DHCP)
    ========================================
  '';

  time.timeZone = "UTC";
}
```

## Key Configuration Changes (from Armbian)

### What was changed and why:

| Change            | From                                              | To                                                     | Reason                                      |
| ----------------- | ------------------------------------------------- | ------------------------------------------------------ | ------------------------------------------- |
| Serial getty baud | 9600                                              | 115200                                                 | HC4 serial console needs 115200 baud        |
| Network DHCP      | `useDHCP = true` (global)                         | `interfaces.eth0.useDHCP = true`                       | Global doesn't create `dhcpcd@eth0.service` |
| IP print service  | `after = ["networking.service" "dhcpcd.service"]` | `after = ["network-pre.target" "dhcpcd@eth0.service"]` | `dhcpcd@eth0.service` is the correct unit   |

### Critical Armbian config found in migration notes:

```
/etc/modprobe.d/blacklist-odroidhc4.conf
blacklist simpledrm
```

Armbian explicitly blacklists `simpledrm` — this driver is known to cause display issues on the Odroid HC4.

## The Boot Problem (HDMI Display)

### Symptom

When booting the NixOS SD image on the Odroid HC4 with HDMI connected:

1. ✅ U-Boot messages appear on HDMI (display hardware works)
2. ✅ "Starting kernel..." appears briefly (early printk works)
3. ❌ After "Starting kernel...", **nothing else appears on HDMI**
4. ✅ System IS fully booted — **blue LED is blinking** (system is running)
5. ✅ SSH works (root/nixos)
6. ❌ No `login:` prompt appears on HDMI

### What was tried (all failed):

1. `console=tty0` — kernel doesn't route to the display driver
2. `console=tty1` — same issue
3. Multiple `console=ttyN` parameters — same issue
4. `getty@tty1` enabled — getty runs but nothing shows on display
5. All VTs gettys (tty1-tty6) — same issue
6. `loglevel=7`, `panic=10` — no visible change
7. Adding `meson-drm` to `initrd.kernelModules` — didn't work

### Root Cause

**The mainline NixOS kernel from nixpkgs does NOT have working HDMI/display support for the Odroid HC4's Amlogic SM1 SoC.**

- The early printk path (direct hardware access) works, which is why "Starting kernel..." appears
- But the proper DRM/display driver (`meson-drm`) doesn't initialize or produce output
- The kernel falls back to serial console (ttyS0), so nothing more appears on HDMI
- **Armbian uses a custom kernel** (`6.18.10-current-meson64`) with proper meson-drm support — this is what makes HDMI work in Armbian

### What's needed

A kernel package with proper Amlogic SM1 display support. Options:

1. **Armbian kernel package** — `6.18.10-current-meson64` has working HDMI, but needs to be found in nixpkgs or built
2. **Custom kernel overlay** — build a kernel with the right config options for meson-drm
3. **Accept the limitation** — use SSH only, no HDMI console

## Current System State (Flashed Image)

The user has flashed the latest image to SD card. The system:

- ✅ Boots successfully (LED blinking)
- ❌ DHCP does NOT obtain a lease on eth0 — no network connectivity
- ❌ SSH NOT accessible (no IP address assigned)
- ❌ HDMI display shows only "Starting kernel..." then freezes
- ❌ No login prompt on HDMI
- ❌ No serial console access available

## DHCP / Network Problem

### Symptom

After booting the NixOS SD image on the Odroid HC4:

- ❌ No DHCP lease obtained on eth0
- ❌ No network connectivity at all
- ❌ Cannot SSH in (no IP address)
- The system boots (blue LED blinking), but eth0 has no IP

### What was configured

```nix
networking.interfaces.eth0.useDHCP = true;
```

This should enable `dhcpcd@eth0.service` which runs `dhcpcd` on eth0.

### Possible causes to investigate

1. **eth0 interface not coming up** — Check `ip addr show` and `dmesg | grep -i eth` to see if the interface exists
2. **PHY driver missing** — The initrd may lack the Realtek PHY driver (`rtl8211e` or similar)
3. **Device tree mismatch** — The Amlogic SM1 ethernet controller may not be properly enabled in the DTB
4. **dhcpcd service not starting** — Check `systemctl status dhcpcd@eth0` to see if the service is running
5. **Interface name mismatch** — Armbian on similar hardware uses `end0` instead of `eth0` (check with `ip link`)
6. **Link not up** — No physical link? Check LED on ethernet port

### Debugging commands (via serial console or once network works)

```bash
# Check if eth0 exists
ip link show

# Check kernel messages about the ethernet controller
journalctl -k | grep -iE 'eth|emac|macb|stmmac|realtek|phy'

# Check dhcpcd status
systemctl status dhcpcd@eth0
journalctl -u dhcpcd@eth0

# Manually bring up interface
dhclient eth0 -v
# or
systemctl start dhcpcd@eth0
```

## What Needs to Happen Next

The priority is **fixing network connectivity** so the device can be accessed remotely. The user needs to investigate:

1. **Interface name** — Does the kernel name it `eth0` or something else? (`ip link show`)
2. **Ethernet controller driver** — Is the MACB/GMAC controller recognized in dmesg?
3. **PHY driver** — Is the Realtek PHY being probed? (`dmesg | grep phy`)
4. **Initrd kernel modules** — Does the initrd contain the ethernet/PHY modules?
5. **DHCP client** — Is dhcpcd@eth0.service starting? Any error messages?

Once network works, then address the HDMI/display support issues separately.

## Build Commands

```bash
cd /home/jgetreu/dev2/Armbian2Nixos-migration/build/odroidhc4

# Validate config
nix build .#checks.x86_64-linux.nixosConfig

# Build SD image
nix build .#sdImage

# Decompress
zstd -d --no-progress result/odroid-hc4-nixos.img.zst -o /tmp/odroid-hc4-nixos.img

# Flash
sudo dd if=/tmp/odroid-hc4-nixos.img of=/dev/sdX bs=4M conv=fsync status=progress
sudo sync
```

## SSH Access

- **SSH:** `ssh root@<odroid-ip>`
- **Password:** `nixos`
- **Find IP:** check router DHCP table or `nmap -sn 192.168.x.0/24`

---

_This file was generated by the agent session to preserve all context for a future agent that can continue working on this project._
