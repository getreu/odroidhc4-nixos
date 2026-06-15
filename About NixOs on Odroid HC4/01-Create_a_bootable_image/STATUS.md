# NixOS HC4 Migration — Project Status

## Goal
Build a reproducible NixOS SD image for the Odroid HC4 (Amlogic S905X3 / SM1, aarch64),
migrating from a working Armbian system.

## Current State (2026-06-15) — SSH WORKING ✅

| Component | Status | Notes |
|---|---|---|
| U-Boot / boot.scr | ✅ Working | FIP at sector 1, ext4 root at sector 8192 |
| Kernel load | ✅ Working | Loads Image, DTB, initrd from ext4 root |
| NixOS activation | ✅ Working | /etc, /var, /bin all created on first boot |
| Ethernet / SSH | ✅ Working | SSH at root@192.168.12.120, password: nixos |
| HDMI console | ❌ No output | meson-drm binding fails (non-critical for NAS use) |

## How to Access

```bash
ssh root@192.168.12.120   # password: nixos
```

Static IP: `192.168.12.120/24`, gateway `192.168.12.1`.
DHCP also runs alongside the static address.

## Fixes Applied (in order)

### 1. Boot files at ext4 root, not /boot/
U-Boot's `boot.scr` must be at the partition root (`/boot.scr`), not `/boot/boot.scr`.
All boot files are at ext4 root: `/Image`, `/initrd`, `/dtb/meson-sm1-odroid-hc4.dtb`, `/boot.scr`.

### 2. Missing `init=` in kernel bootargs
**Root cause of system never activating.**

NixOS's systemd-based initramfs runs `initrd-find-nixos-closure` which reads `init=` from
the kernel command line to locate the NixOS system closure. Without it, the service fails,
`initrd-nixos-activation` never runs, and the system stays in the initramfs forever
(heartbeat LED blinks, but no /etc created on disk).

Normal NixOS ARM boards use extlinux which auto-generates `init=`. Our custom `boot.scr`
bypassed extlinux, so nothing was adding it.

**Fix:** `init=${config.system.build.toplevel}/init` added to `setenv bootargs` in `bootScript`.
`config.system.build.toplevel` expands to the exact Nix store path at build time — no
circular dependency since `system.build.toplevel` does not depend on the sdImage derivations.

### 3. Wrong serial console device (ttyS0 → ttyAML0)
The Amlogic S905X3 UART is driven by `meson_uart` → `/dev/ttyAML0`.
`ttyS0` (8250 driver) is wrong for this SoC — kernel serial output was silent.
Confirmed by comparing with Armbian's `boot.cmd` which uses `console=ttyAML0,115200`.

**Fix:** changed in `setenv bootargs` and `boot.kernelParams`:
`"console=ttyS0,115200n8"` → `"console=ttyAML0,115200"`
Also updated `getty@ttyS0` → `getty@ttyAML0`.

### 4. Missing Amlogic G12A MDIO multiplexer driver
**Root cause of `end0: cannot attach to PHY (error: -ENODEV)`.**

The RTL8211F PHY sits behind an Amlogic G12A MDIO multiplexer
(`compatible = "amlogic,g12a-mdio-mux"` at `bus@ff600000/mdio-multiplexer@4c000`).
Without the `mdio-mux-meson-g12a` module, the mux is not initialised and the PHY
is invisible on the MDIO bus.

**Fix:** added to `boot.kernelModules`:
```nix
"mdio-mux-meson-g12a"
```

## Key Files

```
build/odroidhc4/
├── configuration.nix        ← main NixOS config (edit this)
├── flake.nix                ← build entry point: nix build .#sdImage
├── overlay/odroid-c4.nix   ← U-Boot FIP package
├── blob/armbian-fip-odroid-hc4.bin  ← prebuilt FIP binary
└── result/odroid-hc4-nixos.img.zst  ← latest built image
```

## SD Image Layout

```
Sector 0:       MBR (dos partition table, type 0x83, sig 0x55aa)
Sectors 1-2586: U-Boot FIP (~1.3 MB, magic: f0 f1 2e ef)
Sectors 8192+:  Single ext4 partition (LABEL=NIXOS_SD)
```

No FAT32. Boot files at ext4 root:
- `/Image`, `/initrd`, `/boot.scr`, `/dtb/meson-sm1-odroid-hc4.dtb`

## Build & Flash Commands

```bash
cd /home/jgetreu/dev2/Armbian2Nixos-migration/build/odroidhc4

# Build
nix build .#sdImage

# Decompress
zstd -d -f result/odroid-hc4-nixos.img.zst -o /tmp/odroid-hc4-nixos.img

# Flash (SD card = /dev/sda)
sudo dd if=/tmp/odroid-hc4-nixos.img of=/dev/sda bs=4M conv=fsync status=progress
sudo sync
```

## Hardware Facts

| Component | Detail |
|---|---|
| SoC | Amlogic S905X3 (SM1 / G12A), aarch64 |
| SD card device | `/dev/mmcblk1p1` (internal eMMC = mmcblk0, SD = mmcblk1) |
| Ethernet MAC | Amlogic DWMAC (Synopsys DesignWare), `stmmac` + `dwmac_meson8b` |
| Ethernet PHY | External Realtek RTL8211F, behind `amlogic,g12a-mdio-mux` |
| PHY MDIO mux | `mdio-mux-meson-g12a` module required |
| Interface name | `end0` (renamed from eth0 by predictable network naming) |
| UART | Amlogic `meson_uart` driver → `/dev/ttyAML0` (not ttyS0) |
| MMC host | `meson-gx-mmc` built into kernel (=y), no module needed |
| DRM | `meson-drm` + `meson_dw_hdmi` + `meson-canvas` — loads but fails to bind |

## Current configuration.nix key settings

```nix
# Bootargs (in bootScript / setenv bootargs):
# "console=ttyAML0,115200 console=tty0 root=LABEL=NIXOS_SD rw rootwait rootfstype=ext4
#  init=${config.system.build.toplevel}/init"

boot.kernelParams = [
  "console=ttyAML0,115200"
  "root=LABEL=NIXOS_SD"
  "rootfstype=ext4"
  "rootwait"
  "loglevel=7"
  "console=tty0"
];

boot.initrd.kernelModules = [ "stmmac" "dwmac_meson8b" "ext4" ];

boot.kernelModules = [
  "mdio-mux-meson-g12a"  # MDIO mux for RTL8211F PHY
  "meson-canvas"
  "meson-drm"
  "meson_dw_hdmi"
];

networking.useNetworkd = true;
systemd.network.networks."10-eth" = {
  matchConfig.Type = "ether";
  networkConfig = { DHCP = "yes"; Gateway = "192.168.12.1"; DNS = "192.168.12.1"; };
  addresses = [ { Address = "192.168.12.120/24"; } ];
};

users.users.root.initialPassword = "nixos";
services.openssh.enable = true;
services.openssh.settings.PermitRootLogin = "yes";
```

## What Remains

- **HDMI console**: `meson-drm` loads but `Couldn't bind all components`. Non-critical for
  headless NAS use. Would require debugging the DRM component binding (likely `meson_ee_pwrc`
  power domain sync_state pending on hdmi-tx, pcie, vpu).
- **NAS configuration**: RAID, encryption, services — next phase.
