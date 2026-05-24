---
title: "# Armbian → NixOS Migration Notes for bucketnas2"
subtitle: Note
author: Jgetreu
date: 2026-05-16
lang: en-US
languages:
  - en-US
  - de-DE
---

# Armbian → NixOS Migration Notes for bucketnas2

## System Hardware

| Property          | Value                                                                                              |
| ----------------- | -------------------------------------------------------------------------------------------------- |
| **Device**        | Hardkernel ODROID HC4                                                                              |
| **SoC**           | Amlogic Meson SM1 (meson64)                                                                        |
| **CPU**           | 4x Cortex-A55 @ 1-2.1 GHz (aarch64)                                                                |
| **RAM**           | 3.7 GB (3 859 312 kB)                                                                              |
| **Swap**          | 1.8 GB zram                                                                                        |
| **Kernel**        | 6.18.10-current-meson64 (PREEMPT)                                                                  |
| **Armbian Board** | odroidhc4, BOARDFAMILY=meson-sm1, ARCH=arm64                                                       |
| **CPU Flags**     | fp asimd evtstrm aes pmull sha1 sha2 crc32 atomics fphp asimdhp cpuid asimdrdm lrcpc dcpop asimddp |
| **L1d Cache**     | 128 KiB (4 instances)                                                                              |
| **Uptime**        | ~1.28 days (at last check)                                                                         |

## Storage Layout

```
eMMC: /dev/mmcblk0 (29.72 GB)
  └─ /dev/mmcblk0p1  UUID=8d13d9f1-c65d-4bfe-8ecb-8687863fb1c0  → / (ext4, 81% used)
     └─ /var/log.hdd (overlay via bind-mount for log2ram)

RAID1 Array: /dev/md1
  ├─ /dev/sda1 (3.00 TB, WDC WD30EZRZ-00WN9B0, 5400 rpm)  label=bucketnas2:1
  │    SMART: PASSED, Serial: WD-WCC4E5LNAKEL, SATA 3.0 6.0 Gb/s
  └─ /dev/sdb1 (3.00 TB, ST3000DM001-1CH166, 7200 rpm)     label=bucketnas2:1
       SMART: PASSED, Serial: Z1F4KAF0, SATA 3.1 6.0 Gb/s
  └─ RAID UUID: 492308d1:bdbf-f268-81e4-6a60c9f08e98
  └─ LUKS: /dev/md1  UUID=0a8c7656-cfbd-4e78-be66-211c449e317c  (LUKS2, AES-XTS-plain64, 512-bit)
     └─ /dev/mapper/md1-crypt  UUID=1d65e612-b548-4f91-b089-1ad4260ed796  → data (ext4, 27% used, 1.8T free)

zram (block devices):
  ├─ /dev/zram0  (1.84 GB) → swap
  ├─ /dev/zram1  (50 MB, label=log2ram) → /var/log (ext4, discard)
  └─ /dev/zram2  (unused)

/mnt: UUID=45EFA09D11DEDD23  (auto, nofail) — NTFS volume, currently not found
```

**Current mount points (from `findmnt`):**

```
TARGET SOURCE FSTYPE OPTIONS
/ /dev/mmcblk0p1 ext4 rw,noatime,errors=remount-ro,commit=600
/tmp tmpfs rw,nosuid,relatime
/var/log /dev/zram1 ext4 rw,nosuid,nodev,noexec,relatime,discard
/var/log.hdd /dev/mmcblk0p1[/var/log] ext4 rw,noatime,errors=remount-ro,commit=600
/srv/dev-disk-by-uuid-1d65e612-b548-4f91-b089-1ad4260ed796 /dev/mapper/md1-crypt ext4 rw,noexec,relatime
```

**fstab (`/etc/fstab`):**

```
UUID=8d13d9f1-c65d-4bfe-8ecb-8687863fb1c0 /       ext4 defaults,noatime,commit=600,errors=remount-ro  0 1
tmpfs /tmp tmpfs defaults,nosuid 0 0
UUID=1d65e612-b548-4f91-b089-1ad4260ed796 /srv/dev-disk-by-uuid-1d65e612-b548-4f91-b089-1ad4260ed796 auto noauto,x-cockpit-never-auto,x-parent=0a8c7656-cfbd-4e78-be66-211c449e317c,x-parent=492308d1:bdbff268:81e46a60:c9f08e98 0 0
UUID=45EFA09D11DEDD23 /mnt auto nofail 0 0
```

**modprobe configurations:**

```
# /etc/modprobe.d/blacklist-odroidhc4.conf
blacklist simpledrm

# /etc/modprobe.d/mdadm.conf
options md_mod start_ro=1

# /etc/modprobe.d/8189fs.conf (wifi dongle?)
options 8189fs rtw_power_mgnt=0 rtw_enusbss=0

# /etc/modprobe.d/r8723bs.conf (wifi dongle?)
options r8723bs rtw_power_mgnt=0 rtw_enusbss=0
```

## Network

| Property      | Value                                                       |
| ------------- | ----------------------------------------------------------- |
| **Interface** | `end0` (Realtek, MAC: 00:1e:06:49:19:82)                    |
| **IPv4**      | `192.168.12.120/24` (DHCP)                                  |
| **IPv6**      | `2001:1b28:2302:3100::f120/128` (global) + ULA + link-local |
| **Gateway**   | `192.168.12.1`                                              |
| **DNS**       | `192.168.12.1`, `fdde::1`                                   |
| **Hostname**  | `bucketnas2`                                                |
| **Config**    | NetworkManager (keyfile backend)                            |

**NetworkManager connections:**
| Connection | UUID | Type | Device |
|---|---|---|---|
| `netplan-all-eth-interfaces` | 9f62286e-... | ethernet | end0 (active) |
| `Ethernet connection 1` | 4f7475b8-... | ethernet | -- (not connected) |
| `lo` | 0090c1d8-... | loopback | lo (active) |

**Connection details (netplan-all-eth-interfaces):**

- DHCP for both IPv4 and IPv6
- `addr-gen-mode=default` for IPv6

**`/etc/hosts`:**

```
127.0.0.1   localhost
127.0.1.1   bucketnas2
::1         localhost bucketnas2 ip6-localhost ip6-loopback
fe00::0     ip6-localnet
ff00::0     ip6-mcastprefix
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
```

## Users

| User         | UID  | GID  | Shell         | Home             | Notes                                              |
| ------------ | ---- | ---- | ------------- | ---------------- | -------------------------------------------------- |
| `root`       | 0    | 0    | /usr/bin/bash | /root            | —                                                  |
| `getreu`     | 1000 | 1000 | /bin/bash     | /home/getreu     | Jens Getreu, zsh/oh-my-zsh, Rust/cargo, sudo group |
| `jens`       | 1001 | 1001 | /bin/bash     | /home/jens       | Jens Getreu (Work), zsh/oh-my-zsh                  |
| `getreu-dev` | 1010 | 1010 | /bin/bash     | /home/getreu-dev | Jens Getreu (dev), zsh/oh-my-zsh                   |

**Service/system users:**
| User | UID | Notes |
|---|---|---|
| `daemon` | 1 | — |
| `vnstat` | 101 | vnStat daemon |
| `avahi-autoipd` | 102 | Avahi autoip |
| `iperf3` | 103 | — |
| `_chrony` | 104 | Chrony daemon |
| `sshd` | 105 | — |
| `rpc` | 106 | — |
| `statd` | 107 | — |
| `polkitd` | 997 | — |
| `nm-openvpn` | 108 | — |
| `libvirt-qemu` | 64055 | — |
| `libvirtdbus` | 109 | — |
| `cockpit-ws` | 110 | — |
| `avahi` | 112 | — |
| `minidlna` | 113 | MiniDLNA server |
| `gerbera` | 111 | Gerbera Media Server |
| `emby` | 999 | Emby Server |
| `dnsmasq` | 996 | — |
| `Debian-exim` | 114 | Mail transfer agent |

**Key group memberships for `getreu`:**
`tty`, `disk`, `dialout`, `sudo`, `audio`, `video`, `plugdev`, `games`, `users`, `systemd-journal`, `input`, `netdev`, `render` (shared with emby), `docker`

**Other notable groups:**
`users`: getreu, jens, getreu-dev
`sambashare`: —
`docker`: —
`kvm`: —
`libvirt`: —

## SSH

### SSH Server (`/etc/ssh/sshd_config`)

```
PermitRootLogin yes
KbdInteractiveAuthentication no
UsePAM yes
X11Forwarding yes
PrintMotd no
AcceptEnv LANG LC_* COLORTERM NO_COLOR
Subsystem sftp /usr/lib/openssh/sftp-server
Include /etc/ssh/sshd_config.d/*.conf
```

No overrides in `/etc/ssh/sshd_config.d/`.

### Root SSH Authorized Keys (15 keys from 7 machines)

```
getreu@mosel1, root@mosel1          (ssh-rsa)
getreu@saar1, root@saar1            (ssh-rsa)
getreu@mosel2, root@mosel2          (ssh-rsa)
getreu@rimi1, root@rimi1            (ssh-ed25519)
root@maxima2, getreu@maxima2        (ssh-ed25519)
root@coop1, getreu@coop1            (ssh-ed25519)
root@bauhaus1, getreu@bauhaus1      (ssh-ed25519)
jgetreu@bronze1                      (ssh-ed25519)
```

### Root SSH Known Hosts (22 entries)

### User SSH Keys

| User         | Keys                                                                           |
| ------------ | ------------------------------------------------------------------------------ |
| `getreu`     | `id_rsa` + `id_rsa.pub` (generated Feb 2025), `known_hosts`, `known_hosts.old` |
| `jens`       | None                                                                           |
| `getreu-dev` | None                                                                           |

## Enabled Systemd Services

| Service                             | State           | Notes                    |
| ----------------------------------- | --------------- | ------------------------ |
| `armbian-hardware-monitor.service`  | enabled         | —                        |
| `armbian-hardware-optimize.service` | enabled         | —                        |
| `armbian-led-state.service`         | enabled         | LED state control        |
| `armbian-ramlog.service`            | enabled         | RAM logging              |
| `armbian-zram-config.service`       | enabled         | zram setup               |
| `avahi-daemon.service`              | enabled         | mDNS/DNS-SD              |
| `chrony.service`                    | enabled         | NTP client/server        |
| `containerd.service`                | enabled         | Container runtime        |
| `cron.service`                      | enabled         | Cron daemon              |
| `e2scrub_reap.service`              | enabled         | ext4 scrub               |
| `exim4.service`                     | enabled         | Mail transfer agent      |
| `haveged.service`                   | enabled         | Hardware RNG entropy     |
| `hd-idle.service`                   | enabled         | Disk spin-down           |
| `iperf3.service`                    | enabled         | Network benchmark        |
| `libvirt-guests.service`            | enabled         | Libvirt guest management |
| `libvirtd.service`                  | enabled         | Libvirt daemon           |
| `lm-sensors.service`                | enabled         | Hardware monitoring      |
| `lvm2-monitor.service`              | enabled         | LVM monitoring           |
| `mdmonitor.service`                 | enabled         | RAID monitoring          |
| `NetworkManager-dispatcher.service` | enabled         | NM event dispatcher      |
| `NetworkManager.service`            | enabled         | NetworkManager           |
| `nfs-blkmap.service`                | enabled         | NFS block map            |
| `nfs-server.service`                | enabled         | NFS server               |
| `openvpn.service`                   | enabled         | OpenVPN                  |
| `rng-tools.service` (alias)         | enabled         | RNG daemon               |
| `rng-tools-debian.service`          | enabled         | RNG tools                |
| `rsyslog.service`                   | enabled         | System logging           |
| `ssh.service` (alias)               | enabled         | SSH server               |
| `sysfs.service` (alias)             | enabled         | Sysfs configuration      |
| `sysfsutils.service`                | enabled         | Sysfs utilities          |
| `systemd-fsck@.service`             | enabled-runtime | FS check on boot         |

### Disabled but Installed Services

| Service                              | State    |
| ------------------------------------ | -------- |
| `armbian-firstrun.service`           | disabled |
| `emby-server.service`                | disabled |
| `fancontrol.service`                 | disabled |
| `hc4-fan-control.service`            | disabled |
| `ifupdown-wait-online.service`       | disabled |
| `mdcheck_continue.service`           | static   |
| `mdcheck_start.service`              | static   |
| `NetworkManager-wait-online.service` | disabled |
| `odroid-hc4-fan-control.service`     | disabled |
| `odroid-hc4-pwm-setup.service`       | disabled |
| `rsync.service`                      | disabled |
| `smartmontools.service`              | disabled |
| `sysstat.service`                    | disabled |
| `systemd-networkd.service`           | masked   |
| `smbd.service`                       | masked   |

### Custom Systemd Units

| Unit                             | Type    | Description                                                              |
| -------------------------------- | ------- | ------------------------------------------------------------------------ |
| `odroid-hc4-pwm-setup.service`   | oneshot | Setup PWM fan control (no DefaultDependencies)                           |
| `hc4-fan-control.service`        | oneshot | Odroid HC4 PWM fan control script (workaround for broken pwm_fan driver) |
| `hc4-fan-control.timer`          | timer   | Runs hc4-fan-control every 30s (OnBootSec=10s, OnUnitActiveSec=30s)      |
| `odroid-hc4-fan-control.service` | oneshot | Temperature-based PWM fan control (RemainAfterExit=yes)                  |
| `odroid-hc4-fan-control.timer`   | timer   | Runs fan control every 60s (OnBootSec=10, OnUnitActiveSec=60)            |
| `fan-trip-points.service`        | oneshot | Set fan trip points (no DefaultDependencies)                             |

### Custom Scripts in `/usr/local/sbin/`

| Script                      | Size   |
| --------------------------- | ------ |
| `fan-trip-points.sh`        | 566 B  |
| `hc4-fan-control.sh`        | 925 B  |
| `odroid-hc4-fan-control.sh` | 1479 B |
| `odroid-hc4-pwm-setup.sh`   | 1080 B |

## Applications & Services

### Media Servers

| Application     | Package                 | Version  | Config User | Notes                                                                   |
| --------------- | ----------------------- | -------- | ----------- | ----------------------------------------------------------------------- |
| **MiniDLNA**    | minidlna                | —        | minidlna    | `media_dir=/var/lib/minidlna`, port 8200, album art patterns configured |
| **Gerbera**     | gerbera (external repo) | —        | gerbera     | Config at `/etc/gerbera/config.xml`                                     |
| **Emby Server** | emby-server (local deb) | 4.9.0.42 | emby        | Package from local .deb, service disabled                               |

### Container & Virtualization

| Component      | Package                     | Notes                                                                                  |
| -------------- | --------------------------- | -------------------------------------------------------------------------------------- |
| **containerd** | containerd.io (trixie repo) | 2.2.3                                                                                  |
| **Docker**     | docker (external repo)      | Group `docker` exists, empty daemon.json, no active containers seen                    |
| **libvirt**    | libvirt (Debian trixie)     | QEMU/KVM, default network configured, `libvirt-guests.service` enabled                 |
| **Cockpit**    | cockpit (337) + plugins     | Web console with: bridge, file-sharing, machines, networkmanager, packagekit, storaged |

### Other Services

| Service          | Package              | Notes                                                                    |
| ---------------- | -------------------- | ------------------------------------------------------------------------ |
| **Chrony** (NTP) | chrony (4.6.1)       | Pool: 2.debian.pool.ntp.org, rtcsync, keyfile auth                       |
| **Avahi** (mDNS) | avahi-daemon (0.8)   | IPv4+IPv6, wide-area enabled, ratelimit 1s/1000 burst                    |
| **Exim4** (Mail) | exim4 (4.98.2)       | Light daemon                                                             |
| **Sysstat**      | sysstat              | Installed but **disabled** (ENABLED="false"), cron collects every 10 min |
| **hd-idle**      | hd-idle (1.21)       | Disks spin down after 600s idle                                          |
| **cpufrequtils** | cpufrequtils (local) | Governor: **ondemand**, min 667 MHz, max 2100 MHz (ENABLE=false)         |
| **haveged**      | haveged (1.9.19)     | Hardware RNG entropy source                                              |
| **iPerf3**       | iperf3 (3.18)        | Network benchmarking                                                     |
| **vnStat**       | vnstat               | Network traffic monitoring                                               |
| **NFS Server**   | nfs-kernel-server    | exports file is empty                                                    |
| **Samba**        | samba                | smb.conf minimal: only `include = registry`                              |
| **OpenVPN**      | openvpn              | Client and server configs available, service enabled                     |

## Cron Jobs

**System crontab (`/etc/crontab`):**

```
17 *  * * *  root  run-parts /etc/cron.hourly
25 6  * * *  root  run-parts /etc/cron.daily (or anacron)
47 6  * * 7  root  run-parts /etc/cron.weekly (or anacron)
52 6  1 * *  root  run-parts /etc/cron.monthly (or anacron)
```

**Cron.d entries:**
| File | Schedule | Command |
|---|---|---|
| `armbian-check-battery` | commented out | `/usr/lib/armbian/armbian-check-battery-shutdown` (every 5 min if enabled) |
| `armbian-truncate-logs` | _/15 min + @reboot | `/usr/lib/armbian/armbian-truncate-logs` |
| `armbian-updates` | @reboot + @daily | `/usr/lib/armbian/armbian-apt-updates` |
| `e2scrub_all` | Sun 3:30 + daily 3:10 | e2fsprogs ext4 scrub |
| `sysstat` | 5-55/10 _ \* \* \* + 59 23 | `debian-sa1` for statistics |

## System Configuration

### CPU Frequency

| Property                | Value                                            |
| ----------------------- | ------------------------------------------------ |
| **Governor**            | ondemand (all 4 cores)                           |
| **Min MHz**             | 1000                                             |
| **Max MHz**             | 2100                                             |
| **cpufrequtils config** | ENABLE=false (managed by ondemand kernel driver) |

### Log Management (log2ram)

| Property               | Value                                                       |
| ---------------------- | ----------------------------------------------------------- |
| **Backend**            | zram1 (50 MB)                                               |
| **Mount**              | `/var/log` (ext4, nosuid, nodev, noexec, discard)           |
| **Persistent overlay** | `/var/log.hdd` on eMMC `/var/log` subvolume (ext4, noatime) |

### ZRAM

| Device  | Size    | Purpose              |
| ------- | ------- | -------------------- |
| `zram0` | 1.84 GB | swap (priority 5)    |
| `zram1` | 50 MB   | `/var/log` (log2ram) |
| `zram2` | —       | Unused               |

### APT Sources

| Source                  | File                                             | Details                                                                                 |
| ----------------------- | ------------------------------------------------ | --------------------------------------------------------------------------------------- |
| Debian trixie (main)    | `/etc/apt/sources.list`                          | main + contrib + non-free + non-free-firmware                                           |
| Debian trixie-updates   | Same                                             | —                                                                                       |
| Debian trixie-backports | Same                                             | —                                                                                       |
| Debian trixie-security  | Same                                             | —                                                                                       |
| Armbian                 | `/etc/apt/sources.list.d/armbian.list`           | `deb [signed-by=...gpg] http://apt.armbian.com trixie main trixie-utils trixie-desktop` |
| Armbian Config          | `/etc/apt/sources.list.d/armbian-config.sources` | GitHub Armbian config packages                                                          |
| Docker                  | `/etc/apt/sources.list.d/docker.list`            | `deb [arch=arm64] https://download.docker.com/linux/debian trixie stable`               |
| Gerbera                 | `/etc/apt/sources.list.d/gerbera.list`           | `deb [signed-by=...] https://pkg.gerbera.io/debian/ trixie main`                        |

### Local (non-repository) Packages

| Package                | Version          | Notes                          |
| ---------------------- | ---------------- | ------------------------------ |
| `cockpit-file-sharing` | 3.3.4-1focal     | From Ubuntu focal .deb         |
| `cpufrequtils`         | 008-2            | Local build                    |
| `emby-server`          | 4.9.0.42         | Local .deb, arm64              |
| `libfuse2`             | 2.9.9-6+b1       | From Debian 12 (bullseye)      |
| `libperl5.36`          | 5.36.0-7+deb12u3 | From Debian 12                 |
| `perl-modules-5.36`    | 5.36.0-7+deb12u3 | From Debian 12                 |
| `unison-2.52`          | 2.52.1-1         | File synchronizer              |
| Various lib\* packages | —                | Mixed bullseye/trixie versions |

### User Desktop/Tool Configuration

| User         | Shell                            | Additional Tools                                                |
| ------------ | -------------------------------- | --------------------------------------------------------------- |
| `getreu`     | bash (default), zsh (configured) | oh-my-zsh, Rust toolchain (cargo, rustup), .cargo, .rustup dirs |
| `jens`       | bash (default), zsh (configured) | oh-my-zsh                                                       |
| `getreu-dev` | bash (default), zsh (configured) | oh-my-zsh                                                       |

### Misc Notes

- **`/etc/sudoers.d/README`** exists but is empty (no custom sudo rules)
- **`/etc/default/chrony`** — not examined (likely default)
- **`/etc/sysfs.conf`** — exists but empty
- **`/etc/default/haveged`** — `DAEMON_ARGS=""` (default)
- **`/etc/exports`** — empty (NFS server but no shares exported)
- **`/etc/docker/daemon.json`** — empty/missing
- **`/etc/NetworkManager/system-connections/`** — contains `netplan-all-eth-interfaces.nmconnection` and `Ethernet connection 1.nmconnection`
- **Total installed packages:** ~924
- **Debian base:** trixie (testing/stable transition)

## Final System Audit (Last Access 2026-05-16)

### SSH Host Keys (for fingerprint verification on new system)

| Key Type    | Fingerprint                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Ed25519** | `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBcTpSzBiowLnRNbrPfJ6MF3mio2UQN1stZyM5j7+QB3 root@odroidhc4`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| **RSA**     | `ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCnj6fULDDchLZ/unEzPkxdSbn180uwnVSsc+iCpfcYAj5GdGJSgvArXVHLTCkk+MLley1+y4IVol3E9hGbydaDzbaDaRCbjx2CsJ7TzSmsf2EjkmBTj5g4Hl8y3cKjmNqXyeBP2HGoYRA2DrcwR3xQFiLEHEkwvLPu5RIpXgNb+aV/WMhByp54ejl/ohTpzVPkd1drB1vhOnLenSTKbtlVADcOrZP0n4Wir0vn8KvotatEolFEH+XUNmYbUoFlSKvDdpjixmTiEElnJAhtXv8A+SqoqFeg7R4qEPWTLjLz85eaRWvvbvTGMulNKK4m0BSSCiqPrt8mw3w6wx5250Oalyyiurb3+dQigpcjmqx8U6TtcK/zKiLPG2hpb8gFI0if+5MidpEhPRnmOMbwtHXdYOSR5Trneyyvt4Zf3TLJd/O1zw125r/rIITQ2VCb9jwF2pPpCBCZtLhXUap3BSgzJpI24peSR43oKbpptK2wvGyeTPF3xMrsEcwXzz1iKec= root@odroidhc4` |
| **ECDSA**   | `ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBFbj5CYEQNLgFySRIlousN8j4fiNQZuvmoUDsoeIo4WqWnQRCJVq6ywrK1a0mydsKI6xAVNkDqg0RfPyxFJyXZY= root@odroidhc4`                                                                                                                                                                                                                                                                                                                                                                                                         |

Identity hostname: `odroidhc4` (system hostname: `bucketnas2`)

### Custom udev Rules (`/etc/udev/rules.d/`)

| File                                    | Purpose                                                                                                                           |
| --------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `10-wifi-disable-powermanagement.rules` | Disables WiFi power save for `wlan*` devices                                                                                      |
| `50-usb-realtek-net.rules`              | Sets `bConfigurationValue=1` for Realtek USB ethernet adapters (Realtek, Samsung, Lenovo, TP-LINK, Nvidia, LINKSYS)               |
| `90-chromium-video.rules`               | Symlinks (`/dev/video-dec*`, `/dev/video-enc*`, `/dev/media-dec*`) for V4L2 decoders on various SoCs (qcom-venus, hantro, rkvdec) |

### Avahi / DNS-SD Published Services

| Service          | Port | Purpose        |
| ---------------- | ---- | -------------- |
| `_ssh._tcp`      | 22   | SSH discovery  |
| `_sftp-ssh._tcp` | 22   | SFTP discovery |

### Network Interface Details

| Property        | Value               |
| --------------- | ------------------- |
| Interface       | `end0`              |
| Speed           | 1000 Mbps           |
| State           | up                  |
| MTU             | 1500                |
| MAC             | `00:1e:06:49:19:82` |
| IPv4 forwarding | disabled            |
| IPv6 forwarding | disabled            |

### Disk Temperatures (hwmon / SoC thermal)

| Sensor      | Temperature |
| ----------- | ----------- |
| cpu_thermal | 46.8 °C     |
| ddr_thermal | 47.3 °C     |

No dedicated HDD temperature sensors detected.

### Encrypted Data Volume Contents

**Mount point:** `/srv/dev-disk-by-uuid-1d65e612-b548-4f91-b089-1ad4260ed796/`

| Path           | Contents                                                                                                |
| -------------- | ------------------------------------------------------------------------------------------------------- |
| `SYNCROOT/`    | Unison sync roots mirror of `/root/.unison/`                                                            |
| `video-audio/` | Media library: `Anleitungen`, `Doku`, `Filme`, `Fotos`, `Hörspiele`, `Kinder`, `Musik`, `Raw`, `Serien` |
| `images/`      | Emulator ROMs: `emulator-roms`, `SuperMario`, `Win10`                                                   |
| `nohup.out`    | Script output — shows broken Unison symlinks (deleted targets)                                          |

### Custom Binary: `tpnote`

| Property       | Value                                                   |
| -------------- | ------------------------------------------------------- |
| **Path**       | `/usr/local/bin/tpnote`                                 |
| **Size**       | 165 MB                                                  |
| **Format**     | ELF 64-bit LSB, ARM aarch64, dynamically linked         |
| **Purpose**    | Note-taking app from `blog.getreu.net/projects/tp-note` |
| **NixOS note** | Not in nixpkgs — requires custom derivation             |

### Libvirt / QEMU Status

| Property                     | Value                               |
| ---------------------------- | ----------------------------------- |
| **VMs configured**           | 0                                   |
| **Default network**          | Defined (empty, not used)           |
| **Networks**                 | Only `default` — no custom networks |
| **`libvirt-guests.service`** | Enabled but no running guests       |

### Cockpit Configuration

| Directory          | Purpose                      |
| ------------------ | ---------------------------- |
| `disallowed-users` | Users denied Cockpit access  |
| `machines.d/`      | QEMU/KVM machine integration |
| `ws-certs.d/`      | WebSocket TLS certificates   |

### Exim4 (Mail Server)

- Split configuration under `/etc/exim4/conf.d/`
- Uses `/etc/exim4/passwd.client` for authentication
- Service enabled but no obvious active mail queue

### OpenVPN

- `client/` and `server/` directories exist but are **empty**
- `update-resolv-conf` script present (for updating resolv.conf from VPN DHCP options)
- No active VPN connections

### Docker

- Group `docker` exists but has **no members**
- **No containers running**, no images
- No `daemon.json` — using defaults
- Installed but unused

### vnStat Network Statistics

| Period           | RX         | TX        | Total     | Avg Rate      |
| ---------------- | ---------- | --------- | --------- | ------------- |
| Since 2023-12-02 | 392.44 GiB | 3.12 TiB  | 3.50 TiB  | 181.67 kbit/s |
| 2026-04          | 23.94 GiB  | 30.88 GiB | 54.82 GiB | —             |

Database: SQLite 3.46.1, updated every minute

### Sysstat History

- Historical SAR data at `/var/log/sysstat/`
- Data from at least `sar22` through `sar31` (daily collection was running despite `ENABLED="false"` in `/etc/default/sysstat`)

### Minidlna Configuration

```
media_dir=/var/lib/minidlna
port=8200
album_art_names=Cover.jpg/cover.jpg/AlbumArtSmall.jpg/albumartsmall.jpg
album_art_names=AlbumArt.jpg/albumart.jpg/Album.jpg/album.jpg
album_art_names=Folder.jpg/folder.jpg/Thumb.jpg/thumb.jpg
```

`/var/lib/minidlna/` — empty directory, no media indexed

### Summary: Nothing Critical Missing

The migration documentation is **comprehensive**. The remaining items are:

1. **SSH host key fingerprints** — save for remote host verification on the new system
2. **`tpnote` binary** — custom ARM64 build, needs a separate Nix derivation
3. **`video-audio/` and `images/` directories** — migrate as encrypted data
4. **Libvirt has no VMs** — just the default empty network definition
5. **OpenVPN configs are empty** — no active VPN connections
6. **Docker is idle** — installed but unused, no containers or images
7. **udev rules** — WiFi power save and Realtek NIC config; the V4L2 decoder rules are for other SoCs and can likely be ignored on the new system
8. **Avahi publishes SSH/SFTP** — can be re-declared declaratively in NixOS
9. **Network at 1 Gbps** — confirmed wired connection speed

## RAID & Storage Lifecycle Management

### Manual RAID Assembly Scripts (`/root/bin/`)

The RAID1+LUKS stack is managed by **two complementary shell scripts**, not systemd services. This is a **manual/session-based model** — the array is never assembled at boot.

#### `start-disks` (1002 B, root:root)

Manually initiated unlock script, typically invoked remotely via SSH tunnel from a work machine:

```sh
#!/bin/sh
### OPEN DISKS ###
RAIDDISK1=/dev/sda
RAIDDISK2=/dev/sdb

open_disks() {
    echo "UNLOCK AND MOUNT ENCRYPTED DISK"
    hdparm -S 244 $RAIDDISK1    # Set APM: max performance, disable spin-down
    hdparm -S 244 $RAIDDISK2
    echo "*** Assemble Raid 1"
    mdadm -A /dev/md1 ${RAIDDISK1}1 ${RAIDDISK2}1
    mdadm --detail --scan
    MD_DISK="$(ls /dev/md*|head -n 1)"
    echo "*** Unlock: $MD_DISK"
    cryptsetup open --type luks "$MD_DISK" md1-crypt   # prompts for passphrase
    umount /dev/mapper/md1-crypt
    mount -t ext4 -o rw,noexec,relatime /dev/mapper/md1-crypt /srv/.../
    service nfs-kernel-server restart    # commented out: minidlna, smbd, nmbd
}

open_disks
sleep 135m        # Auto-shutdown after 2h15m
/root/bin/stop-disks
```

#### `stop-disks` (661 B, getreu:getreu)

```sh
#!/bin/sh
close_disks() {
    service nfs-kernel-server stop   # commented out: smbd, nmbd
    MAPPER_MD_DISK="$(ls /dev/mapper/md*|head -n 1)"
    umount --detach-loop --lazy --force $MAPPER_MD_DISK
    cryptsetup close /dev/md1-crypt
}
close_disks
```

#### Remote unlock pattern (from `SYNCROOT-dev/bucketnas-unlock`)

```sh
#!/bin/sh
BUCKETNAS='bucketnas2.lan'
ssh -l root "$BUCKETNAS" pkill --signal 9 -f "start-disks"
echo hosPF7RilGJ | ssh -l root "$BUCKETNAS" nohup /root/bin/start-disks &
```

### Operational Characteristics

| Aspect                    | Value                                                            |
| ------------------------- | ---------------------------------------------------------------- |
| **Assembly model**        | Manual (no boot-time automatic assembly)                         |
| **LUKS cipher**           | AES-XTS-plain64, 512-bit key                                     |
| **Passphrase entry**      | Interactive (tty prompt on `cryptsetup open`)                    |
| **Session duration**      | 135 minutes, then auto-shutdown via `stop-disks`                 |
| **RAID at boot**          | Not assembled (arrays stay down until manually started)          |
| **Services when mounted** | NFS only (minidlna/emby/smbd commented out)                      |
| **Post-shutdown state**   | LUKS closed, array stays assembled (`mdadm -S` is commented out) |

### Concerns

1. **Not automatic**: No recovery on reboot; data is inaccessible until a manual unlock
2. **Stop-disks ownership**: Owned by `getreu` (UID 1000) but closes root-owned LUKS/RAID devices — works via sudo group but is a security concern
3. **Aggressive unmount**: `--detach-loop --force` can orphan open file handles from NFS/media clients
4. **Hardcoded session timeout**: 135-minute sleep is very specific to current operational habits
5. **Incomplete service management**: NFS only; MiniDLNA and Emby are commented out (Emby service itself is disabled)

## Backup & Synchronization Ecosystem

### BorgBackup

**Package**: `borgbackup2` (Debian trixie), version 2.0.0b19

**Backup script**: `/root/.unison/SYNCROOT-dev/backup`

**Sources** (selected, files < 4 GB):

- `/home/jens/Documents`
- `/home/getreu/JENS_DATEN/DOKUMENTE`
- `/home/getreu/BILDER`
- `/home/getreu-dev/projects`
- `/home/getreu-dev/mykeys`

**Excluded** by pattern: `~`, `$`, `.bak`, `.db`, `.tmp`, `target/`, `_downloads/`

**Retention policy**: 7 daily, 4 weekly, 6 monthly archives

**Workflow**: `backup` → `backup-init` (new repo) → `backup-mount`/`backup-mount1` (mount array) → `backup-list` → `backup-break-lock` (force-release) → `backup-repair` (repair repo)

### Unison File Synchronization

**Three sync roots** under `/root/.unison/SYNCROOT-{dev,personal,vault,work}/`:

| Sync Root           | Owner        | Contents                                                                                                    |
| ------------------- | ------------ | ----------------------------------------------------------------------------------------------------------- |
| `SYNCROOT-dev`      | `getreu-dev` | Dev projects, scripts (7zip, backup, lsync, SSH tunnels, etc.)                                              |
| `SYNCROOT-personal` | `getreu`     | `BILDER` (241 entries), `BÜCHER`, `Desktop`, `Documents`, `JENS_DATEN`, `movie`, `mp3`, `.cargo`, `.rustup` |
| `SYNCROOT-vault`    | `getreu-dev` | GPG-encrypted passwords, Jami keys, KeePass2xc data, **git repo**                                           |
| `SYNCROOT-work`     | `jens`       | `OneDrive`, `Documents`, `Music`, recent NixOS/work backup archives                                         |

**Key scripts**:
| Script | Purpose |
|---|---|
| `lsync` | Inotify-based rsync for live file sync |
| `bucketnas-unlock` | Remote SSH unlock of NAS |
| `bucketnas-lock` | Lock/disconnect |
| `bucketnas-restart-media-server` | Remote Emby restart |
| `connect-sshtunnel-*` | SSH tunnel setups for remote access |
| `backup-source`/`backup-source1` | Borg backup path definitions |

**Symlinks** (pointing to project content):

- `devtpnote` → `/home/getreu-dev/projects/WEB-SERVER-CONTENT/blog.getreu.net/projects/tp-note`
- `totem-keyboard` → `/home/getreu-dev/projects/WEB-SERVER-CONTENT/blog.getreu.net/projects/totem-keyboard`

## NixOS Migration Recommendations

### 1. RAID Assembly Strategy

The current manual model is fragile. Consider one of two approaches:

**Option A — Automatic at boot** (recommended for a NAS):

- Declarative `mdadm` array with `boot.deviceMetadata = true`
- `cryptDevices.md1-crypt` with `allowDiscards = true`
- `fileSystems."/srv/..."` with proper dependencies
- **Challenge**: Interactive LUKS passphrase must be replaced with a key file

**Option B — Keep manual model**:

- Convert `start-disks`/`stop-disks` to proper NixOS **systemd services**
- Use `systemd.timers` for the 135-minute session timeout
- Move `stop-disks` ownership to root:root

### 2. LUKS Passphrase Management

The current interactive prompt won't work for boot-time assembly. Options:

- **Key file**: Store on encrypted eMMC partition, referenced via `keyFile`
- **systemd-creds**: Use `nixos-generate-credentials` for sealed keys
- **Keep interactive**: If manual assembly is retained, no change needed

### 3. Service Conversions

Convert these custom components to NixOS declarative equivalents:

| Armbian Component            | NixOS Equivalent                                                   |
| ---------------------------- | ------------------------------------------------------------------ |
| `hc4-fan-control.sh` + timer | `systemd.services` + `systemd.timers` (or kernel `thermal` config) |
| `odroid-hc4-pwm-setup.sh`    | One-shot service in `systemd.services`                             |
| `fan-trip-points.sh`         | One-shot service updating `thermal_zone` trip points               |
| `hd-idle.service`            | `services.hd-idle` (NixOS module) or systemd service               |
| `cpufrequtils` (ondemand)    | `powerManagement.cpuFreqGovernor = "ondemand"`                     |
| `armbian-zram-config`        | `swap.devices` with `zramSwap`                                     |
| `log2ram` (zram → /var/log)  | Custom tmpfs on `/var/log` or `systemd.tmpfs`                      |
| `haveged`                    | `services.haveged.enable`                                          |
| `lm-sensors`                 | `services.sensors.enable`                                          |

### 4. Media Server Configuration

| Server   | Status                       | Notes for Migration                                            |
| -------- | ---------------------------- | -------------------------------------------------------------- |
| MiniDLNA | Enabled, port 8200           | `services.minidlna` module available                           |
| Emby     | Disabled, local deb 4.9.0.42 | Consider `services.emby-server` from nixpkgs or keep local deb |
| Gerbera  | Enabled, external repo       | `services.gerbera` module available                            |

### 5. Container & Virtualization

| Component    | NixOS Module                                    |
| ------------ | ----------------------------------------------- |
| containerd   | `virtualisation.containerd`                     |
| Docker       | `virtualisation.docker` (or containerd runtime) |
| libvirt/QEMU | `virtualisation.libvirt.enable`                 |

### 6. Backup & Sync on NixOS

- **BorgBackup**: Use `services.borgbackup` module for automated schedules
- **Unison**: Keep as-is (user-owned sync roots in `/root/.unison/`) — no NixOS integration needed
- **lsync**: Consider `services.lsyncd` module or keep custom `lsync` script

### 7. User Accounts & SSH

- Replicate all 15 root authorized_keys (8 machines)
- Replicate `getreu`'s RSA key pair
- Copy Unison sync roots, Borg configs, and personal data to new system
- Sudo group membership for `getreu` is default in NixOS

### 8. Additional Notes

- **`/etc/modprobe.d/blacklist-odroidhc4.conf`** (simpledrm) — may not be needed on NixOS (different kernel)
- **WiFi module options** (`8189fs`, `r8723bs`) — if dongles are present, add to NixOS kernel modules
- **NetworkManager** → NixOS `networking.networkmanager` module handles DHCP/IPv6 similarly
- **Chrony**, **Avahi**, **Exim4**, **OpenVPN** — all have NixOS modules
- **Total packages to replace**: ~924 → many can be expressed declaratively via `environment.systemPackages`
