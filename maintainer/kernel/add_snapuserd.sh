#!/bin/bash
# BUGS 193 (VABC OTA): add a first-stage snapuserd to a boot image's ramdisk (TWRP ramdisk, header v3), kernel unchanged.
# First-stage init (in this ramdisk) starts /system/bin/snapuserd from the ramdisk when it boots from Virtual A/B
# compression snapshots (after an OTA, before the merge). Our ramdisk has none; the donor init_boot has a static arm64
# snapuserd_ramdisk (Android 17, CP2A.260605.016), the same version as the snapuserd of our system that takes over later.
#   bash maintainer/kernel/add_snapuserd.sh <in boot.img> <snapuserd_ramdisk> <out boot.img>
# Same packing rule as mkboot.sh: magiskboot repack, then the original 4 os_version/os_patch_level bytes (16-19) back
# (magiskboot -h mangles them -> black screen).
set -euo pipefail
K=${K:-${PIPA_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}/port-work/kernel}
MB=$K/bootimg/magiskboot
[ $# -eq 3 ] && [ -f "$1" ] && [ -f "$2" ] || { sed -n 2,6p "$0"; exit 1; }
in=$(realpath "$1"); su=$(realpath "$2"); out=$(realpath -m "$3")
file "$su" | grep -q 'ARM aarch64.*statically linked' || { echo "$su is not a static arm64 binary"; exit 1; }
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
cd "$w"
"$MB" unpack -h "$in" >/dev/null 2>&1
[ -f ramdisk.cpio ] || { echo "no ramdisk in $in"; exit 1; }
"$MB" cpio ramdisk.cpio "exists system/bin/snapuserd" 2>/dev/null && { echo "ramdisk already has snapuserd"; exit 1; }
"$MB" cpio ramdisk.cpio "add 0750 system/bin/snapuserd_ramdisk $su" "ln snapuserd_ramdisk system/bin/snapuserd" >/dev/null
"$MB" repack "$in" "$out" >/dev/null 2>&1
dd if="$in" of="$out" bs=1 skip=16 seek=16 count=4 conv=notrunc status=none
cmp -s <(head -c 20 "$in" | tail -c 4) <(head -c 20 "$out" | tail -c 4) || { echo "os_version mismatch" >&2; exit 1; }
echo "md5 $(md5sum < "$out" | cut -c1-32)  $(stat -c %s "$out") bytes  $out"
