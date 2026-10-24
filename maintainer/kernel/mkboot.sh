#!/bin/bash
# Pack a kernel Image into a full-size boot_b image: the 2026-10-23 boot_b backup (TWRP ramdisk, header v3) with
# only the kernel swapped, optionally with extra kernel cmdline in the boot header (e.g. "pipa_hooks=3").
#   bash maintainer/kernel/mkboot.sh <Image> <out.img> ["cmdline"]      (TRIM=1: test-boot image, see below)
set -euo pipefail
K=${K:-$HOME/Documents/pipa/port-work/kernel}
BK=${BK:-$HOME/Documents/pipa/COS17/kernel/backup-partitions-20261023}
MB=$K/bootimg/magiskboot
[ $# -ge 2 ] && [ -f "$1" ] || { sed -n 2,4p "$0"; exit 1; }
img=$(realpath "$1"); out=$(realpath -m "$2"); cmd=${3:-}
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
cd "$w"
"$MB" unpack -h "$BK/boot_b.img" >/dev/null 2>&1
cp "$img" kernel
[ -n "$cmd" ] && sed -i "s|^cmdline=.*|cmdline=$cmd|" header
"$MB" repack "$BK/boot_b.img" "$out" >/dev/null 2>&1
# magiskboot -h mangles os_version/os_patch_level (2099-12 -> 17.126.9/2099-00); a wrong patch level makes the
# bootloader stop before the kernel prints anything (black screen, no log). Always keep the original 4 bytes.
dd if="$BK/boot_b.img" of="$out" bs=1 skip=16 seek=16 count=4 conv=notrunc status=none
cmp -s <(head -c 20 "$BK/boot_b.img" | tail -c 4) <(head -c 20 "$out" | tail -c 4) || { echo "os_version mismatch" >&2; exit 1; }
# TRIM=1: keep only header + kernel + ramdisk (v3, 4 KiB pages) for `fastboot boot`; the full 196 MB image hangs it
if [ "${TRIM:-0}" = 1 ]; then
	r4k() { echo $(( ($1 + 4095) / 4096 * 4096 )); }
	ks=$(od -An -tu4 -j8 -N4 "$out" | tr -d ' '); rs=$(od -An -tu4 -j12 -N4 "$out" | tr -d ' ')
	truncate -s $(( 4096 + $(r4k "$ks") + $(r4k "$rs") )) "$out"
fi
grep '^cmdline=' header
echo "md5 $(md5sum < "$out" | cut -c1-32)  $(stat -c %s "$out") bytes  $out"
