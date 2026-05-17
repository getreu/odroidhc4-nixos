{
  config,
  lib,
  pkgs,
  sdImageModule,
  ...
}:

let
  dtbFile = "meson-sm1-odroid-hc4.dtb";

  kernelAddr = "0x10000000";
  fdtAddr = "0x11000000";
  ramdiskAddr = "0x11800000";

  # Generate boot.scr from boot.cmd using mkimage
  # runCommandLocal ensures this builds on the HC4 itself (no sandbox)
  # where mkimage is available from nixpkgs' ubootTools package
  bootScript = pkgs.runCommandLocal "boot.scr" { } ''
    ${pkgs.ubootTools}/bin/mkimage -A arm64 -O linux -T script -C none \
      -a 0 -e 0 \
      -n "NixOS Odroid HC4" \
      -d ${pkgs.writeText "boot.cmd" ''
        setenv bootargs "console=ttyS0,115200n8 console=tty0 root=/dev/mmcblk0p2 rw rootwait rootfstype=ext4"
        load mmc 0:1 ${kernelAddr} Image
        load mmc 0:1 ${fdtAddr} ${dtbFile}
        load mmc 0:1 ${ramdiskAddr} initrd
        booti ${kernelAddr} ${ramdiskAddr} ${fdtAddr}
      ''} $out
  '';

  # Armbian ships U-Boot at this path on the HC4.
  # runCommandLocal builds on the HC4 itself (no sandbox) so it can
  # access the Armbian host filesystem path /usr/lib/linux-u-boot-current-odroidhc4/.
  armbianUboot = pkgs.runCommandLocal "armbian-uboot-hc4" { } ''
    mkdir -p $out
    cp /usr/lib/linux-u-boot-current-odroidhc4/u-boot.bin $out/u-boot.bin
  '';

in

{
  system.stateVersion = "25.11";

  # Boot loader
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  boot.kernelParams = [
    "console=ttyS0,115200n8"
    "console=tty0"
    "root=/dev/mmcblk0p2"
    "rootfstype=ext4"
    "rootwait"
  ];

  # Hardware
  hardware.deviceTree.filter = dtbFile;

  # Fan control (pwm-fan)
  hardware.fancontrol.enable = lib.mkDefault true;
  hardware.fancontrol.config = lib.mkDefault ''
    INTERVAL=10
    DEVPATH=hwmon0=devices/virtual/thermal/thermal_zone0 hwmon2=devices/platform/pwm-fan
    DEVNAME=hwmon0=cpu_thermal hwmon2=pwmfan
    FCTEMPS=hwmon2/pwm1=hwmon0/temp1_input
    MINTEMP=hwmon2/pwm1=50
    MAXTEMP=hwmon2/pwm1=60
    MINSTART=hwmon2/pwm1=20
    MINSTOP=hwmon2/pwm1=28
    MINPWM=hwmon2/pwm1=0
    MAXPWM=hwmon2/pwm1=255
  '';

  # Watchdog
  systemd.settings.Manager.RuntimeWatchdogSec = lib.mkDefault 60;

  # File systems
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
  };

  # SD image module (imported via specialArgs from flake.nix)
  imports = [
    sdImageModule
  ];

  # SD image configuration
  sdImage = {
    populateFirmwareCommands = ''
      # Copy Armbian's pre-built U-Boot FIP binary
      cp ${armbianUboot}/u-boot.bin firmware/

      # Copy boot script
      cp ${bootScript} firmware/boot.scr

      # Copy kernel Image
      cp ${config.boot.kernelPackages.kernel}/Image firmware/Image

      # Copy device tree
      cp ${config.boot.kernelPackages.kernel}/dtbs/${dtbFile} firmware/${dtbFile}

      # Copy initial RAM disk
      cp ${config.system.build.initialRamdisk}/initrd firmware/initrd
    '';

    populateRootCommands = ''
      mkdir -p ./files/boot
      ${config.boot.loader.generic-extlinux-compatible.populateCmd} \
        -c ${config.system.build.toplevel} \
        -d ./files/boot
    '';

    firmwarePartitionOffset = 8;
    firmwareSize = 64;
    firmwarePartitionName = "FIRMWARE";
    compressImage = true;
    expandOnBoot = true;
  };

  # Networking
  networking.useDHCP = true;

  # Users
  users.users.root.initialPassword = "nixos";
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "yes";

  # Time
  time.timeZone = "UTC";
}
