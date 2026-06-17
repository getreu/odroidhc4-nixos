# NixOS HC4 Migration — Project Status

## Goal
Build a reproducible NixOS SD image for the Odroid HC4 (Amlogic S905X3 / SM1, aarch64),
migrating from a working Armbian system.

## Current State (2026-06-17) — SSH WORKING ✅

| Component | Status | Notes |
|---|---|---|
| U-Boot / boot.scr | ✅ Working | FIP at sector 1, ext4 root at sector 8192 |
| Kernel load | ✅ Working | Loads Image, DTB, initrd from ext4 root |
| NixOS activation | ✅ Working | /etc, /var, /bin all created on first boot |
| Ethernet / SSH | ✅ Working | SSH at root@192.168.12.120, password: nixos |
| SATA drives | ✅ Working | pcie_aspm=off; both drives detected at 6 Gbps |
| USB keyboard | ✅ Working | usb-rebind service; enumerated at t=49.8s |
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

**Fix:** `init=/nix/var/nix/profiles/system/init` added to `setenv bootargs` in `bootScript`.
A symlink `/nix/var/nix/profiles/system → <toplevel>` is created in `populateRootCommands`
so the init path is stable across generations (see Fix #5).

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

### 5. `nixos-rebuild --rollback` support — system profile symlink

After boot, `nixos-rebuild switch` updates the active generation but boot always points to a
fixed path. Without a stable init path, each rebuild requires reflashing.

**Fix:** `populateRootCommands` in `sd-image.nix` creates:
```
/nix/var/nix/profiles/system → <config.system.build.toplevel>
```
Boot script uses `init=/nix/var/nix/profiles/system/init` instead of a hard-coded store path.
`nixos-rebuild switch` updates the profile symlink; `nixos-rebuild --rollback` restores the
previous one. An `update-boot-files` activation script in `hardware.nix` copies `/Image`,
`/initrd`, and `/dtb/meson-sm1-odroid-hc4.dtb` to the ext4 root on every switch so U-Boot
always finds the correct files for the active generation.

### 6. DTB GPU node disabled — no Mali voltage regulator on HC4

The Odroid HC4 GPU (`/soc/gpu@ffe40000`, Mali G31) shares the VDDEE power rail. There is no
dedicated `mali` voltage regulator in the device tree. Without intervention, the Panfrost DRM
driver fails to probe because it cannot find the regulator, producing:

```
panfrost ffe40000.gpu: supply mali not found, using dummy regulator
```

and attempts to operate without proper voltage control.

**Fix:** The DTB is patched with `fdtput -t s ... /soc/gpu@ffe40000 status disabled` in two
places:
- `sd-image.nix` `populateRootCommands` — applied at image build time to `/dtb/...` on the SD
- `hardware.nix` `system.activationScripts.update-boot-files` — reapplied on every
  `nixos-rebuild switch` after the DTB is copied from the new kernel package

## Key Files

```
build/odroidhc4/
├── flake.nix                        ← build entry point: nix build .#sdImage
├── configuration.nix                ← NixOS config → /etc/nixos/configuration.nix on device
├── hardware.nix                     ← hardware config → /etc/nixos/hardware.nix on device
│                                       (update-boot-files activation script lives here)
├── sd-image.nix                     ← SD image build only (boot script, FIP, profile symlink, DTB patch)
├── overlay/odroid-c4.nix            ← U-Boot FIP package
├── blob/armbian-fip-odroid-hc4.bin  ← prebuilt FIP binary
└── result/odroid-hc4-nixos.img.zst  ← latest built image
```

After first boot, manage the device via `/etc/nixos/` on the device itself:

```bash
ssh root@192.168.12.120
vi /etc/nixos/configuration.nix
nixos-rebuild switch
```

## SD Image Layout

```
Sector 0:       MBR (dos partition table, type 0x83, sig 0x55aa)
Sectors 1-2586: U-Boot FIP (~1.3 MB, magic: f0 f1 2e ef)
Sectors 8192+:  Single ext4 partition (LABEL=NIXOS_SD)
```

No FAT32. Files at ext4 root:
- `/Image`, `/initrd`, `/boot.scr`, `/dtb/meson-sm1-odroid-hc4.dtb` (GPU node disabled)
- `/nix/var/nix/profiles/system` → active NixOS generation (init= target, enables rollback)

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

## Key Settings

**`hardware.nix`** (hardware — also at `/etc/nixos/hardware.nix` on device):

```nix
boot.kernelParams = [
  "console=ttyAML0,115200" "root=LABEL=NIXOS_SD" "rootfstype=ext4"
  "rootwait" "loglevel=7" "console=tty0"
  "pcie_aspm=off"          # prevent SATA link loss via ASPM L1
  "usbcore.autosuspend=-1" # prevent USB keyboard from sleeping
];
boot.initrd.kernelModules = [ "stmmac" "dwmac_meson8b" "ext4" ];
boot.kernelModules = [ "mdio-mux-meson-g12a" "meson-canvas" "meson-drm" "meson_dw_hdmi" ];
hardware.fancontrol.enable = true;
fileSystems."/" = { device = "/dev/disk/by-label/NIXOS_SD"; fsType = "ext4"; };
# Keeps boot files in sync with the active generation on every nixos-rebuild switch.
# Also patches the DTB to disable the GPU node (no dedicated Mali voltage regulator on HC4).
system.activationScripts.update-boot-files.text = ''
  cp -f ${kernel}/Image /Image
  cp -f ${initialRamdisk}/initrd /initrd
  cp -f ${dtb}/amlogic/meson-sm1-odroid-hc4.dtb /dtb/meson-sm1-odroid-hc4.dtb
  fdtput -t s /dtb/meson-sm1-odroid-hc4.dtb /soc/gpu@ffe40000 status disabled
'';
```

**`configuration.nix`** (user config — also at `/etc/nixos/configuration.nix` on device):

```nix
networking.hostName = "odroid-hc4";
networking.useNetworkd = true;
systemd.network.networks."10-eth" = {
  matchConfig.Type = "ether";
  networkConfig = { DHCP = "yes"; Gateway = "192.168.12.1"; DNS = "192.168.12.1"; };
  addresses = [ { Address = "192.168.12.120/24"; } ];
};
users.users.root.initialPassword = "nixos";
services.openssh.enable = true;
nix.settings.experimental-features = [ "nix-command" "flakes" ];
environment.systemPackages = with pkgs; [ mdadm cryptsetup e2fsprogs mc ];
systemd.services.usb-rebind = { ... };  # dwc3 rebind after 8s
```

## Issues Found and Resolved (2026-06-16 – 2026-06-17)

### SATA drives drop after ~40s — PCIe ASPM

Both drives (WD 3TB + Seagate 3TB) detected at 6 Gbps via ASMedia ASM1061 SATA controller
(PCIe `0000:01:00.0`, vendor `1b21:0611`). At ~111s: `SStatus FFFFFFFF SControl FFFFFFFF` —
the PCIe link dies, all AHCI registers return 0xFF (bus gone).

Root cause: Amlogic `meson-pcie` + ASPM L1 — controller enters sleep and ASMedia chip doesn't
wake. Early hint: `meson_ee_pwrc sync_state() pending due to fc000000.pcie` (power domain tracks
PCIe, fires after all probing completes).

**Fix applied:** `pcie_aspm=off` added to `boot.kernelParams`.

### USB keyboard not detected — QMK connect-debounce failure → dwc3 rebind service

Keyboard: **Thomas Haukland cheapino** (custom QMK split keyboard, VID `FEE3:0000`).

**Root cause chain:**
1. `dwc3-meson-g12a` probes at ~1.76 s → VBUS on
2. QMK cold-boots: takes 1.22 s to first D+ assert, then unstable for ~1.5 s
   (split-half comms establishing, USB init cycling)
3. Linux hub connect-debounce requires D+ stable for 100 ms within 1500 ms — fails
   → `usb usb1-port2: connect-debounce failed` at ~4.5 s; port enters Disabled state
4. QMK eventually settles but hub stops monitoring the port — keyboard stuck forever

**Why VBUS delay (DT overlay `startup-delay-us`) doesn't help:**
xHCI initialisation sends a USB bus reset (SE0) to all ports. This restarts QMK's
USB init sequence regardless of how long VBUS was previously on. The debounce
failure just shifts later in time, not eliminated.
Also: NixOS's `apply_overlays.py` silently skips overlays with no `compatible`
property (empty set intersection → skip), and the kernel DTB has no
`regulator-always-on` on `regulator-usb-pwr-en` to delete anyway.

**Fix applied:** `systemd.services.usb-rebind` — after udevd is up (keyboard has
been settled for >30 s by then), rebind the dwc3 controller:
```
echo ffe09000.usb > /sys/bus/platform/drivers/dwc3-meson-g12a/unbind
sleep 0.5
echo ffe09000.usb > /sys/bus/platform/drivers/dwc3-meson-g12a/bind
```
This triggers a fresh xHCI init → hub scan → keyboard enumerates in ~261 ms.
`usbcore.autosuspend=-1` is also set to prevent idle autosuspend on the dwc3-meson-g12a
(keyboards on this controller don't wake from autosuspend).

## What Remains

- **HDMI console**: `meson-drm` loads but `Couldn't bind all components`. Non-critical for
  headless NAS use. Would require debugging the DRM component binding (likely `meson_ee_pwrc`
  power domain sync_state pending on hdmi-tx, pcie, vpu). GPU is intentionally disabled (Fix #6).
- **NAS configuration** (bucketnas3): NFS server, users/groups, manual disk management
  (`start-disks` / `stop-disks`) all working as of 2026-06-17. Remaining: RAID auto-mount at
  boot (currently requires manual `start-disks` after each boot).
