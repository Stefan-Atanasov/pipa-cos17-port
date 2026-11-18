#!/bin/sh
# Phase 7o: Live Clock (photo frame clock) styles for a non-OPPO tablet (BUGS 107, 2026-11-18).
#
# * Wallpapers AssetsUtil picks the styles dir by project: OPPO Pad lvy (ro.separate.soft 25928/25929/25979) ->
#   inspiration_theme_styles_lvy, a 1920x1200 pad -> _Fiji, any other tablet -> _sw600dp. Stock OPPO init sets
#   ro.separate.soft from /proc/oplusVersion; our Xiaomi kernel has none, so the app uses _sw600dp, which no ROM
#   ships: "File does not exist ... styles_sw600dp/photo_frame/style_config.json", Live Clock does not apply.
# * Setting ro.separate.soft=25928 fixed Live Clock live, but the launcher then used the OPPO Pad layout (large,
#   broken portrait home screen; test 2026-11-18). So no prop: this step copies the donor pad's own _lvy styles
#   (2.8 MB, the stock files for this screen class) to _sw600dp in my_product.
set -eu
. "$PORT/lib.sh"
STEP=7o
D=$T/system/my_product/decouping_wallpaper/styles
[ -f "$D/inspiration_theme_styles_lvy/photo_frame/style_config.json" ] || die "no _lvy photo_frame style_config.json"
[ -e "$D/inspiration_theme_styles_sw600dp" ] && die "_sw600dp exists already"
cp -a "$D/inspiration_theme_styles_lvy" "$D/inspiration_theme_styles_sw600dp"   # keeps owner, mode, SELinux label
L=$(getfattr --only-values -n security.selinux "$D/inspiration_theme_styles_sw600dp/photo_frame/style_config.json" 2>/dev/null | tr -d '\0')
[ "$L" = "u:object_r:system_file:s0" ] || die "label on the copy: '$L'"
echo "my_product: decouping_wallpaper styles _lvy -> _sw600dp ($(find "$D/inspiration_theme_styles_sw600dp" -type f | wc -l) files, $L)"
set_layer "$STEP"
