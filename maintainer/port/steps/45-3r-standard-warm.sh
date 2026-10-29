#!/bin/sh
# Phase 3r: ColorOS "Standard" = Natural colours with a slightly warmer white (user wish; vendor only).
#
# Standard (display_color_mode 256) used the SDM mode hal_native: the raw panel without a PCC matrix, so sRGB content
# was stretched to the near-P3 panel (oversaturated, cool panel white).
# * vendor/etc/qdcm_calib_data_xiaomi_m82_{36_02_0a,42_02_0b}_*.xml: module/tools/patch_qdcm_standard_warm.py gives
#   hal_native the Natural PCC (step 01) times channel gains R 1.0, G 0.99, B 0.962 (saturation as Natural). The user
#   chose the values on the tablet next to an OPPO phone (live bind mount + composer restart, 2026-10-29).
# Same run (other steps take the changed sources): pipa_port service.sh pen capsule fix and nandswap log fix;
# pipa_port_rules.cil sys_admin + loop_device (nandswap_dedup swapoff was denied since 3g: duplicate 8 GB swap files
# after each zygote restart filled /data, 72 GB on 2026-10-29); PipaGameFilter matrices (3f).
# * system_ext/etc/build.prop: ro.pipa.port.layer=3r.
set -eu
. "$PORT/lib.sh"
STEP=3r
#NEEDS: "$TOOLS/patch_qdcm_standard_warm.py"

echo "== Standard = Natural, warmer white"
for q in qdcm_calib_data_xiaomi_m82_36_02_0a_video_mode_dual_dsi_dphy_panel.xml \
         qdcm_calib_data_xiaomi_m82_42_02_0b_video_mode_dual_dsi_dphy_panel.xml; do
    f=$T/vendor/etc/$q
    python3 -I "$TOOLS/patch_qdcm_standard_warm.py" "$f" "$R/$q.new"
    cat "$R/$q.new" > "$f"   # same inode: owner, mode, label stay
    rm -f "$R/$q.new"
done

echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
set_layer "$STEP"
