# NixOS SD image configuration for Odroid HC4
#
# Odroid HC4 uses the same Amlogic SM1/S905X3 (G12A) SoC as Odroid C4.
# U-Boot is built via a Nixpkgs overlay that provides:
#   - meson64-tools       : proprietary Amlogic signing tools
#   - firmwareOdroidC4    : Hardkernel firmware blobs (BL2, BL30, BL31, BL33)
#   - ubootOdroidC4       : U-Boot FIP binary (u-boot.bin)
#
# Boot flow:
#   1. ROM code loads SPL from SD sector 1
#   2. SPL loads u-boot.bin from the firmware partition (mmc 0:1)
#   3. U-Boot executes boot.scr from the firmware partition
#   4. boot.scr loads kernel, initrd, and DTB, then boots via booti
#
# Build with flake:
#   cd "Armbin2Nixos migration"
#   nix build .#nixosConfigurations.odroid-hc4.config.system.build.sdImage
#
# Flash to SD card:
#   zstd -d result/nixos-sd-image-*.img.zst -o odroid-hc4.img
#   sudo dd if=odroid-hc4.img of=/dev/sdX bs=4M conv=fsync status=progress

{
  config,
  lib,
  pkgs,
  ...
}:

let
  # U-Boot for Odroid HC4 — same Amlogic SM1/S905X3 (G12A) SoC as C4
  # The overlay provides ubootOdroidC4 on top of upstream NixOS 25.11
  uboot = pkgs.ubootOdroidC4;

  # mkimage tool for generating boot.scr from boot.cmd
  # Provided by upstream NixOS 25.11 as ubootTools
  mkimage = pkgs.ubootTools;

  # Device tree for Odroid HC4
  dtbFilter = "meson-sm1-odroid-hc4.dtb";

  # Memory addresses for Meson SM1 (S905X3) SoC
  kernel_addr = "0x10000000";
  fdt_addr = "0x11000000";
  ramdisk_addr = "0x11800000";

  # Generate boot.scr from boot.cmd using mkimage
  bootScript = pkgs.runCommandLocal "boot.scr" { } ''
    ${mkimage}/bin/mkimage -A arm64 -O linux -T script -C none \
      -a 0 -e 0 \
      -n "NixOS Odroid HC4" \
      -d ${pkgs.writeText "boot.cmd" ''
        setenv bootargs "console=ttyS0,115200n8 console=tty0 root=/dev/mmcblk0p2 rw rootwait rootfstype=ext4"
        load mmc 0:1 ${kernel_addr} Image
        load mmc 0:1 ${fdt_addr} ${dtbFilter}
        load mmc 0:1 ${ramdisk_addr} initrd
        booti ${kernel_addr} ${ramdisk_addr} ${fdt_addr}
      ''} $out
  '';
in

{
  # ============================================================
  # System configuration
  # ============================================================
  system.stateVersion = "25.11";

  # ============================================================
  # Boot configuration
  # ============================================================
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;
  boot.consoleLogLevel = lib.mkDefault 7;

  boot.kernelParams = [
    "console=ttyS0,115200n8"
    "console=tty0"
    "root=/dev/mmcblk0p2"
    "rootfstype=ext4"
    "rootwait"
  ];

  # ============================================================
  # Hardware-specific settings (Odroid HC4)
  # ============================================================
  hardware.deviceTree.filter = dtbFilter;

  # Fan control (required for proper cooling)
  # Uses thermal_zone0 to control pwm-fan via pwm1
  hardware.fancontrol.enable = lib.mkDefault true;
  hardware.fancontrol.config = lib.mkDefault (
    let
      kernelVersion = config.boot.kernelPackages.kernel.version;
      needFcFans = lib.versions.majorMinor kernelVersion != "5.15";
    in
    ''
      INTERVAL=10
      DEVPATH=hwmon0=devices/virtual/thermal/thermal_zone0 hwmon2=devices/platform/pwm-fan
      DEVNAME=hwmon0=cpu_thermal hwmon2=pwmfan
      FCTEMPS=hwmon2/pwm1=hwmon0/temp1_input
    ''
    + lib.optionalString needFcFans ''
      FCFANS= hwmon2/pwm1=hwmon2/fan1_input
    ''
    + ''
      MINTEMP=hwmon2/pwm1=50
      MAXTEMP=hwmon2/pwm1=60
      MINSTART=hwmon2/pwm1=20
      MINSTOP=hwmon2/pwm1=28
      MINPWM=hwmon2/pwm1=0
      MAXPWM=hwmon2/pwm1=255
    ''
  );

  # Watchdog to prevent freezes
  systemd.watchdog.runtimeTime = lib.mkDefault "1min";

  # ============================================================
  # SD image configuration
  # Partition layout:
  #   - [8 MiB gap] for U-Boot SPL at sector 1
  #   - Partition 1: 64 MiB FAT32 (FIRMWARE) — u-boot.bin, boot.scr, Image, DTB, initrd
  #   - Partition 2: ext4 (NIXOS_SD) — NixOS root with extlinux boot config
  # ============================================================
  fileSystems."/boot/firmware" = {
    device = "/dev/disk/by-label/FIRMWARE";
    fsType = "vfat";
    options = [
      "nofail"
      "noauto"
    ];
  };

  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
  };

  sdImage = {
    # Firmware partition: U-Boot + boot script + kernel + DTB + initrd
    populateFirmwareCommands = ''
      # Copy U-Boot binary (full FIP: BL2+BL30+BL31+BL33)
      cp ${uboot}/u-boot.bin firmware/u-boot.bin

      # Copy boot script (generated from boot.cmd)
      cp ${bootScript} firmware/boot.scr

      # Copy kernel Image
      cp ${config.boot.kernelPackages.kernel}/Image firmware/Image

      # Copy device tree blob
      cp ${config.boot.kernelPackages.kernel}/dtbs/${dtbFilter} firmware/${dtbFilter}

      # Copy initial RAM disk
      cp ${config.system.build.initialRamdisk}/initrd firmware/initrd
    '';

    # extlinux boot config on root partition (for manual recovery)
    populateRootCommands = ''
      mkdir -p ./files/boot
      ${config.boot.loader.generic-extlinux-compatible.populateCmd} \
        -c ${config.system.build.toplevel} \
        -d ./files/boot
    '';

    # Partition settings
    firmwarePartitionOffset = 8; # 8 MiB gap for U-Boot SPL
    firmwareSize = 64; # 64 MiB for u-boot + kernel + initrd
    firmwarePartitionName = "FIRMWARE";
    firmwarePartitionID = "0x2178694e";

    postBuildCommands = "";
    compressImage = true;
    expandOnBoot = true;
  };

  # ============================================================
  # Networking
  # ============================================================
  networking.useDHCP = true;

  # ============================================================
  # User accounts and SSH
  # ============================================================
  users.users.root.initialPassword = "nixos";
  services.openssh.enable = true;
  services.openssh.permitRootLogin = "yes";

  # ============================================================
  # System settings
  # ============================================================
  time.timeZone = "UTC";
}
