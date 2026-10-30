#!/bin/bash
# Kernel test/flash/rollback for the tablet (slot B). Only boot_b changes: our kernel keeps the device's
# vendor_boot (dtb) and dtbo, exactly as in the test boots.
#
#   bash maintainer/kernel/flash_kernel.sh test <boot.img>     fastboot boot, nothing written (a reboot = old kernel)
#   bash maintainer/kernel/flash_kernel.sh flash <boot.img>    write boot_b, then reboot
#   bash maintainer/kernel/flash_kernel.sh restore             write the 2026-10-23 backups of boot_b, vendor_boot_b, dtbo_b
#
# The tablet may be in Android (adb) or already in fastboot. Ask the user before "flash" or "restore".
set -euo pipefail
SERIAL=${SERIAL:-83836a90}
BK=${BK:-$(cd "$(dirname "$0")/../.." && pwd)/kernel/backup-partitions-20261023}
FB="timeout 180 fastboot -s $SERIAL"
BOOT_SIZE=201326592

die() { echo "error: $*" >&2; exit 1; }

to_fastboot() {
	if timeout 5 fastboot devices | grep -q "^$SERIAL"; then return; fi
	adb -s "$SERIAL" get-state >/dev/null 2>&1 || die "tablet not found in adb or fastboot"
	adb -s "$SERIAL" reboot bootloader
	for _ in $(seq 1 30); do timeout 5 fastboot devices | grep -q "^$SERIAL" && break; sleep 2; done
	timeout 15 fastboot -s "$SERIAL" getvar current-slot 2>&1 | grep -q 'current-slot: b' ||
		die "bootloader not answering or slot is not b"
}

check_img() {
	[ -f "$1" ] || die "no such file: $1"
	[ "$(head -c 8 "$1")" = "ANDROID!" ] || die "$1 is not an Android boot image"
	[ "$(stat -c %s "$1")" -le $BOOT_SIZE ] || die "$1 is larger than boot_b"
}

# test boots: use a trimmed image (mkboot.sh TRIM=1; used for r7kb, r7ov, r8 since 2026-10-28). A full 196 MB image
# hung the bootloader two times, and a 92 MB KPM trim image also hung it (57 MB worked); a long power press restarts it

case "${1:-}" in
test)
	check_img "${2:-}"
	to_fastboot
	$FB boot "$2"
	echo "test boot started; it ends with the next reboot" ;;
flash)
	check_img "${2:-}"
	echo "md5 $(md5sum < "$2" | cut -c1-32)  $2"
	to_fastboot
	$FB flash boot_b "$2"
	$FB reboot ;;
restore)
	for p in boot_b vendor_boot_b dtbo_b; do [ -f "$BK/$p.img" ] || die "missing $BK/$p.img"; done
	(cd "$BK" && md5sum boot_b.img vendor_boot_b.img dtbo_b.img)
	to_fastboot
	for p in boot_b vendor_boot_b dtbo_b; do $FB flash "$p" "$BK/$p.img"; done
	$FB reboot ;;
*)
	sed -n 2,10p "$0"; exit 1 ;;
esac
