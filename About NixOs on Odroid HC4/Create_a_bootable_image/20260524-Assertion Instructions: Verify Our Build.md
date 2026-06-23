## Assertion Instructions: Verify Our SD Image Reproduces Armbian Boot Flow

### 1. FIP Binary — Magic Bytes & Format

**Goal:** Confirm our FIP has the same format as Armbian's (mainline U-Boot, magic `f0 f1 2e ef`).

```bash
cd /home/jgetreu/dev2/Armbian2Nixos-migration/build/odroidhc4

# Check our built FIP
nix build .#u-boot
head -c 4 result/u-boot.bin | hexdump -C
# Expected: f0 f1 2e ef

# Compare against the source from Armbian image
dd if=~/Armbian2Nixos-migration/blob/armbian-fip-odroid-hc4.bin bs=512 skip=1 count=4 2>/dev/null | hexdump -C
# Expected: f0 f1 2e ef

# Both should match — same mainline U-Boot FIP format
```

### 2. Partition Layout

**Goal:** Confirm the image has the exact same sector layout as Armbian.

```bash
cd /home/jgetreu/dev2/Armbian2Nixos-migration/build/odroidhc4

# Build the full SD image
nix build .#sdImage

# Check image size and sector count
ls -la result/odroid-hc4-nixos.img.zst
zstd -d result/odroid-hc4-nixos.img.zst -o /tmp/compare.img

# Sector 0: MBR — last 2 bytes must be 55 aa
od -A x -t x1 /tmp/compare.img | grep "0001f0"
# Expected: ... 55 aa

# Sector 1: FIP — should contain magic f0 f1 2e ef
dd if=/tmp/compare.img bs=512 skip=1 count=1 2>/dev/null | od -A x -t x1 | head -1
# Expected: 000000 f0 f1 2e ef ...

# Verify partition table — exactly ONE partition starting at sector 8192
fdisk -l /tmp/compare.img
# Should show: /tmp/compare.img1  *  8192  ...  83  Linux
```

### 3. Compare Against Working Armbian Image

**Goal:** Cross-reference with the known-working Armbian image.

```bash
cd ~/Armbian2Nixos-migration/Images

# Decompress if needed
zstd -d 20260523-Armbian-working.img.zst -o /tmp/armbian-compare.img

# Check Armbian's partition layout
fdisk -l /tmp/armbian-compare.img

# Check Armbian's FIP location and magic
dd if=/tmp/armbian-compare.img bs=512 skip=1 count=1 2>/dev/null | od -A x -t x1 | head -1
# Expected: 000000 f0 f1 2e ef ...

# Both should have identical layout: MBR → FIP at sector 1 → partition at 8192
```

### 4. Device Tree Blob

**Goal:** Verify the correct Meson SM1 DTB is used.

```bash
cd /home/jgetreu/dev2/Armbian2Nixos-migration/build/odroidhc4

# Verify configuration.nix references the correct DTB filename
grep "dtbFile" configuration.nix
# Expected: dtbFile = "meson-sm1-odroid-hc4.dtb";

# Check hardware.deviceTree.filter
grep "deviceTree.filter" configuration.nix
# Expected: hardware.deviceTree.filter = dtbFile;
```

### 5. Boot Script (boot.scr)

**Goal:** Verify the boot.cmd loads files from the ext4 partition root (not /boot/).

Boot files live at the ext4 **partition root** — U-Boot's `load` command uses paths relative to
the filesystem root, and our partition has no /boot/ subdirectory.

```bash
cd /home/jgetreu/dev2/Armbian2Nixos-migration/build/odroidhc4

# Check boot.cmd in configuration.nix — verify load paths
grep -A 20 'mkimage' configuration.nix

# It must:
# 1. Set bootargs with console=ttyAML0,115200 and init=<nix-store-path>/init
# 2. Load kernel from:  load mmc 0:1 <addr> /Image
# 3. Load DTB from:     load mmc 0:1 <addr> /dtb/meson-sm1-odroid-hc4.dtb
# 4. Load initrd from:  load mmc 0:1 <addr> /initrd
# 5. Boot with:         booti <kernelAddr> <ramdiskAddr>:${initrd_size} <fdtAddr>
```

### 6. Kernel Command Line Parameters

**Goal:** Verify bootargs match what the Amlogic S905X3 SoC requires.

```bash
cd /home/jgetreu/dev2/Armbian2Nixos-migration/build/odroidhc4

# Check bootargs in the bootScript (setenv bootargs) in configuration.nix
grep -A 3 "setenv bootargs" configuration.nix

# Must include:
#   console=ttyAML0,115200    (Amlogic meson_uart driver — NOT ttyS0)
#   console=tty0
#   root=LABEL=NIXOS_SD
#   rw
#   rootwait
#   rootfstype=ext4
#   init=<nix-store-path>/init   (required for NixOS initramfs activation)

# Also check boot.kernelParams (applied by extlinux/bootloader, separate from bootScript):
grep -A 10 "kernelParams" configuration.nix
```

**Note on `init=`:** Without `init=` in bootargs, the NixOS initramfs service
`initrd-find-nixos-closure` cannot locate the NixOS system closure, causing activation to
silently fail — the system stays in the initramfs with no /etc created on disk.

**Note on `ttyAML0`:** The Amlogic S905X3 UART uses the `meson_uart` driver, device
`/dev/ttyAML0`. Using `ttyS0` produces no serial output.

### 7. Filesystem Type

**Goal:** Confirm we use ext4 root.

```bash
# ext4 superblock magic 0x53EF appears at offset 0x438 (1080) within the partition.
# Partition starts at sector 8192 → absolute byte offset = 8192*512 + 1080 = 4195384
dd if=/tmp/compare.img bs=1 skip=4195384 count=2 2>/dev/null | od -A x -t x1
# Expected: 000000 ef 53   (little-endian 0x53ef — ext4 magic)
```

### 8. Root Filesystem Content

**Goal:** Verify the NixOS rootfs has boot files at the ext4 partition root.

All boot files are placed at `/` (partition root), not `/boot/`. This is because U-Boot's
`load mmc 0:1 <addr> /Image` resolves relative to the partition root.

```bash
cd /home/jgetreu/dev2/Armbian2Nixos-migration/build/odroidhc4

# Decompress the full SD image
zstd -d result/odroid-hc4-nixos.img.zst -o /tmp/odroid-hc4-nixos.img

# Attach with partition scanning (uses udisksctl — no sudo needed)
udisksctl loop-setup --file /tmp/odroid-hc4-nixos.img --read-only
# note the loop device (e.g. /dev/loop0)
udisksctl mount --block-device /dev/loop0p1 --read-only
# note the mount point (e.g. /run/media/<user>/NIXOS_SD)

MOUNT=/run/media/$(whoami)/NIXOS_SD

# Check expected boot files exist at partition root:
ls -la $MOUNT/Image
ls -la $MOUNT/initrd
ls -la $MOUNT/boot.scr
ls -la $MOUNT/dtb/meson-sm1-odroid-hc4.dtb

# Verify all four are present: Image, initrd, boot.scr, dtb/
udisksctl unmount --block-device /dev/loop0p1
udisksctl loop-delete --block-device /dev/loop0
```

**Expected file table:**

| File                                     | Size (approx)   | Location         |
| ---------------------------------------- | --------------- | ---------------- |
| `Image`                                  | ~60 MB          | `/Image`         |
| `initrd`                                 | ~11 MB          | `/initrd`        |
| `boot.scr`                               | ~772 bytes      | `/boot.scr`      |
| `meson-sm1-odroid-hc4.dtb`               | ~77 KB          | `/dtb/`          |

**Note on populateRootCommands:** Boot files must be placed as `./files/Image`,
`./files/dtb/…`, `./files/initrd`, `./files/boot.scr`. The sd-image module's
`make-ext4-fs.nix` copies `./files/*` into the rootfs image root. Using `./files/boot/Image`
would put them under `/boot/` on the partition, which U-Boot cannot find.

### 9. Memory Addresses

**Goal:** Verify kernel/initrd/FDT addresses don't conflict with FIP in low memory.

```bash
cd /home/jgetreu/dev2/Armbian2Nixos-migration/build/odroidhc4

# FIP is ~1.3MB; all load addresses must be well above this.
grep -E "kernelAddr|fdtAddr|ramdiskAddr" configuration.nix
# Expected:
#   kernelAddr   = "0x34000000";   (~852 MB — safely above FIP)
#   fdtAddr      = "0x04080000";   (~64.5 MB — safely above FIP)
#   ramdiskAddr  = "0x32000000";   (~800 MB — safely above FIP)
# All >> 1.3MB (FIP size) — no overlap
```

### 10. Final Checklist Summary

| Check                                    | Expected                              | Status      |
| ---------------------------------------- | ------------------------------------- | ----------- |
| FIP magic bytes                          | `f0 f1 2e ef`                         | ✅ verified |
| FIP at sector 1                          | Yes                                   | ✅ verified |
| Partition starts at sector 8192          | Yes                                   | ✅ verified |
| Single ext4 partition                    | One partition, type 0x83              | ✅ verified |
| Root fs is ext4                          | Magic `ef 53` at 8192×512+1080        | ✅ verified |
| MBR signature                            | `55 aa`                               | ✅ verified |
| DTB filename                             | `meson-sm1-odroid-hc4.dtb`            | ✅ verified |
| Boot files at partition root             | `/Image`, `/initrd`, `/boot.scr`, `/dtb/` | ✅ verified |
| Boot args: ttyAML0 console               | `console=ttyAML0,115200`              | ✅ verified |
| Boot args: root=LABEL=NIXOS_SD           | Yes                                   | ✅ verified |
| Boot args: rootfstype=ext4               | Yes                                   | ✅ verified |
| Boot args: rootwait                      | Yes                                   | ✅ verified |
| Boot args: init=<nix-store-path>/init    | Yes                                   | ✅ verified |
| Boot script loads from mmc 0:1           | Yes                                   | ✅ verified |
| Boot script loads /Image                 | Yes (partition root, not /boot/)      | ✅ verified |
| Boot script loads /initrd                | Yes (partition root, not /boot/)      | ✅ verified |
| Boot script loads /dtb/*.dtb             | Yes (partition root, not /boot/dtb/)  | ✅ verified |
| Boot script uses booti                   | Yes                                   | ✅ verified |
| Memory addresses don't overlap FIP       | All > 1.3 MB                          | ✅ verified |

### Fixes Applied (history)

1. **MBR was zeros** — fixed by writing MBR with type `0x83` Linux partition entry and `55 aa` signature.
2. **Partition at sector 2048 overlapped FIP** — fixed by moving to sector 8192.
3. **Boot files at `./boot/`** — fixed: `populateRootCommands` now uses `./files/Image` etc. (partition root).
4. **Wrong serial console `ttyS0`** — fixed to `ttyAML0` (Amlogic `meson_uart` driver).
5. **Missing `init=` in bootargs** — fixed: `init=${config.system.build.toplevel}/init` added to `setenv bootargs` in `bootScript`.
6. **Missing MDIO mux driver** — fixed: `mdio-mux-meson-g12a` added to `boot.kernelModules`.

All checks pass. The image boots the Odroid HC4 to SSH (root@192.168.12.120).
