#!/bin/bash
cocoonfs -i cocoonfs.img -f write-mkfs-info-header -H sha2 -C aes -t 128 -I 'ddeeff' -s 8M
