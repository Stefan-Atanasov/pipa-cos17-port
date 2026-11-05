#!/bin/sh
# Phase 5g: full blur at animation tier 3, and a two-state Animations tile (user 2026-11-04: tier 3 with blur and
# contour glow; tile with only a slow ColorOS state and a fast state).
#
# ColorOS turns blur off at tier 3 in two places. This step turns it on again for both:
# * SystemUI (ScrimUtil) reads its blur level once at start, from debug.systemui.gaussblur_level or else from
#   persist.sys.oplus.anim_level. At level 3 or more the Quick Settings background has no blur. system_ext
#   build.prop: debug.systemui.gaussblur_level=2 (full Quick Settings and shade blur at every tier, no reboot needed
#   when the tier changes).
# * OplusLauncher: BlurUtils.isMaterialBlurJumpSupported() is true only at tier 1 or 2, or when the app feature
#   com.oplus.blur.support_upgrade_anim_material_blur is set. Without it the dock, the folders and the search bar have
#   no blur at tier 3. my_product/etc/extension/com.oplus.app-features.xml gets that feature (a config line, no code
#   edit). Live test 2026-11-04: row inserted in the AppFeatureProvider table + launcher restart -> dock and folders
#   frosted with the contour glow edge.
# * pipa helper 0.9: the Quick Settings tile "Animations" has two states, Fast (tier 3, default) and ColorOS (tier 1).
#   pipa_port restarts the launcher when the tier changes (anim_check); SystemUI keeps its blur level.
#NEEDS: "$HERE/../helper/out/PipaHelper.apk"
set -eu
. "$PORT/lib.sh"
STEP=5g

FEAT=com.oplus.blur.support_upgrade_anim_material_blur
X=$T/system/my_product/etc/extension/com.oplus.app-features.xml
[ -f "$X" ] || die "$X not found"
forbid_grep "$FEAT" "$X"
replace_once "$X" '</extend_features>' \
"	<app_feature name=\"$FEAT\" args=\"boolean:true\"/>\n</extend_features>"
need_grep "<app_feature name=\"$FEAT\" args=\"boolean:true\"/>" "$X"
echo "edited  system/my_product/etc/extension/com.oplus.app-features.xml (+ $FEAT)"

BP=$T/system_ext/etc/build.prop
forbid_grep '^debug.systemui.gaussblur_level=' "$BP"
{ cat "$BP"; printf '\n# pipa port 5g: SystemUI blur level 2 at every animation tier (ColorOS has no QS blur at tier 3)\ndebug.systemui.gaussblur_level=2\n'; } > "$R/build.prop.5g"
cat "$R/build.prop.5g" > "$BP"; rm -f "$R/build.prop.5g"   # same inode
need_grep '^debug.systemui.gaussblur_level=2$' "$BP"
echo "edited  system_ext/etc/build.prop (debug.systemui.gaussblur_level=2)"

APK=$HERE/../helper/out/PipaHelper.apk
python3 -I - "$APK" <<'PY'
import sys, zipfile
d = zipfile.ZipFile(sys.argv[1]).read("classes.dex")
assert b"CircleSearchActivity" in d, "PipaHelper.apk: no CircleSearchActivity (older than 0.8)"
# 0.9: the tile subtitles are Fast / ColorOS; 0.6-0.8 also had Smooth, Parallel and Light
assert b"Fast" in d and b"Parallel" not in d, "PipaHelper.apk: not 0.9 (two-state Animations tile)"
PY
S=$T/system
cat "$APK" > "$S/system/priv-app/PipaHelper/PipaHelper.apk"   # in place: owner, mode and label stay
rm -rf "$S/system/priv-app/PipaHelper/oat"
md5sum "$S/system/priv-app/PipaHelper/PipaHelper.apk"

set_layer "$STEP"
