{
  config,
  lib,
  pkgs,
  ...
}:
{
  # ===== Boot loader =====
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = false;

  # ===== Kernel parameters =====
  # ttyAML0 = Amlogic meson_uart driver (mainline kernel); tty0 for HDMI once DRM is up
  boot.kernelParams = [
    "console=ttyAML0,115200"
    "root=LABEL=NIXOS_SD"
    "rootfstype=ext4"
    "rootwait"
    "loglevel=7"
    "console=tty0"
    # ASMedia ASM1061 SATA via PCIe loses link ~40s after boot due to ASPM L1
    # putting the Amlogic meson-pcie controller to sleep non-recoverably.
    "pcie_aspm=off"
    # Prevent keyboards from autosuspending on dwc3-meson-g12a (they don't wake).
    "usbcore.autosuspend=-1"
  ];

  # ===== Hardware =====
  hardware.deviceTree.filter = "meson-sm1-odroid-hc4.dtb";

  # Ethernet: stmmac + dwmac_meson8b (Amlogic glue layer) needed for HC4 ethernet
  # dwmac_meson8b has no dependencies — it's the Amlogic-specific driver
  # that probes the device tree node "amlogic,meson-g12a-dwmac".
  # stmmac is the generic Synopsys DesignWare MAC framework.
  # Both are needed — stmmac alone is NOT enough.
  # ext4 must be included so the initrd can mount the root filesystem.
  boot.initrd.kernelModules = [
    "stmmac"
    "dwmac_meson8b"
    "ext4"
  ];

  # Amlogic meson DRM + HDMI — must be explicit; meson-canvas is a hard dep of
  # meson-drm and was missing from prior initrd attempts, causing silent failure.
  # modprobe resolves dw-hdmi, cec, drm_dma_helper, drm_display_helper automatically.
  boot.kernelModules = [
    "mdio-mux-meson-g12a" # MDIO mux for RTL8211F PHY — sits behind amlogic,g12a-mdio-mux
    "meson-canvas"
    "meson-drm"
    "meson_dw_hdmi"
  ];

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

  systemd.settings.Manager.RuntimeWatchdogSec = lib.mkDefault 60;

  # ===== File systems =====
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
  };

  # ===== Keep boot files in sync with the active generation =====
  # U-Boot loads /Image, /initrd, /dtb/... from fixed paths on the ext4 root.
  # nixos-rebuild switch updates the profile symlink but not these files.
  # Placing this in hardware.nix ensures it runs for any config that imports it,
  # including the NAS config, without requiring manual edits after reflash.
  environment.systemPackages = [ pkgs.dtc ];
  system.activationScripts.update-boot-files = {
    text = ''
      cp -f ${config.boot.kernelPackages.kernel}/Image /Image
      cp -f ${config.system.build.initialRamdisk}/initrd /initrd
      cp -f ${config.hardware.deviceTree.package}/amlogic/meson-sm1-odroid-hc4.dtb /dtb/meson-sm1-odroid-hc4.dtb
      ${pkgs.dtc}/bin/fdtput -t s /dtb/meson-sm1-odroid-hc4.dtb /soc/gpu@ffe40000 status disabled
    '';
  };
}
