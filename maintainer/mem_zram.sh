#!/bin/sh
# Live zram re-setup for RAM A/B tests (BUGS 89/99). A reboot gives back the ROM setup (OPPO init.oplus.nandswap.sh).
#   sh maintainer/mem_zram.sh <size_mb> <algo> [wsf]      e.g. 8192 lz4 1  (pt93 values)  |  5632 zstd 25  (stock OPPO)
# swapoff moves all swapped pages back into RAM first: run it with few apps open (needs free RAM >= zram "Used").
set -eu
ADB=${ADB:-adb -s 83836a90}
SZ=${1:?size_mb}; ALG=${2:?algo}; WSF=${3:-}
$ADB shell "su -c 'set -e; swapoff /dev/block/zram0; echo 1 > /sys/block/zram0/reset;
echo $ALG > /sys/block/zram0/comp_algorithm; echo ${SZ}M > /sys/block/zram0/disksize;
mkswap /dev/block/zram0 >/dev/null; swapon /dev/block/zram0 -p 32758;
[ -n \"$WSF\" ] && echo $WSF > /proc/sys/vm/watermark_scale_factor;
cat /proc/swaps | tail -1; cat /sys/block/zram0/comp_algorithm; echo wsf=\$(cat /proc/sys/vm/watermark_scale_factor)'"
