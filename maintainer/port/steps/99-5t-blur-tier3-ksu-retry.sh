#!/bin/sh
# Phase 5t (user 2026-11-05, clean-flash goal): tier 3 with blur, the blur switches visible, Animations tile tier 3/2,
# SukiSU manager on a clean flash. Found on the beta7 clean flash (pt57 = beta7 + FindMyPhone back in 5f).
#
# * my_stock/priv-app/Wallpapers: wallpapers/patch_blur_entry.py. Personalization > More hides "Textured visual
#   effects" (Visual blur, Contour glow, Animation blur; page com.oplus.uxdesign BlurredTextureActivity) when
#   persist.sys.oplus.anim_level > 2. Same-size dex edit, OPPO signature kept (as 4k). The page itself has no check.
# * port-rom (step 2e copies it): service.sh first-boot defaults Visual blur + Contour glow ON
#   (system_material_blur_enable=1, system_material_stroke_enable=1; 5g measured no cost at tier 3); the SukiSU
#   manager install waits for user 0 storage and is retried every 60 s (first boot: pm install 1 s after "On user
#   unlock 0" failed, the next try was only at the next boot).
# * helper 1.1 (step 2d copies helper/out): Animations tile Fast = tier 3, Slow = tier 2 (was ColorOS = tier 1).
# New layer: early.sh clears the package parse cache (changed system APKs).
#NEEDS: "$HERE/wallpapers/patch_blur_entry.py" "$HERE/ipe-fluid/patch_ipemanager.py"
set -eu
. "$PORT/lib.sh"
STEP=5t

W=$T/system/my_stock/priv-app/Wallpapers
[ -f "$W/Wallpapers.apk" ] || die "Wallpapers.apk missing: $W"
python3 -I "$HERE/wallpapers/patch_blur_entry.py" "$W/Wallpapers.apk" "$R/Wallpapers.patched.apk"
cat "$R/Wallpapers.patched.apk" > "$W/Wallpapers.apk"    # in place (cat >): owner, mode and SELinux label stay
rm -f "$R/Wallpapers.patched.apk"
rm -rf "$W/oat"                                           # the prebuilt odex no longer matches the dex
md5sum "$W/Wallpapers.apk"

S=$T/system_ext/pipa_port/service.sh
need_grep 'system_material_stroke_enable 1' "$S"
need_grep 'ksu_manager()' "$S"
set_layer "$STEP"
