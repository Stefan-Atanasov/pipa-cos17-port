#!/bin/sh
# 6h (BUGS-TODO 80, tester 2026-11-06): Miracast (Settings > Device connection > TV) shows coloured noise.
#
# Tester log 2026-11-08: "WFD SMS Pixel Format Mismatch Error Detected" for every frame. The check is in
# WFDMMSourceVideoCapture::ScheduleFrame (system_ext lib/libwfdmmsrc_system.so, 0xfd92): it rejects the pixel
# formats 1..4 and 0x2b (RGBA_8888, RGBX_8888, RGB_888, RGB_565, RGBA_1010102). SurfaceFlinger gives RGBA_8888 when
# it composes the virtual display with the GPU. The WFD source wants the YUV buffer that the HWC virtual display
# writes. SurfaceFlinger (QTI extension, strings "Allow HWC for WFD", vendor.display.vds_allow_hwc) uses the HWC
# virtual display for WFD only when vendor.display.vds_allow_hwc=1 (or a first API level below 33). Stock HyperOS
# vendor/build.prop (line 605) and the donor OPD2515 vendor (line 245) set it. The beta4 vendor build.prop lost it
# (display block aligned to AOSPA).
# * product/etc/build.prop: vendor.display.vds_allow_hwc=1 (as stock; debug.sf.enable_hwc_vds stays 0, so other
#   virtual displays, e.g. the screen recorder, stay on the GPU path). Label vendor_display_prop: surfaceflinger can
#   read it; init loads product props with its own context.
# * system_ext/etc/build.prop: ro.pipa.port.layer=6h.
# NOT TESTED when written (2026-11-10, offline; needs a Miracast receiver). Live test without a build:
#   su -c 'resetprop -n vendor.display.vds_allow_hwc 1'; su -c 'setprop ctl.restart surfaceflinger' (the UI restarts)
set -eu
. "$PORT/lib.sh"
STEP=6h

P_NAME=vendor.display.vds_allow_hwc
echo "== 6h HWC virtual display for WFD"
for f in $(find "$T" -maxdepth 4 -name build.prop -type f); do
    forbid_grep "^$P_NAME=" "$f"
done
BP=$T/product/etc/build.prop
[ -f "$BP" ] || die "no $BP"
{ cat "$BP"; printf '%s\n' "# pipa port 6h (BUGS-TODO 80): Miracast needs the HWC virtual display (YUV), as stock HyperOS" \
    "$P_NAME=1"; } > "$R/build.prop.new"
cat "$R/build.prop.new" > "$BP"   # same inode: label, owner and mode kept
tail -2 "$BP"
need_grep "^$P_NAME=1\$" "$BP"
set_layer "$STEP"
