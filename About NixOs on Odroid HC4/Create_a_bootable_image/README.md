# NixOS on Odroid HC4 — Reproducible SD Image

Build a fully reproducible NixOS SD image for the Odroid HC4 (and compatible ODROID-C4),
using a prebuilt U-Boot FIP with ext4 support extracted from the working Armbian image.

## Prerequisites

- A **x86_64 Linux machine** with [Nix](https://nixos.org/download) installed and flakes enabled
- **Cross-compilation** works out of the box — the aarch64 kernel, initrd, and device tree are
  built on your x86_64 host. No QEMU emulation needed.
- An SD card of **at least 8 GB** (32 GB recommended)

## Project Structure

```
build/odroidhc4/
├── flake.nix              # Flake definition: nixosSystem, packages, devShells
├── configuration.nix      # NixOS config: SSH, networking, services
├── hardware.nix           # Hardware config: kernel params, modules, fan, filesystems
├── sd-image.nix           # SD image build only: boot script, FIP assembly, DTB patch
├── overlay/
│   └── odroid-c4.nix      # U-Boot FIP package (prebuilt from Armbian)
└── blob/
    └── armbian-fip-odroid-hc4.bin  # Prebuilt FIP binary (1.3 MB)
```

| File                              | Purpose                                                          |
| --------------------------------- | ---------------------------------------------------------------- |
| `flake.nix`                       | Flake: defines `#sdImage`, `#u-boot`, `#odroid-hc4` NixOS config |
| `configuration.nix`               | NixOS system config: SSH, networking, services                   |
| `hardware.nix`                    | Hardware config: kernel params, modules, fan, update-boot-files  |
| `sd-image.nix`                    | Build-time only: boot script, FIP assembly, DTB patch, profile symlink |
| `overlay/odroid-c4.nix`           | Defines `u-boot-odroid-c4` from the prebuilt FIP                 |
| `blob/armbian-fip-odroid-hc4.bin` | U-Boot FIP with ext4 support, extracted from Armbian             |

## How It Works

The Odroid HC4 uses an Amlogic G12A (S905X3) SoC that requires a **Firmware Image Package (FIP)**
at the start of the SD card. This FIP contains:

1. **BL2** — Bootloader stage 2
2. **BL30** — TrustZone firmware
3. **BL31** — Arm Trusted Firmware
4. **BL33** — U-Boot v2025.04 with `odroid-c4_defconfig` (enables ext4)

These are signed/encrypted with `aml_encrypt_g12a` and assembled into a single FIP binary.

**We don't build this ourselves.** We use the exact FIP extracted from the working Armbian
SD image — verified to boot on HC4 hardware. This is defined in `overlay/odroid-c4.nix` as a
Nix derivation that copies the prebuilt binary into the Nix store.

### SD Image Layout

```
Sector 0:     MBR (MBR partition table, type 0x83 Linux, sig 0x55aa)
Sectors 1–2586:  U-Boot FIP (~1.3 MB, magic: f0 f1 2e ef)
Sectors 2587–8191: Unused gap
Sectors 8192+:     Single ext4 partition (NixOS root filesystem)
```

**No FAT32 partition.** All boot files live on ext4 at the **partition root** (`/`):

| File                               | Source                               | Purpose                              |
| ---------------------------------- | ------------------------------------ | ------------------------------------ |
| `/Image`                           | Kernel output                        | aarch64 Linux kernel                 |
| `/initrd`                          | `config.system.build.initialRamdisk` | Initramfs with Nix store             |
| `/dtb/meson-sm1-odroid-hc4.dtb`    | Kernel dtbs                          | Device tree for HC4                  |
| `/boot.scr`                        | U-Boot mkimage                       | Boot script (compiled from boot.cmd) |

Boot files are at the partition root because U-Boot's `load mmc 0:1 <addr> /Image` resolves
paths relative to the filesystem root, not to any `/boot/` subdirectory.

The boot script (U-Boot's `boot.cmd`) sets boot arguments and loads the kernel/initrd/DTB from
the ext4 partition at specific memory addresses to avoid FIP overlap:

```
setenv bootargs "console=ttyAML0,115200 root=LABEL=NIXOS_SD rootfstype=ext4 rootwait loglevel=7 console=tty0 pcie_aspm=off usbcore.autosuspend=-1 init=/nix/var/nix/profiles/system/init"
load mmc 0:1 0x34000000 /Image
load mmc 0:1 0x04080000 /dtb/meson-sm1-odroid-hc4.dtb
load mmc 0:1 0x32000000 /initrd
booti 0x34000000 0x32000000:${initrd_size} 0x04080000
```

`console=ttyAML0,115200` — the Amlogic S905X3 UART uses the `meson_uart` driver; `ttyS0` is silent.
`init=/nix/var/nix/profiles/system/init` — stable path via the system profile symlink; required for
NixOS initramfs activation and enables `nixos-rebuild --rollback`.
`pcie_aspm=off` — prevents PCIe ASPM L1 from killing the SATA link (~40 s after boot without this).
`usbcore.autosuspend=-1` — prevents dwc3-meson-g12a from suspending USB devices (they don't wake).

Memory addresses are chosen well above 1.3 MB (FIP size) to avoid conflict with the FIP stored
at sector 1.

### Build Pipeline

```
configuration.nix (NixOS config — SSH, networking, services)
  └── imports hardware.nix (kernel params, modules, fan, update-boot-files)
        └── sd-image.nix (SD image build — boot script, DTB patch, profile symlink)
              ├── sd-image module → creates ext4 rootfs with Nix store closure
              ├── populateRootCommands →
              │     cp Image, DTB (patched via fdtput), initrd, boot.scr  → ./files/
              │     cp configuration.nix, hardware.nix                    → ./files/etc/nixos/
              │     ln -s <toplevel>                                       → ./files/nix/var/nix/profiles/system
              └── make-ext4-fs.nix → creates compressed ext4-fs.img.zst

overlay/odroid-c4.nix
  └── u-boot-odroid-c4 → copies prebuilt FIP binary

system.build.finalSdImage (mkDerivation in sd-image.nix):
  1. Decompress ext4-fs.img.zst
  2. Create blank image file
  3. Write MBR to sector 0
  4. Write U-Boot FIP to sector 1
  5. Write ext4 rootfs starting at sector 8192
  6. Compress with zstd
```

**Why `./files/Image` and not `./boot/Image` or `./files/boot/Image`?** The NixOS
`make-ext4-fs.nix` module creates a `./files/` directory, runs `populateRootCommands` inside it,
then copies `./files/*` into the rootfs image root. Using `./boot/` would place boot files
_alongside_ the build directory (never in the image). Using `./files/boot/` would put them
under `/boot/` on the partition — where U-Boot cannot find them.

## Building

### Quick Start

```bash
cd build/odroidhc4

# Validate the configuration evaluates correctly (fast)
nix flake show
nix build .#checks.x86_64-linux.nixosConfig

# Build the SD image (cross-compiles aarch64 on your x86_64 host)
nix build .#sdImage

# The result is at:
ls -la result/odroid-hc4-nixos.img.zst
```

### Full Build Steps

The build does two main things:

1. **Cross-compiles the aarch64 NixOS system** (kernel + initrd + device tree + Nix store)
   - Uses `nixpkgs.crossSystem = "aarch64-unknown-linux-gnu"`
   - Takes the most time (30 min – 2 hours depending on hardware)

2. **Assembles the final SD image** (MBR + FIP + ext4 rootfs + zstd compression)
   - Runs on the host architecture, very fast (a few seconds)

### Build Artifacts

After a successful build:

```
result/
└── odroid-hc4-nixos.img.zst   ← Compressed SD image (ready to flash)
```

The uncompressed image is approximately 2.7 GB for a minimal system.

## Flashing

### Step 1: Identify Your SD Card

```bash
lsblk
# Look for your SD card (15–32 GB typically).
# Common device names: /dev/sdX or /dev/mmcblk0
#
# Example output:
# sda    ← Your SD card (not /dev/nvme0n1 — that's your system disk!)
# ├─sda1
# └─sda2
# nvme0n1 ← Your system disk — DO NOT WRITE HERE
```

### Step 2: Decompress the Image

```bash
cd result

# Decompress to a temporary file (creates a ~2.7 GB file)
zstd -d odroid-hc4-nixos.img.zst -o /tmp/odroid-hc4-nixos.img
```

### Step 3: Write to SD Card

```bash
# ⚠️ REPLACE /dev/sdX WITH YOUR ACTUAL SD CARD DEVICE!
# Double-check with lsblk before running this command.

sudo dd if=/tmp/odroid-hc4-nixos.img bs=1M status=progress of=/dev/sdX conv=fsync
```

### Step 4: Verify (Optional)

```bash
# Detach and check the image layout
sudo losetup -fP /tmp/odroid-hc4-nixos.img
sudo losetup -a    # note the loop device

# Verify MBR signature (should be 55 aa)
sudo dd if=/tmp/odroid-hc4-nixos.img bs=512 count=1 | tail -c 2 | hexdump -C
# Expected: 55 aa

# Verify FIP magic (should be f0 f1 2e ef)
sudo dd if=/tmp/odroid-hc4-nixos.img bs=512 skip=1 count=1 | head -c 4 | hexdump -C
# Expected: f0 f1 2e ef

# Verify boot files are present at partition root
sudo mount /dev/loop0p1 /mnt
sudo ls -la /mnt/Image /mnt/initrd /mnt/boot.scr /mnt/dtb/
# Should show: Image, initrd, boot.scr, dtb/meson-sm1-odroid-hc4.dtb
sudo umount /mnt

# Cleanup
sudo losetup -d /dev/loop0
```

## First Boot

1. Insert the SD card into the Odroid HC4
2. Connect an Ethernet cable (headless boot, no monitor needed)
3. Power on the device
4. Wait 1–2 minutes for first-boot initialization

### Default Credentials

- **SSH login:** `root` / `nixos`
- **SSH key access:** Copy your key to `/root/.ssh/authorized_keys` after first login
- **Static IP:** `192.168.12.120/24` (DHCP also runs alongside)

### SSH In

```bash
ssh root@192.168.12.120
```

## Updating

When you modify `configuration.nix` (e.g., add packages, change fan settings):

```bash
cd build/odroidhc4

# Rebuild
nix build .#sdImage

# Flash (WARNING: erases the SD card!)
# Find the correct device first!
lsblk
sudo dd if=result/odroid-hc4-nixos.img bs=1M status=progress of=/dev/sdX conv=fsync
```

Or update on the device itself:

```bash
# On the Odroid HC4, you can use nixos-rebuild for non-image changes:
nixos-rebuild switch --flake /etc/nixos#odroid-hc4
```

## Customizing

### Change the Root Password

```nix
# In configuration.nix:
users.users.root.initialPassword = "your-password";
# Or better, use SSH keys:
# users.users.root.openssh.authorizedKeys.keyFiles = [ ./keys/root ];
```

### Add Packages

```nix
# In configuration.nix, add to environment.systemPackages:
environment.systemPackages = with pkgs; [
  htop
  nvtop
  tmux
];
```

### Change Timezone

```nix
# In configuration.nix:
time.timeZone = "America/New_York";  # replace with your timezone
```

### Adjust Fan Control

Fan control is enabled by default with conservative thresholds (50–60 °C). To disable:

```nix
hardware.fancontrol.enable = false;
```

To adjust, modify `hardware.fancontrol.config` — the key parameters:

- `MINTEMP` — Start ramping up fan at this temperature
- `MAXTEMP` — Full fan speed at this temperature
- `MINSTOP` — Fan turns off below this temperature
- `MAXPWM` — Maximum fan speed (0–255)

### Change Boot Kernel Parameters

```nix
# In configuration.nix:
boot.kernelParams = [
  "console=ttyAML0,115200"
  "console=tty0"
  "root=LABEL=NIXOS_SD"
  "rootfstype=ext4"
  "rootwait"
  "loglevel=7"   # add this for verbose kernel output
];
```

### Increase System Size

The image expands to fill the SD card on first boot (`expandOnBoot = true`). If you need a
larger initial rootfs, add more packages to `environment.systemPackages` or configure
additional file systems.

## Troubleshooting

### Build Fails with Hash Mismatch

The FIP binary hash needs to match the file in `blob/`. If you replace it:

```bash
sha256sum blob/armbian-fip-odroid-hc4.bin
# Update the hash in overlay/odroid-c4.nix
```

### Boot Fails — U-Boot Can't Find Boot Files

Check the boot files are present at the partition root:

```bash
zstd -d result/odroid-hc4-nixos.img.zst -o /tmp/test.img
sudo losetup -fP /tmp/test.img
sudo mount /dev/loop0p1 /mnt
ls -la /mnt/Image /mnt/initrd /mnt/boot.scr /mnt/dtb/
sudo umount /mnt
sudo losetup -d /dev/loop0
```

If files are missing from the partition root, the issue is in `populateRootCommands` —
it must use `./files/Image` etc. (partition root), not `./files/boot/Image`.

### Device Won't Boot

1. **Check the SD card** — try a different card, or re-flash
2. **Check serial console** — connect to `ttyAML0` at 115200 baud to see U-Boot/kernel output
3. **Check the FIP** — verify magic bytes: `hexdump -C -n 4 -s 512 /tmp/test.img`
4. **Check the partition layout** — partition should start at sector 8192, not 2048

### SSH Connection Refused

- Verify the device has a valid IP (check router DHCP table)
- Wait 2–3 minutes after power-on (first boot can take time)
- Check that the Ethernet link is up (green LED on the HC4's Ethernet port)

### "No Space Left on Device" During Flash

The uncompressed image is ~2.7 GB. Ensure your temp directory has at least 3 GB free,
and that you're writing to the correct device (double-check with `lsblk`).

## Reference: Armbian Comparison

This build was reverse-engineered from the working Armbian image (`20260523-Armbian-working.img.zst`)
by comparing binary layout, partition sectors, and boot script content. Key matches:

| Aspect          | NixOS Build                | Armbian          |
| --------------- | -------------------------- | ---------------- |
| FIP magic       | `f0 f1 2e ef`              | `f0 f1 2e ef`    |
| FIP location    | Sector 1                   | Sector 1         |
| Partition start | Sector 8192                | Sector 8192      |
| Root fs type    | ext4                       | ext4             |
| DTB filename    | `meson-sm1-odroid-hc4.dtb` | same             |
| Boot console    | `ttyAML0,115200`           | `ttyAML0,115200` |
| Boot script     | `booti` command            | `booti` command  |

## Development

### Dev Shell

```bash
nix develop   # opens shell with nixfmt, nil, alejandra, mdbook
```

### Format Configuration

```bash
nix fmt       # formats all .nix files with nixfmt
alejandra .   # alternative formatter
```

### Check NixOS Config

```bash
nix build .#checks.x86_64-linux.nixosConfig 2>&1
```

## License

- NixOS configuration: MPL-2.0 (matching nixpkgs)
- U-Boot FIP: Unfree redistributable firmware (extracted from Armbian, distributed under
  Hardkernel's terms)
- Nixpkgs: MPL-2.0
