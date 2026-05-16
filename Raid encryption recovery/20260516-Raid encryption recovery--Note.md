---
title: Raid encryption recovery
subtitle: Note
author: Jgetreu
date: 2026-05-16
lang: en-US
---

# RAID Encryption Recovery Data for bucketnas2

> Hardkernel ODROID HC4 | aarch64 | Amlogic Meson SM1 | Debian trixie
>
> **This file contains all identifiers, parameters, and commands needed to decrypt the RAID1+LUKS stack on new hardware.**

---

## 1. LUKS Decryption Parameters

### Container Identity

| Property            | Value                                                        |
| ------------------- | ------------------------------------------------------------ |
| **Device**          | `/dev/md1` (Linux RAID1 member)                              |
| **LUKS UUID**       | `0a8c7656-cfbd-4e78-be66-211c449e317c`                       |
| **LUKS version**    | LUKS2                                                        |
| **Cipher**          | `aes-xts-plain64`                                            |
| **Key size**        | 512 bits                                                     |
| **Sector offset**   | 32768 (64 MiB from start of `/dev/md1`)                      |
| **Sector size**     | 512 bytes                                                    |
| **Container size**  | 5 860 028 416 sectors (~2.73 TB)                             |
| **Mapper name**     | `md1-crypt`                                                  |
| **Mapper device**   | `/dev/mapper/md1-crypt`                                      |
| **Filesystem UUID** | `1d65e612-b548-4f91-b089-1ad4260ed796`                       |
| **Filesystem**      | ext4                                                         |
| **Mount point**     | `/srv/dev-disk-by-uuid-1d65e612-b548-4f91-b089-1ad4260ed796` |
| **Mount options**   | `rw,noexec,relatime`                                         |

### Passphrase

- The passphrase is entered **interactively** at the `cryptsetup open` prompt.
- The remote unlock script contains a string `hosPF7RilGJ` — verify whether this is the LUKS passphrase or an SSH passphrase.
- **Action required**: Confirm the correct LUKS passphrase and record it securely here:

  ```
  LUKS PASSPHRASE: ________________________________
  ```

---

## 2. RAID1 Array Parameters

### Array Identity

| Property         | Value                                                |
| ---------------- | ---------------------------------------------------- |
| **Array name**   | `bucketnas2:1`                                       |
| **RAID UUID**    | `492308d1-bdbf-f268-81e4-6a60c9f08e98`               |
| **MD UUID**      | `492308d1:bdbf-f268-81e4-6a60c9f08e98` (scan format) |
| **Level**        | RAID1                                                |
| **Metadata**     | 1.2                                                  |
| **Devices**      | 2                                                    |
| **State**        | `[2/2] [UU]` (both members active)                   |
| **Total blocks** | 2 930 030 592                                        |
| **Chunk size**   | 64 KB                                                |

### Member Partitions

| Device      | Model                | Serial            | Label          | Start sector | Size (sectors) | Type (fdisk)      |
| ----------- | -------------------- | ----------------- | -------------- | ------------ | -------------- | ----------------- |
| `/dev/sda1` | WDC WD30EZRZ-00WN9B0 | `WD-WCC4E5LNAKEL` | `bucketnas2:1` | 2048         | 2 930 030 592  | fd00 (Linux RAID) |
| `/dev/sdb1` | ST3000DM001-1CH166   | `Z1F4KAF0`        | `bucketnas2:1` | 2048         | 2 930 030 592  | fd00 (Linux RAID) |

### mdadm Assembly Line

```
ARRAY /dev/md1 metadata=1.2 name=bucketnas2:1 UUID=492308d1:bdbff268:81e46a60:c9f08e98
```

---

## 3. Step-by-Step Decryption Procedure (for use on new hardware)

### Step 1: Install required tools

```bash
# Debian / Ubuntu / NixOS (with unstable channel)
apt install mdadm cryptsetup e2fsprogs

# NixOS
nix-shell -p mdadm cryptsetup e2fsprogs
```

### Step 2: Load kernel modules

```bash
modprobe dm-crypt
modprobe raid1
modprobe md-mod
```

### Step 3: Detect and assemble the RAID array

```bash
# Scan for existing RAID metadata
mdadm --assemble --scan

# Or explicitly assemble with known members
mdadm -A /dev/md1 /dev/sda1 /dev/sdb1

# Verify assembly
mdadm --detail /dev/md1
# Expected: [2/2] [UU]
```

### Step 4: Open the LUKS container

```bash
# This will prompt for the LUKS passphrase
cryptsetup open --type luks /dev/md1 md1-crypt

# Verify it opened
cryptsetup status md1-crypt
# Expected output:
#   type:    LUKS2
#   cipher:  aes-xts-plain64
#   keysize: 512 bits
#   device:  /dev/md1
```

### Step 5: Mount the filesystem

```bash
# The mount point path includes the filesystem UUID
mkdir -p /srv/dev-disk-by-uuid-1d65e612-b548-4f91-b089-1ad4260ed796

mount -t ext4 -o rw,noexec,relatime /dev/mapper/md1-crypt \
    /srv/dev-disk-by-uuid-1d65e612-b548-4f91-b089-1ad4260ed796/

# Verify mount
df -h
```

---

## 4. LUKS Keyslot & Crypto Parameters (from `cryptsetup luksDump /dev/md1`)

**Recorded:** 2026-05-16 from live system

### Header

| Property          | Value                                                |
| ----------------- | ---------------------------------------------------- |
| **Version**       | LUKS2                                                |
| **Epoch**         | 3                                                    |
| **Metadata area** | 16 384 bytes                                         |
| **Keyslots area** | 16 744 448 bytes                                     |
| **UUID**          | `0a8c7656-cfbd-4e78-be66-211c449e317c`               |
| **Label**         | (none)                                               |
| **Data segment**  | `0: crypt` at offset 16 777 216 bytes (whole device) |

### Active Keyslot — Slot 0 (only slot)

| Property         | Value                                                                                             |
| ---------------- | ------------------------------------------------------------------------------------------------- |
| **Keyslot type** | luks2                                                                                             |
| **Key size**     | 512 bits                                                                                          |
| **Cipher**       | `aes-xts-plain64`                                                                                 |
| **PBKDF**        | `argon2i`                                                                                         |
| **Time cost**    | 4                                                                                                 |
| **Memory**       | 455 452 KiB (~445 MiB)                                                                            |
| **Threads**      | 4                                                                                                 |
| **AF stripes**   | 4000                                                                                              |
| **AF hash**      | sha256                                                                                            |
| **Area offset**  | 32 768 bytes                                                                                      |
| **Area length**  | 258 048 bytes                                                                                     |
| **Digest ID**    | 0                                                                                                 |
| **Salt (PBKDF)** | `22 ae a4 ea d7 3a e5 df 93 40 93 fc 80 48 a0 2f 86 2f eb 92 54 02 90 50 d3 44 6e 15 3e dc 10 57` |

### Digest — Slot 0 (pbkdf2)

| Property       | Value                                                                                             |
| -------------- | ------------------------------------------------------------------------------------------------- |
| **Hash**       | sha256                                                                                            |
| **Iterations** | 54 795                                                                                            |
| **Salt**       | `47 4f 7e 35 0d 07 aa be 0b 17 92 7d 01 06 04 84 d7 76 31 0f a7 e4 be f1 1b 35 3f 44 e9 dd d4 7d` |
| **Digest**     | `06 d1 18 96 46 8c d1 9e 1a 36 ac b5 eb 59 07 02 81 bf b8 9f 9a 5c ed 61 79 2a 6a 6d 88 6f 59 1c` |

### Keyslot Summary

```
Keyslots:
  0: luks2  ← ONLY active keyslot
     PBKDF: argon2i, time=4, mem=455452 KiB, threads=4
     (no other keyslots defined)
Tokens:
  (none)
Digests:
  0: pbkdf2  (sha256, iterations=54795)
```

### Recovery Notes

- **Only one keyslot (0) exists.** If this passphrase is lost, the data is unrecoverable unless a header backup was made.
- **PBKDF is argon2i** — very expensive to brute-force (455 MiB memory, 4 threads, 4 iterations).
- **No key files** exist on disk anywhere. The passphrase is the sole recovery vector.
- **Passphrase candidate:** the string `hosPF7RilGJ` found in `/root/bin/start-disks` and `SYNCROOT-dev/bucketnas-unlock` — this is piped via `echo` to SSH, but **must be verified** as the LUKS passphrase. It may instead be an SSH key passphrase or a different secret.

```
LUKS PASSPHRASE: hosPF7RilGJ   ← CANDIDATE (UNVERIFIED — test on /dev/md1 before relying on this)
```

### Verify Passphrase (from recovery media)

```bash
# Test passphrase without creating a device mapper entry
cryptsetup luksTestKey /dev/md1
# or:
cryptsetup open --test-passphrase /dev/md1
#   (prompts for passphrase — enter hosPF7RilGJ)
```

### Header Backup — CREATED 2026-05-16

| Property    | Value                                                                                        |
| ----------- | -------------------------------------------------------------------------------------------- |
| **File**    | `/root/luks-header-md1-backup.img`                                                           |
| **Size**    | 16 MiB                                                                                       |
| **SHA256**  | `bd25b04cb09823cfc52756f298c6b262dda014d55bc8e4bc2743876113153d4a`                           |
| **Created** | 2026-05-16 17:56                                                                             |
| **Perms**   | `-r--------` (root-only)                                                                     |
| **Command** | `cryptsetup luksHeaderBackup /dev/md1 --header-backup-file /root/luks-header-md1-backup.img` |

**Local copy** (same directory as this document):

| Property   | Value                                                              |
| ---------- | ------------------------------------------------------------------ |
| **File**   | `luks-header-md1-backup.img`                                       |
| **SHA256** | `bd25b04cb09823cfc52756f298c6b262dda014d55bc8e4bc2743876113153d4a` |
| **Copied** | 2026-05-16 17:57                                                   |

> **ACTION REQUIRED:** The local copy in this directory is safe to keep. Also copy to a secure off-device location (USB stick, external drive). If the header on `/dev/md1` is corrupted, this file is the only way to restore access.

### Restore Header (if lost)

```bash
# Use the backup created 2026-05-16:
# /root/luks-header-md1-backup.img
# SHA256: bd25b04cb09823cfc52756f298c6b262dda014d55bc8e4bc2743876113153d4a

# Use the local copy (same directory as this document):
cryptsetup luksHeaderRestore /dev/md1 --header-backup-file luks-header-md1-backup.img

# Or use the on-device copy:
cryptsetup luksHeaderRestore /dev/md1 --header-backup-file /root/luks-header-md1-backup.img
```

---

## 5. All Identifiers Quick Reference

```
LUKS UUID:         0a8c7656-cfbd-4e78-be66-211c449e317c
RAID UUID:         492308d1-bdbf-f268-81e4-6a60c9f08e98
mdadm scan UUID:   492308d1:bdbf-f268-81e4-6a60c9f08e98
FS  UUID:          1d65e612-b548-4f91-b089-1ad4260ed796
Mapper:            md1-crypt
Device path:       /dev/mapper/md1-crypt
Mount:             /srv/dev-disk-by-uuid-1d65e612-b548-4f91-b089-1ad4260ed796
SATA serial sda:   WD-WCC4E5LNAKEL
SATA serial sdb:   Z1F4KAF0
Cipher:            aes-xts-plain64
Key:               512 bits
PBKDF:             argon2i (slot 0, mem=455452 KiB, time=4, threads=4)
Keyslot count:     1 (slot 0 only)
Metadata:          RAID1, md 1.2
```
