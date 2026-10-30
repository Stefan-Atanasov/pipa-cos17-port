#!/bin/sh
# Phase 3h: HDR video like on HyperOS (BUGS-TODO 29), on top of 3g (product only).
#
# beta4 set ro.surface_flinger.has_HDR_display=false (system and vendor build.prop; HyperOS: true). Codec2InfoBuilder
# (libsfplugin_ccodec) then hides all HDR decoder profiles (HEVC HDR10/HDR10+, VP9 HDR, AV1 HDR10), so apps never pick
# HDR streams. Tested live 2026-10-28 with resetprop: profiles back, HDR10 clip composited by the HWC as BT2020_PQ,
# HDR/SDR boost 2.25 (HyperOS value). has_wide_color_display stays false here; step 3i sets it
# to true (only together with the 3j composer patch).
# * product/etc/build.prop: ro.surface_flinger.has_HDR_display=true (product loads after system and vendor).
# * system_ext/etc/build.prop is not changed: ro.pipa.port.layer stays 3g (no system APK changed).
#
# Old layer script: build_beta5_3h.sh
set -eu
. "$PORT/lib.sh"

BP=$T/product/etc/build.prop

echo "== 29: has_HDR_display=true"
if grep -q "^ro.surface_flinger.has_HDR_display=" "$BP"; then echo "product build.prop already sets has_HDR_display"; exit 1; fi
{ cat "$BP"; printf '%s\n' "# pipa port 3h (BUGS-TODO 29): HDR decoder profiles and HDR output as on HyperOS" "ro.surface_flinger.has_HDR_display=true"; } > "$R/build.prop.new"
cat "$R/build.prop.new" > "$BP"   # same inode: label kept
tail -2 "$BP"

