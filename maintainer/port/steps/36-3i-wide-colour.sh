#!/bin/sh
# Phase 3i: wide colour like on HyperOS (BUGS-TODO 29: YouTube HDR), on top of 3h (product only).
#
# YouTube offers HDR only with a VP9 Profile2HDR decoder (3h) and Configuration.isScreenWideColorGamut().
# Alone, 3i made the PixelOS composer drop frames during HDR playback (screen glitches); 3j fixes that. Use 3i only
# together with 3j.
# * product/etc/build.prop: ro.surface_flinger.has_wide_color_display=true.
#
# Old layer script: build_beta5_3i.sh
set -eu
. "$PORT/lib.sh"

BP=$T/product/etc/build.prop

echo "== 29: has_wide_color_display=true (YouTube needs isScreenWideColorGamut for HDR)"
need_grep "^ro.surface_flinger.has_HDR_display=true" "$BP"
forbid_grep "^ro.surface_flinger.has_wide_color_display=" "$BP"
{ cat "$BP"; printf '%s\n' "# pipa port 3i (TEST, BUGS-TODO 29): wide colour as on HyperOS; YouTube offers HDR only with it" "ro.surface_flinger.has_wide_color_display=true"; } > "$R/build.prop.new"
cat "$R/build.prop.new" > "$BP"   # same inode: label kept
tail -2 "$BP"
