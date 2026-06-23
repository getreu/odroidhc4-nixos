# Summary — Odroid HC4 NixOS Migration

## What Was Fixed

### 1. Bootloader (TFTP → SD Card) ✅ DONE
**Problem:** U-Boot couldn't find `boot.scr` because it was at `/boot/boot.scr` instead of the partition root, so it fell back to TFTP.

**Fixes:**
- Moved `boot.scr` from `./files/boot/boot.scr` → `./files/boot.scr` (partition root)
- Fixed boot script paths from `/boot/Image` → `/Image`, `/boot/initrd` → `/initrd`, etc.
- Fixed `filesize` bug — saved initrd size before DTB load overwrote it

**Confirmed working:** initrd_size = 0xb16d67 (11.1 MB) — U-Boot is loading everything correctly.

### 2. Ethernet Driver ✅ DONE
**Problem:** `stmmac` module (Synopsys DesignWare MAC) was missing from the initrd, so the kernel couldn't see the ethernet controller.

**Fix:** Added `boot.initrd.kernelModules = [ "stmmac" ];`

### 3. DHCP / Network Config ✅ DONE
**Problem:** Used legacy `networking.interfaces.eth0.useDHCP = true` which relies on dhcpcd that was never started.

**Fix:**
- Switched to systemd-networkd: `networking.useNetworkd = true`
- Match on **any** ethernet interface: `matchConfig.Type = "ether"` (not just `eth0`)
- Updated `print-ip` service to wait for `network-online.target`

### 4. Ethernet Link ✅ CONFIRMED
LEDs show: green steady + yellow blink once/sec = link is UP. The physical connection works.

## Current Status

| Component | Status |
|---|---|
| U-Boot / Boot Script | ✅ Working — loads kernel, DTB, initrd |
| Ethernet driver (stmmac) | ✅ Added to initrd (can't verify loaded without serial) |
| DHCP configuration | ✅ Fixed for any ethernet interface |
| Physical link | ✅ Confirmed (LEDs show link up) |
| Network working | ❓ Can't test — no serial, no IP assigned |

## What Still Needs Verification

Without serial console access we can't confirm:
- The kernel is actually booting (not hanging before the prompt)
- The `stmmac` module is loaded
- The interface is named `eth0`, `end0`, or something else
- networkd is starting and trying DHCP
- Any kernel errors during boot

**If the device still isn't getting an IP**, the most likely causes are:
1. Interface named `end0` (not `eth0`) — our new config should handle this
2. Kernel hanging somewhere before network starts
3. A missing kernel module or device tree issue

Rebuild and flash the updated image with the interface-agnostic network config.

