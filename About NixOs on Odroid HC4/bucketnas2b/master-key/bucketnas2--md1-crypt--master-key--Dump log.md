---
title:      "bucketnas2--md1-crypt--master-key"
subtitle:   "Dump log"
author:     "Getreu"
date:       "2023-05-11"
lang:       "en-US"
---

[bucketnas2--md1-crypt--master-key](<bucketnas2--md1-crypt--master-key>)



```
cryptsetup luksDump --master-key-file bucketnas2--md1-crypt--master-key --dump-master-key /dev/md1 

WARNING!
========
The header dump with volume key is sensitive information
that allows access to encrypted partition without a passphrase.
This dump should be stored encrypted in a safe place.

Are you sure? (Type 'yes' in capital letters): YES
Enter passphrase for /dev/md1: 
LUKS header information for /dev/md1
Cipher name:   	aes
Cipher mode:   	xts-plain64
Payload offset:	32768
UUID:          	0a8c7656-cfbd-4e78-be66-211c449e317c
MK bits:       	512
Key stored to file bucketnas2--md1-crypt--master-key.
```


