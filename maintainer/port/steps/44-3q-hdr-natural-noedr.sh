#!/bin/sh
# Phase 3q: HDR looks like Natural, no EDR brightness boost (BUGS-TODO 29; vendor + my_product).
#
# * vendor/etc/qdcm_calib_data_xiaomi_m82_{36_02_0a,42_02_0b}_*.xml: module/tools/patch_qdcm_hdr_natural.py. The SDM
#   mode standard_hdr (ColorOS HDR, render intent 257) gets the Natural processing (step 01) with a P3 matrix. Stock
#   standard_hdr made HDR whites green and warm (grey test clip, 2026-10-29). Live test on panel 42 (bind mount +
#   composer restart): no tint in the grey clip and YouTube HDR.
# * my_product/etc/permissions/oplus.product.display_features.xml: oplus.software.display.enhance_brightness_with_uidimming
#   off. That feature is ColorOS EDR. On the pipa LCD it told apps hdrSdrRatio 4.926 but raised the backlight only for
#   video (1.6x, 5530 -> 8880 of 10239): HDR photos were dim (Google Photos), the screen jumped in brightness at each
#   HDR start and end, and the slider did nothing during HDR. Without it: hdrSdrRatio NaN, photos at normal brightness,
#   no jumps, HDR video still decodes and shows as HDR (P3, 10-bit) at the user's brightness. Live test 2026-10-29
#   (bind mount + zygote restart): user confirmed both. Research: port-work/codex/edr-ratio-answer.md.
# * system_ext/etc/build.prop: ro.pipa.port.layer=3q.
set -eu
. "$PORT/lib.sh"
STEP=3q
#NEEDS: "$TOOLS/patch_qdcm_hdr_natural.py"

echo "== 29: standard_hdr = Natural + P3"
for q in qdcm_calib_data_xiaomi_m82_36_02_0a_video_mode_dual_dsi_dphy_panel.xml \
         qdcm_calib_data_xiaomi_m82_42_02_0b_video_mode_dual_dsi_dphy_panel.xml; do
    f=$T/vendor/etc/$q
    python3 -I "$TOOLS/patch_qdcm_hdr_natural.py" "$f" "$R/$q.new"
    cat "$R/$q.new" > "$f"   # same inode: owner, mode, label stay
    rm -f "$R/$q.new"
done

echo "== 29: EDR off"
replace_once system/my_product/etc/permissions/oplus.product.display_features.xml \
    '    <oplus-feature name="oplus.software.display.enhance_brightness_with_uidimming"/>\n' \
    '    <!-- pipa port 3q: EDR off (LCD) <oplus-feature name="oplus.software.display.enhance_brightness_with_uidimming"/> -->\n'

echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
set_layer "$STEP"
