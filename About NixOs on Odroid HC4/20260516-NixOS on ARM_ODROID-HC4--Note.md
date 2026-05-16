---
title:        NixOS on ARM/ODROID-HC4
subtitle:     Note
author:       Jgetreu
date:         2026-05-16
lang:         en-US
---

[NixOS on ARM/ODROID-HC4 - Official NixOS Wiki](https://wiki.nixos.org/wiki/NixOS_on_ARM/ODROID-HC4#Fan_doesn't_work_by_default)

# NixOS on ARM/ODROID-HC4

* [Page](https://wiki.nixos.org/wiki/NixOS_on_ARM/ODROID-HC4)
* [Discussion](https://wiki.nixos.org/w/index.php?title=Talk:NixOS_on_ARM/ODROID-HC4&action=edit&redlink=1)

* [Read](https://wiki.nixos.org/wiki/NixOS_on_ARM/ODROID-HC4)
* [View source](https://wiki.nixos.org/w/index.php?title=NixOS_on_ARM/ODROID-HC4&action=edit)
* [View history](https://wiki.nixos.org/w/index.php?title=NixOS_on_ARM/ODROID-HC4&action=history)

Tools

* [](https://wiki.nixos.org/wiki/Special:WhatLinksHere/NixOS_on_ARM/ODROID-HC4)
* [](https://wiki.nixos.org/wiki/Special:RecentChangesLinked/NixOS_on_ARM/ODROID-HC4)
* [](javascript:print();)
* [](https://wiki.nixos.org/w/index.php?title=NixOS_on_ARM/ODROID-HC4&oldid=21562#Fan_doesn't_work_by_default)
* [](https://wiki.nixos.org/w/index.php?title=NixOS_on_ARM/ODROID-HC4&action=info)

Appearance

Text

* Small

  Standard

  Large

Width

* Standard

  Wide

[← Back to NixOS on ARM](https://wiki.nixos.org/wiki/NixOS_on_ARM)

|Hardkernel ODROID-HC4|               |
|---------------------|---------------|
|    Manufacturer     |  Hardkernel   |
|    Architecture     |    AArch64    |
|     Bootloader      |    U-Boot     |
|    Boot options     |microSD (SATA?)|

## Status

Mostly working, but some manual steps needed to get it running.

U-boot support in NixPkgs is currently in review: [NixPkgs Pull Request #101454](https://github.com/NixOS/nixpkgs/pull/101454)

## Board-specific installation notes

### Petitboot removal

Petitboot is installed on the SPI memory of the Odroid HC4 from factory. To be able to load an upstreamed version of U-Boot without having to press a hardware button at each boot, you may remove it.**Please proceed with caution, this will make Hardkernel images unbootable!**

From the Petitboot, go for “Exit to shell” and enter these commands to remove Petitboot:

```bash
flash_eraseall /dev/mtd0
flash_eraseall /dev/mtd1
flash_eraseall /dev/mtd2
flash_eraseall /dev/mtd3

```

This will make your SPI flash memory empty and the device will now start from SD on next boot.

See [this Odroid forum topic](https://forum.odroid.com/viewtopic.php?f=207&t=40906) to restore Petitboot.

### NixOS installation

1. First follow the [generic installation steps](https://wiki.nixos.org/wiki/NixOS_on_ARM#Installation) to get the latest stable installer image.
2. Uncompress the .zst file. One may use the `unzstd` command (equivalent to `zstd -d`) on supported machines. The zstd commands can be accessed from the `zstd` package.
3. Patch this image (.img file) with U-Boot for Odroid HC4.

   ```bash
   # Clone content of samueldr's wip/odroidc4 branch, edit the defconfig file, and build
   git clone https://github.com/samueldr/nixpkgs --depth 1 -b wip/odroidc4 && cd nixpkgs
   test "$(uname)" '==' 'Darwin' && sed -i '' 's/defconfig = "odroid-c4_defconfig"/defconfig = "odroid-hc4_defconfig"/' pkgs/misc/uboot/default.nix || sed -i 's/defconfig = "odroid-c4_defconfig"/defconfig = "odroid-hc4_defconfig"/' pkgs/misc/uboot/default.nix
   nix-build -I "nixpkgs=$PWD" -A pkgsCross.aarch64-multiplatform.ubootOdroidC4
   sudo dd if=result/u-boot.bin of=PATH/TO/nixos-sd-image-21.05.XXXX.XXXXXXXX-aarch64-linux.img  conv=fsync,notrunc bs=512 seek=1

   ```

4. Flash the modified SD image file (.img) to a microSD card. **This will erase all the data on the card!**

## Known issues

### Fan doesn't work by default

You need to use software fan control (via `fancontrol`) for this.
You may refer to [[nixos-hardware Odroid HC4 module](https://github.com/NixOS/nixos-hardware/blob/master/hardkernel/odroid-hc4/default.nix)] for `fancontrol` configuration.

## No HDMI audio by default

After enabling ALSA you should see a sound card named "ODROID-HC4". Audio is not correctly routed by default so you might need to open alsa-mixer and change:

* `FRDDR_A SINK 1 SEL` to `OUT 1`
* `FRDDR_A SRC 1 EN` to on
* `TDMOUT_B SRC SEL` to `IN 0`
* `TOHDMITX` to on
* `TOHDMITX I2S SRC` to `I2S B`

After these changes, `speaker-test -c 2` should output white noise.

## Resources

* [Official product page](https://www.hardkernel.com/shop/odroid-hc4/)
* [NixOS configuration for the ODROID HC4 microcomputer by considerate](https://github.com/considerate/nixos-odroidhc4/)
* [Armbian Odroid HC4](https://www.armbian.com/odroid-hc4/)
* [U-Boot for Odroid C4 documentation](https://u-boot.readthedocs.io/en/latest/board/amlogic/odroid-c4.html)

[Category](https://wiki.nixos.org/wiki/Special:Categories):

* [NixOS on ARM](https://wiki.nixos.org/wiki/Category:NixOS_on_ARM)

*

