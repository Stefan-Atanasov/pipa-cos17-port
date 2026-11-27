#!/bin/sh
# Step 8w (2026-11-24, BUGS 185): vendor lib64/libgsl.so with the Adreno 650 entry for the DRM path (patch by a dev).
# 5 bytes in ioctl_drm_device_getinfo_ext: the chip case 0x06010800 (Adreno 618) becomes 0x06050002 (Adreno 650,
# pipa) with highest bank bit 16 and UBWC 4.0 (the mainline sm8250 values). Before, chip 0x6050002 logged "Unknown GSL
# device info properties". Only the DRM path (/dev/dri/renderD128, mainline msm GPU driver) uses this code:
# gsl_ioctl_init takes /dev/kgsl-3d0 first, and our 4.19 kernel has KGSL, so today it changes nothing. Kept for a
# mainline kernel. Blob and note: port-work/blobs/gsl-drm-a650/.
#NEEDS: "$P/blobs/gsl-drm-a650/libgsl.so"
set -eu
. "$PORT/lib.sh"
STEP=8w
t=$T/vendor/lib64/libgsl.so
OLD=2a565c16570c78bc298346dcd43ddd35
NEW=7785c0570fd8f7d1b69ef0c310d7b3e2
echo "== 8w vendor/lib64/libgsl.so: Adreno 650 on the DRM path (BUGS 185)"
[ -f "$t" ] || die "missing $t"
[ "$(md5sum < "$t" | cut -d' ' -f1)" = "$OLD" ] || die "$t: unexpected md5 (not the beta4 lib64 libgsl)"
[ "$(md5sum < "$P/blobs/gsl-drm-a650/libgsl.so" | cut -d' ' -f1)" = "$NEW" ] || die "blob: wrong md5"
cat "$P/blobs/gsl-drm-a650/libgsl.so" > "$t"   # same inode: label, owner and mode kept
[ "$(md5sum < "$t" | cut -d' ' -f1)" = "$NEW" ] || die "$t: copy failed"
echo "lib64/libgsl.so -> $NEW"
set_layer "$STEP"
