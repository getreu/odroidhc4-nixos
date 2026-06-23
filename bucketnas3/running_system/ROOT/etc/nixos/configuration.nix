{
  config,
  lib,
  pkgs,
  ...
}:
let
  dataMountPoint = "/srv/dev-disk-by-uuid-1d65e612-b548-4f91-b089-1ad4260ed796";
  diskHealth = pkgs.writeTextFile {
    name = "disk-health";
    executable = true;
    destination = "/bin/disk-health";
    text = ''
      #!${pkgs.nushell}/bin/nu

      def ok   [msg: string] { print $"  (ansi green) OK (ansi reset)  ($msg)" }
      def warn [msg: string] { print $"  (ansi yellow)WARN(ansi reset) ($msg)" }
      def fail [msg: string] { print $"  (ansi red)FAIL(ansi reset) ($msg)" }

      def get_attr [attrs: list, name: string] {
        try { $attrs | where name == $name | first | get raw.value } catch { 0 }
      }

      mut issues = 0

      print ""
      print $"=== Health Report: (date now | format date '%Y-%m-%d %H:%M') ==="

      for disk in ["/dev/sda" "/dev/sdc" "/dev/sdb"] {
        if not ($disk | path exists) { continue }

        let data = (^smartctl --json -a $disk | complete | get stdout | from json)
        let model = (try { $data.model_name } catch { "unknown" })
        print $"-- ($disk)  ($model) --"

        let passed = (try { $data.smart_status.passed } catch { false })
        if $passed {
          ok "SMART: PASSED"
        } else {
          $issues += 1; fail "SMART: FAILED"
        }

        let attrs = (try { $data.ata_smart_attributes.table } catch { [] })

        let hours = (get_attr $attrs "Power_On_Hours")
        if $hours > 100000 {
          $issues += 1; fail $"Power-on hours: ($hours)  >100k — replace soon"
        } else if $hours > 50000 {
          warn $"Power-on hours: ($hours)  >50k — aging"
        } else {
          ok $"Power-on hours: ($hours)"
        }

        let realloc = (get_attr $attrs "Reallocated_Sector_Ct")
        if $realloc > 0 {
          $issues += 1; fail $"Reallocated sectors: ($realloc)"
        } else {
          ok "Reallocated sectors: 0"
        }

        let pending = (get_attr $attrs "Current_Pending_Sector")
        if $pending > 0 { $issues += 1; fail $"Pending sectors: ($pending)" }

        let temp = (try { $data.temperature.current } catch { 0 })
        if $temp > 50 {
          $issues += 1; fail $"Temperature: ($temp) C"
        } else if $temp > 42 {
          warn $"Temperature: ($temp) C"
        } else {
          ok $"Temperature: ($temp) C"
        }

        print ""
      }

      print "-- RAID --"
      let mdstat = (open /proc/mdstat)
      if ($mdstat | str contains "[UU]") {
        ok "md1: clean [UU]"
      } else {
        $issues += 1
        let reason = (
          $mdstat
          | lines
          | where { |l| $l =~ '^md1' }
          | first?
          | default "unknown"
          | str replace -r '^md1 : ' ""
          | str trim
        )
        fail $"md1: DEGRADED — ($reason)"
      }
      print ""

      print "-- Kernel I/O errors (7 days) --"
      let errors = (
        ^journalctl -k --since "7 days ago"
        | lines
        | where { |l| $l =~ 'I/O error|ata\d+\.\d+: exception|medium error|read error correction' }
        | length
      )
      if $errors == 0 {
        ok "No I/O errors in kernel log"
      } else {
        warn $"($errors) kernel I/O errors — run: journalctl -k --since '7 days ago' | grep -iE 'I/O error'"
      }
      print ""

      if $issues > 0 {
        print $"(ansi red)*** ($issues) issues detected above ***(ansi reset)\n"
      }
    '';
  };
in
{
  imports = [ ./hardware.nix ];

  system.stateVersion = "26.05";

  # ===== Nix daemon =====
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  # builtins.unsafeDiscardStringContext is required here to avoid a Nix build
  # error caused by derivation name length.
  #
  # Without it, the string context of pkgs.path would force Nix to include
  # pkgs.path in the system closure.  pkgs.path is a filtered-source derivation
  # (lib.cleanSource applied to the nixpkgs tree).  To build it, Nix runs
  # filterSource on the already-long-named nixpkgs source, creating a new
  # derivation whose name is derived from the input's name.  The input name is
  # already ~205 characters, and prepending the new store hash pushes it past
  # Nix's 211-character limit.
  #
  # builtins.unsafeDiscardStringContext (toString pkgs.path) avoids this:
  #   - toString pkgs.path        → /nix/store/lv089…-source  (same value)
  #   - unsafeDiscardStringContext → strips the context annotation, making it a
  #                                  plain string with no recorded dependency
  #
  # The resulting NIX_PATH entry is correct at runtime because pkgs.path is
  # already in the store; we just don't force Nix to re-derive it during build.
  nix.nixPath = [
    "nixpkgs=${builtins.unsafeDiscardStringContext (toString pkgs.path)}"
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
  users.groups.getreu = { gid = 1000; };
  users.groups.jens = { gid = 1001; };
  users.groups."getreu-dev" = { gid = 1010; };
  users.users.getreu = {
    isNormalUser = true;
    uid = 1000;
    group = "getreu";
    extraGroups = [
      "users"
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
    group = "jens";
    extraGroups = [ "users" ];
    shell = pkgs.bash;
    hashedPassword = "!";
  };
  users.users."getreu-dev" = {
    isNormalUser = true;
    uid = 1010;
    group = "getreu-dev";
    extraGroups = [ "users" ];
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
        for part in \
          /dev/disk/by-partuuid/0b5f33ec-1422-dd42-b512-bff872fa7d27 \
          /dev/disk/by-partuuid/d92296d4-a7ea-d448-afd3-79bdfec4ddba; do
          disk=/dev/$(${pkgs.util-linux}/bin/lsblk -ndo pkname "$(realpath "$part")")
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
    "d /srv/dev-disk-by-uuid-45EFA09D11DEDD23 0755 root root -"
  ];

  # ===== NTFS disk (sdb) =====
  fileSystems."/srv/dev-disk-by-uuid-45EFA09D11DEDD23" = {
    device = "/dev/disk/by-partuuid/472c237d-01";
    fsType = "ntfs";
    options = [ "ro" "nofail" ];
  };

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
    ${dataMountPoint}/video-audio 192.168.12.0/24(rw,sync,no_subtree_check,no_root_squash)
    /srv/dev-disk-by-uuid-45EFA09D11DEDD23 192.168.12.0/24(ro,sync,no_subtree_check,no_root_squash)
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
      unison
      nushell
      diskHealth
    ]
    ++ [
      (writeShellScriptBin "start-disks" ''
        set -e
        RAIDPART1=/dev/disk/by-partuuid/0b5f33ec-1422-dd42-b512-bff872fa7d27
        RAIDPART2=/dev/disk/by-partuuid/d92296d4-a7ea-d448-afd3-79bdfec4ddba
        RAIDDISK1=/dev/$(${pkgs.util-linux}/bin/lsblk -ndo pkname "$(realpath "$RAIDPART1")")
        RAIDDISK2=/dev/$(${pkgs.util-linux}/bin/lsblk -ndo pkname "$(realpath "$RAIDPART2")")
        MD_DEVICE=/dev/md1

        echo "=== Set spindown ==="
        ${hdparm}/bin/hdparm -q -B 128 -M 128 -S 240 "$RAIDDISK1" > /dev/null 2>&1 || true
        ${hdparm}/bin/hdparm -q -B 128 -M 128 -S 240 "$RAIDDISK2" > /dev/null 2>&1 || true
        echo "spindown: APM=128 standby=20min set on $RAIDDISK1 $RAIDDISK2"
        echo ""

        echo "=== Assemble RAID1 ==="
        if [ -b "$MD_DEVICE" ]; then
          echo "Already assembled — skipping"
        else
          ${mdadm}/bin/mdadm -A "$MD_DEVICE" "$RAIDPART1" "$RAIDPART2"
        fi
        ${mdadm}/bin/mdadm --detail --scan
        echo ""

        echo "=== Unlock LUKS: $MD_DEVICE ==="
        if ${cryptsetup}/bin/cryptsetup status md1-crypt > /dev/null 2>&1; then
          echo "Already open — skipping"
        else
          ${cryptsetup}/bin/cryptsetup open --type luks "$MD_DEVICE" md1-crypt
        fi
        ${cryptsetup}/bin/cryptsetup status md1-crypt 2>/dev/null | head -1
        echo ""

        echo "=== Mount filesystem ==="
        if mount | grep -q /dev/mapper/md1-crypt; then
          echo "Already mounted — skipping"
        else
          mount -t ext4 -o rw,noexec,relatime /dev/mapper/md1-crypt ${dataMountPoint}
        fi
        echo "Mounted: $(mount | grep /dev/mapper/md1-crypt)"
        echo ""

        echo "=== Restart NFS ==="
        systemctl restart nfs-server.service || true
        ${pkgs.nfs-utils}/bin/exportfs -v 2>/dev/null | awk -v h="$(hostname)" '/^\// {print "  mount -t nfs " h ":" $1 " /mnt"}'

        ${diskHealth}/bin/disk-health
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
