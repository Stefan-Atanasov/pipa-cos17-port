#!/bin/sh
# Phase 7t (BUGS-TODO 80, user 2026-11-18): Miracast / Screencast picture = green and red lines.
#
# 6h set vendor.display.vds_allow_hwc=1, but system/build.prop still had debug.sf.enable_hwc_vds=0, so SurfaceFlinger
# composed the WFD virtual display on the GPU (RGBA_8888) and the Qualcomm WFD source (libwfdmmsrc_system) rejected
# every frame ("WFD SMS Pixel Format Mismatch Error Detected"). Live test 2026-11-18 (pt123, prop set at
# post-fs-data, Windows Wireless Display as the sink): 0 mismatches, 904 frames, clean picture; screenrecord still
# fine. Here: debug.sf.enable_hwc_vds 0 -> 1 in system/build.prop (the line stays in place).
set -eu
. "$PORT/lib.sh"
STEP=7t
BP=$T/system/system/build.prop
[ -f "$BP" ] || BP=$T/system/build.prop
[ -f "$BP" ] || die "no system build.prop"
need_grep '^debug.sf.enable_hwc_vds=0$' "$BP"
awk '$0=="debug.sf.enable_hwc_vds=0"{print "debug.sf.enable_hwc_vds=1"; next} {print}' "$BP" > "$R/build.prop.7t"
cat "$R/build.prop.7t" > "$BP"   # same inode: label, owner and mode kept
rm -f "$R/build.prop.7t"
forbid_grep '^debug.sf.enable_hwc_vds=0$' "$BP"
need_grep '^debug.sf.enable_hwc_vds=1$' "$BP"
need_grep '^vendor.display.vds_allow_hwc=1$' "$T/product/etc/build.prop"
echo "edited  system build.prop: debug.sf.enable_hwc_vds=1"
set_layer "$STEP"
