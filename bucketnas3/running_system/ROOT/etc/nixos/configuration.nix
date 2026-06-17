{
  config,
  lib,
  pkgs,
  ...
}:
let
  dataMountPoint = "/srv/dev-disk-by-uuid-1d65e612-b548-4f91-b089-1ad4260ed796";
in
{
  imports = [ ./hardware.nix ];

  system.stateVersion = "26.05";

  # ===== Nix daemon =====
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.nixPath = [
    "nixpkgs=${pkgs.path}"
    "nixos-config=/etc/nixos/configuration.nix"
  ];

  # ===== Networking =====
  networking.hostName = "bucketnas3";
  networking.useNetworkd = true;
  systemd.network.enable = true;
  systemd.network.networks."10-eth" = {
    matchConfig.Type = "ether";
    networkConfig = {
      DHCP = "yes";
      Gateway = "192.168.12.1";
      DNS = "192.168.12.1";
    };
    addresses = [ { Address = "192.168.12.120/24"; } ];
    linkConfig.RequiredForOnline = "yes";
  };

  # ===== SSH =====
  users.users.root.initialPassword = "nixos";
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      X11Forwarding = true;
    };
  };
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDh8HCmy217FqvGI1xMHPS4SvyBviOC6EUedyv8sLhfVJ0beIUR1n6MFBjdt6cUtdq1Whe9vHpGe2jOdrYXY8Vpj3ZHZBv1j+2zTuNFfYU/aJLWR8VQfiXqwvzNmOcH2hcehEQmfzA8/eQlneiRvVVSESXYT+ACiXFaAJRoCqTxrKKUXAGYoANZS+A7tQu2rKQLU/zkQy8CtAUfS3GV9u0GYEuZncTgsR03EPigOtU3B7+IYxqKS2ZeIdQdvsfW+BkOL+KSwl4jmA23V+dnewx9ZCCRUdFAeRtlfTnZar7k/ZQoOWNCAwFFSnv9S2WdPhtJKcQVH2xDWtiDdntbB+l7 getreu@mosel1"
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCnGstsgh1Y7/sMJZTwcQKM9+UnaD+lHsESY0AWQudu/bOLl+lZ7HaOf+Y51sphd0nhQfK6QYgXtL0DEf0Wcnjp9dBrEvO+CCeWN8H6P7Smjrlk2KMstwVNz2CmCv7XjUEHq08TBC8vXIK6lNZInlwXqDEb1ZEGIfvExEJrTayHGWfrrGXsa0iApLWYV6jkjaTs27Fv6An2XHKf41E6xlWmKRUZJhLBhcxWzushPkjHPLnJh3tNzizhZwFD15rbXWjh3qFPOPRZsPzT+AbPRERSqIspf5hyCWjsvjJoTi7isGkowj+ESzW2vFuGB4wUOcIjuzDaqBvXnGqXyD1uNf5N root@mosel1"
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCdNlRdDY8mcdP/hLZ0MHYwVhQzyS0kYzjUKtH+q7tFVjzQNoaPZsX5Pd3nLQPEgz206jRTpGPKO7IKn4v2yFgbsGz/FAgUT2dkkASKLK6zNatr5vGe0Lk34OJDpK5IM0KWPlWbmXTYdXRTYwx/Un8HfHIv7WWP1Qh9lWvTpNiyL5mhMagULE5yrqdz7t5cs6K8tzlbdmsKq/WlR7yYDchGdbwSwr4Ghiv8Ot7Tpvd3Oic3QNpxmSWyZ2l4Z5LJ5LoVEVrWCsJb1wCPVILZ6FiqzrfV9FXrsxI8o/j9Lj8XxCtj17BaciYlxcu+zcnX4DOkl4/WtRtfkJ6zqjM1MfH9 root@saar1"
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDC4P56BpJA8F5fzer6CUEsW0NR1vGOEwjnzwn11GbysIRiKPIfCnuboG7kIw52orZq6UbQN1st0OiVj0gr6RSOt+HazT+L7MXIMjN8TL54RoqOiIWZ68LQ7DwEN/bwww1sRpxJp6jZUkL1MF3uohNXczYIgJezkzly9PV9FxbtKuyjujQRAVDHgQgg9YpZx911uiQ4s69uQS0U0KkvBJQaX8nrbJScxJY9I0WX8NlTVj0seR7xKdY346nrBlzjHDlCwHCwVqHh6sdeTPolwVCujgxP7rcBl8zIDMvvSekhDe0zDLIq9az+JNBE6rAqPCsHrvdGhC892V1DUxLyb3Vf getreu@saar1"
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDC7R8BlM7WnsEGRUWaoQjbHJFU0DNVTLposh/uxSNC5RcJmRHkvyxAgSTBOwaR3fzFCb81H1XZ1E7i1Ls0n9WE9tcLKP3keZyDqwRm6EI3aach1YdGEgkWaCbnma2oVOH+pKp+zPx46z9ATppnBILEpYfJV5hxqrFkorWCLUuS/YcSwUsX2DXNcnN8z4uid01FkLC03pJD5FxKTsTxxZUX6bFcktPBTy06CwmA4xJj36tnHJArN3NlzFZ+OXz9obm0/cy5o0C131yPCG6BoTc/iOA0YrNeKQ/XdI3+POCZVb9fFBx3gocHaRl8hw+SauakSjzrWUOR8AzlUkXYWDtFoeJCg3PAdmzJMmggeE2DZXMwkG9oiw9tb+/CleJDABUT58nXTRrPSFiDFWc1XSP2x/vMRGzyYJcsS62vy23kH6DYw9o+uz999ByL/WL56RwPiE9dIsKllbQM9xbR4/SV2MkwBlct+yJt2L6Ll3Ho8ZDoIe4NZFf6JagpXkx2C9c= getreu@mosel2"
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCrBCiE8wiBzw0e1U1DeZ2EcfcytItMGW+9/u159GUBoc9RS4uRVjb2MUsqBNGHp7W6URKori2PmOb/oPEBry52kq7HzRLyGJ7y7Tao+g1G7Ta9frYLH4MIf7uHIoIuc3DqE6irfzYK5u4/rKY2VfL7UIWRKcMqks2Czo2qWWS0Phzl3wX/wZIAmJVIzA03DPReNO3jRzKnp1h5YqlkwoZxwQJMiLv6vje6VsPqRm8GLiyyK6eMPtiOquXbEO3hHZJ2XdaUUnJMhkITJgLjPWjScldIvXpYUsyeDCMtdLVhsHqeH1NGE4bm6Nps4AP6DSHziN8UvRfg7SgVs80oohWFR6h/Q3Mw2zKCPiyqav10vlArGl23vhuIRIUb0NHVV+gP99LD4giCegbjy4U86V7tUosTUx0e8kxG0nCL+WUloI0iDMhtP6SvEQScMAkRT9vgdJ1C6aQnGDggq9GyZ3cVwFwKu/90euxB1EYKDdUNehLz+ej8BkWOTRSp6bPpGNE= root@mosel2"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILSWG386ITrBk1mkTD5BfRxZvzq/iPQMv2f4lREInQwj getreu@rimi1"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHEXTzTDupEvzxLAadrL3qJcB9VQ386R1v94/Wdi+VfA root@rimi1"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHnBs3PS6wbp5ccphAhNGhIaM5vvlm6KovF44Q8k0g8+ root@maxima2"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP0+/TA0PK/maeE6GQoF8wO8pKzV7X15dXc95EbwJ1Ae getreu@maxima2"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAIyfOhSiCFpWyd32voTg+Ok9jcNoRv49EPrxjEy91m7 root@coop1"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDuN+0qa176iAK1x1nzVJuAeohnXv/YVWQY5pqK5+9ud getreu@coop1"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILco58O7MIisz2TsaEhRLddFz47jPxF0hmz/NTl07mVV root@bauhaus1"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJIDQZrr8+gY0Y0X83Cpbit7ikQlM+ixpJAQxSLK5gA9 getreu@bauhaus1"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGgxeKDkH7k54CdpYh2jmjKMVerW9opmhcQPam5/aLie jgetreu@bronze1"
  ];

  # ===== Users =====
  users.groups.users = { };
  users.users.getreu = {
    isNormalUser = true;
    uid = 1000;
    group = "users";
    extraGroups = [
      "wheel"
      "tty"
      "disk"
      "dialout"
      "audio"
      "video"
      "input"
    ];
    shell = pkgs.bash;
    hashedPassword = "!"; # locked — set via: passwd getreu
  };
  users.users.jens = {
    isNormalUser = true;
    uid = 1001;
    group = "users";
    shell = pkgs.bash;
    hashedPassword = "!";
  };
  users.users."getreu-dev" = {
    isNormalUser = true;
    uid = 1010;
    group = "users";
    shell = pkgs.bash;
    hashedPassword = "!";
  };

  # ===== Avahi (mDNS / DNS-SD — publishes bucketnas3.local) =====
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = false;
      userServices = true;
    };
    extraServiceFiles = {
      ssh = "${pkgs.avahi}/etc/avahi/services/ssh.service";
      sftp-ssh = "${pkgs.avahi}/etc/avahi/services/sftp-ssh.service";
    };
  };

  # ===== NTP =====
  services.chrony.enable = true;

  # ===== CPU frequency governor =====
  powerManagement.cpuFreqGovernor = "ondemand";

  # ===== ZRAM swap (~1.8 GB matching original) =====
  zramSwap.enable = true;
  zramSwap.memoryPercent = 50;

  # ===== Fan control (from bucketnas2b/etc/fancontrol) =====
  hardware.fancontrol.config = lib.mkForce ''
    INTERVAL=10
    DEVPATH=hwmon0=devices/virtual/thermal/thermal_zone0 hwmon2=devices/platform/pwm-fan
    DEVNAME=hwmon0=cpu_thermal hwmon2=pwmfan
    FCTEMPS=hwmon2/pwm1=hwmon0/temp1_input
    MINTEMP=hwmon2/pwm1=40
    MAXTEMP=hwmon2/pwm1=60
    MINSTART=hwmon2/pwm1=150
    MINSTOP=hwmon2/pwm1=30
    MAXPWM=hwmon2/pwm1=90
  '';

  # ===== SATA disk APM / spindown =====
  # apm=128: balanced APM; acoustic_management=128: medium AAM
  # spindown_time=240: 240 * 5s = 20 min idle before spindown
  systemd.services.hdparm-setup = {
    description = "Configure SATA disk APM and spindown";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-udevd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "hdparm-setup" ''
        for disk in /dev/sda /dev/sdb; do
          if [ -b "$disk" ]; then
            ${pkgs.hdparm}/bin/hdparm -q -B 128 -M 128 -S 240 "$disk" || true
          fi
        done
      '';
    };
  };

  # ===== RAID + LUKS kernel modules =====
  boot.kernelModules = [
    "dm_crypt"
    "raid1"
    "md_mod"
  ];

  # ===== Data volume mount point =====
  systemd.tmpfiles.rules = [
    "d ${dataMountPoint} 0755 root root -"
  ];

  # ===== Firewall =====
  # 111   — portmapper (rpcbind)   — NFS
  # 2049  — nfsd                   — NFS
  # 20048 — mountd                 — NFS
  networking.firewall.allowedTCPPorts = [ 111 2049 20048 ];
  networking.firewall.allowedUDPPorts = [ 111 2049 20048 ];

  # ===== NFS server =====
  services.nfs.server.enable = true;
  services.nfs.server.exports = ''
    # NFS export for the encrypted RAID volume.
    # Active only after start-disks mounts the volume.
    ${dataMountPoint} 192.168.12.0/24(rw,sync,no_subtree_check,no_root_squash)
  '';

  # ===== RAID + LUKS disk management =====
  # Usage:
  #   start-disks   — assemble RAID1, unlock LUKS, mount, start NFS
  #   stop-disks    — stop NFS, unmount, close LUKS
  #
  # Remote unlock (from a work machine):
  #   echo hosPF7RilGJ | ssh root@bucketnas3.lan nohup start-disks &
  environment.systemPackages =
    with pkgs;
    [
      mdadm
      cryptsetup
      e2fsprogs
      mc
      hdparm
      iperf3
      smartmontools
      borgbackup
      nfs-utils
    ]
    ++ [
      (writeShellScriptBin "start-disks" ''
        set -e
        RAIDDISK1=/dev/sda
        RAIDDISK2=/dev/sdb
        MD_DEVICE=/dev/md1

        echo "=== APM / spindown ==="
        ${hdparm}/bin/hdparm -q -B 128 -M 128 -S 240 "$RAIDDISK1" || true
        ${hdparm}/bin/hdparm -q -B 128 -M 128 -S 240 "$RAIDDISK2" || true

        echo "=== Assemble RAID1 ==="
        if [ -b "$MD_DEVICE" ]; then
          echo "Already assembled — skipping"
        else
          ${mdadm}/bin/mdadm -A "$MD_DEVICE" ''${RAIDDISK1}1 ''${RAIDDISK2}1
        fi
        ${mdadm}/bin/mdadm --detail --scan

        echo "=== Unlock LUKS: $MD_DEVICE ==="
        if ${cryptsetup}/bin/cryptsetup status md1-crypt > /dev/null 2>&1; then
          echo "Already open — skipping"
        else
          ${cryptsetup}/bin/cryptsetup open --type luks "$MD_DEVICE" md1-crypt
        fi

        echo "=== Mount filesystem ==="
        if mount | grep -q /dev/mapper/md1-crypt; then
          echo "Already mounted — skipping"
        else
          mount -t ext4 -o rw,noexec,relatime /dev/mapper/md1-crypt ${dataMountPoint}
        fi
        echo "Mounted: $(mount | grep /dev/mapper/md1-crypt)"

        echo "=== Restart NFS ==="
        systemctl restart nfs-server.service || true

        echo "=== LUKS status ==="
        ${cryptsetup}/bin/cryptsetup status md1-crypt
      '')

      (writeShellScriptBin "stop-disks" ''
        echo "=== Stop NFS server ==="
        systemctl stop nfs-server.service || true

        echo "=== Unmount filesystem ==="
        MAPPER_DEV="$(ls /dev/mapper/md* 2>/dev/null | head -n 1)"
        if [ -n "$MAPPER_DEV" ]; then
          umount --detach-loop --lazy --force "$MAPPER_DEV" \
            || { echo "$MAPPER_DEV: unmount failed, aborting."; exit 1; }
          sleep 3
        fi

        echo "=== Close LUKS ==="
        ${cryptsetup}/bin/cryptsetup close md1-crypt

        echo "=== Assert key forgotten ==="
        if ${cryptsetup}/bin/cryptsetup status md1-crypt 2>&1 | grep -q "is active"; then
          echo "ERROR: LUKS volume still active — key NOT forgotten!" >&2
          exit 1
        fi
        echo "OK: md1-crypt is inactive — encryption key wiped from kernel"
      '')
    ];

  # ===== USB keyboard workaround =====
  # QMK cheapino (FEE3:0000) fails connect-debounce at ~4.5s on dwc3-meson-g12a.
  # Rebinding the controller after udevd starts (~8s later) triggers a clean xHCI
  # reset, allowing the keyboard to enumerate in ~261ms.
  systemd.services.usb-rebind = {
    description = "Rebind dwc3 USB controller to recover keyboard after debounce failure";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-udevd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "usb-rebind" ''
        sleep 8
        echo ffe09000.usb > /sys/bus/platform/drivers/dwc3-meson-g12a/unbind
        sleep 0.5
        echo ffe09000.usb > /sys/bus/platform/drivers/dwc3-meson-g12a/bind
      '';
    };
  };

  # ===== Local console login =====
  systemd.services."getty@tty1".enable = true;

  # Serial console at 115200 baud on ttyAML0 (Amlogic meson_uart driver)
  systemd.services."getty@ttyAML0" = {
    enable = true;
    serviceConfig.ExecStart = lib.mkForce [
      ""
      "${pkgs.util-linux}/bin/agetty --login-program ${pkgs.shadow}/bin/login 115200 ttyAML0 vt102"
    ];
  };

  # ===== Login banner =====
  environment.etc."issue".text = ''
    ========================================
    bucketnas3  |  NixOS
    Serial:   ttyAML0  115200 baud  8N1
    Display:  tty1            (HDMI)
    Network:  192.168.12.120 + DHCP
    SSH:      root@192.168.12.120
    ========================================
  '';

  # ===== Time zone =====
  time.timeZone = "Europe/Berlin";
}
