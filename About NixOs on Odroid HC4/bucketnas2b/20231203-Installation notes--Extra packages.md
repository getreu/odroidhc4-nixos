---
title:        Installation notes
subtitle:     Extra packages
author:       Getreu
date:         2023-12-03
lang:         de-DE
---


```sh
apt install cryptsetup libblockdev-crypto2 
apt install avahi-daemon libnss-mdns

apt install lm-sensors fancontrol
apt install unison-2.52

apt install cockpit cockpit-machines, cockpit-networkmanager, cockpit-packagekit, cockpit-storaged 
/usr/lib/cockpit/cockpit-certificate-ensure

apt install lvm2
```



The block ids:

```sh
blkid
/dev/sdb1: UUID="492308d1-bdbf-f268-81e4-6a60c9f08e98" UUID_SUB="1b1a8358-cae4-60ee-38a7-3c2daf0e81ea" LABEL="bucketnas2:1" TYPE="linux_raid_member" PARTUUID="0b5f33ec-1422-dd42-b512-bff872fa7d27"
/dev/mmcblk0p1: LABEL="armbi_root" UUID="8d13d9f1-c65d-4bfe-8ecb-8687863fb1c0" BLOCK_SIZE="4096" TYPE="ext4" PARTUUID="c9cf8773-01"
/dev/sdc1: UUID="492308d1-bdbf-f268-81e4-6a60c9f08e98" UUID_SUB="4e2b9296-dfe7-c08a-3742-dbcc02a354e9" LABEL="bucketnas2:1" TYPE="linux_raid_member" PARTUUID="d92296d4-a7ea-d448-afd3-79bdfec4ddba"
/dev/sda1: LABEL="2. Festplatte" BLOCK_SIZE="512" UUID="45EFA09D11DEDD23" TYPE="ntfs" PARTUUID="472c237d-01"
/dev/md1: UUID="0a8c7656-cfbd-4e78-be66-211c449e317c" TYPE="crypto_LUKS"
/dev/zram1: LABEL="log2ram" UUID="e74cd8be-9f85-476a-aa12-1510968f1628" BLOCK_SIZE="4096" TYPE="ext4"
/dev/mapper/md1-crypt: UUID="1d65e612-b548-4f91-b089-1ad4260ed796" BLOCK_SIZE="4096" TYPE="ext4"
/dev/zram0: UUID="7f2f73a1-e385-42a4-83e4-df2a6166bc23" TYPE="swap"
```
