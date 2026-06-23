## Armbian vs NixOS — Full Comparison

### 🔑 THE KEY FINDING: Two-Layer Ethernet Driver

The HC4 ethernet uses a **two-layer driver stack**:

| Layer | Armbian (working) | NixOS (before fix) | NixOS (after fix) |
|---|---|---|---|
| **Generic MAC framework** | `stmmac` (built into kernel) | ✅ in initrd | ✅ in initrd |
| **Amlogic glue layer** | `dwmac_meson8b` (built into kernel) | ❌ **MISSING** | ✅ **NOW added** |

In Armbian both drivers are **built into the kernel** (`6.18.10-current-meson64`). In NixOS, the mainline kernel has them as modules, so they need to be in the initrd to be available at boot.

**`stmmac` alone was NOT enough.** Without `dwmac_meson8b`, the kernel has no driver to bind to the device tree node `amlogic,meson-g12a-dwmac`.

### Other Differences

| | Armbian | NixOS |
|---|---|---|
| **Kernel** | `6.18.10-current-meson64` (custom) | Mainline NixOS kernel |
| **Interface name** | `end0` | Unknown (need serial to verify) |
| **Network manager** | NetworkManager (netplan) | systemd-networkd |
| **Interface match** | `name: "e*"` → matches `end0` | `Type = "ether"` → matches any |
| **simpledrm** | Blacklisted ✅ | Blacklisted ✅ (added by me) |
| **simpledrm modprobe** | `/etc/modprobe.d/blacklist-odroidhc4.conf` | `boot.extraModprobeConfig` |
| **Serial console** | Not primary (HDMI works) | Added as first console |

### What I Fixed

1. **Added `dwmac_meson8b`** to initrd kernel modules — this is the Amlogic glue layer that was missing
2. **Kept `simpledrm` blacklist** — prevents hangs on Amlogic SoCs
3. **Added serial console first** — `console=ttyS0,115200n8` before `console=tty0` — so the kernel won't hang waiting for HDMI
4. **Dual IP addresses** — DHCP + static `192.168.12.100`

## The Key Difference for Display

| | Armbian | NixOS |
|---|---|---|
| **Kernel** | `6.18.10-current-meson64` (custom with `meson-drm` driver) | Mainline NixOS kernel (no working `meson-drm` for HC4) |
| **Console** | `console=ttyS0,115200 console=tty1` | Only `console=tty0` (framebuffer, doesn't work on mainline) |
| **HDMI** | ✅ Works (custom kernel has meson-drm) | ❌ "Starting kernel..." then hangs |

Armbian's custom kernel has the **`meson-drm` driver** properly compiled in, which is why HDMI display works. Our mainline NixOS kernel doesn't have this working for the HC4 — that's why the HDMI shows nothing past the initial "Starting kernel..." message.

## What This Means for Us

**The HDMI/display problem is a kernel limitation, not a config problem.** Armbian uses a custom kernel (`6.18.10-current-meson64`) that has `meson-drm` built in. NixOS uses the mainline kernel which doesn't support the HC4's HDMI properly.

**For our purposes (SSH/headless), this doesn't matter.** The serial console + ethernet should work fine. The display issue is separate.

## Summary of Everything

| Component | Armbian (working) | NixOS (before) | NixOS (after my fixes) |
|---|---|---|---|
| **Kernel** | `6.18.10-current-meson64` | Mainline (no `dwmac_meson8b`) | Mainline + `dwmac_meson8b` ✅ |
| **Ethernet** | `meson8b-dwmac` (built-in) | Only `stmmac` ❌ | `stmmac` + `dwmac_meson8b` ✅ |
| **Interface name** | `end0` | Unknown | Unknown (need serial to verify) |
| **Network** | NetworkManager ✅ | systemd-networkd ✅ | systemd-networkd ✅ |
| **simpledrm** | Blacklisted ✅ | Not blacklisted ✅ (added) |
| **Serial console** | `console=ttyS0,115200` | Not set in kernel params | `console=ttyS0,115200n8` ✅ |
| **HDMI** | `console=tty1` ✅ | `console=tty0` ❌ | `console=tty0` ❌ (same — kernel limit) |
| **Network config** | DHCP on any `e*` interface | DHCP + static `192.168.12.100` ✅ |

**The `dwmac_meson8b` fix should solve the network problem.** Rebuild and test on serial to confirm.
