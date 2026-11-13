#!/bin/sh
# Step 6n (BUGS-TODO 98, user decision 2026-11-13): hide Settings > System navigation > "Digital assistant from
# Google" (corner swipe). The swipe cannot work on the port: SystemUI NavBarUtils.isAssistantAvailable() is false on
# CN builds and when Circle to Search is supported (stock export ColorOS also turns it off then), and the default
# assistant is the pipa helper for Circle to Search (4g). Circle to Search (gesture-bar long press) stays.
# * system_ext/priv-app/Settings/Settings.apk: maintainer/cts/patch_settings_corner_assist.py (1 edit in place, same
#   size: the Google corner-swipe switch is removed like the Yandex one; platform signature block kept).
# * The prebuilt oat of Settings is deleted (the dex changed). Live test 2026-11-13 on pt87 (bind mount): switch gone,
#   Circle to Search switch still there.
#NEEDS: "$HERE/cts/patch_settings_corner_assist.py" "$HERE/jar-edits/venv/bin/python"
set -eu
. "$PORT/lib.sh"
STEP=6n
echo "== 6n hide the corner-swipe assistant switch"

A=$T/system_ext/priv-app/Settings/Settings.apk
[ -f "$A" ] || die "no $A"
"$HERE/jar-edits/venv/bin/python" -I "$HERE/cts/patch_settings_corner_assist.py" "$A" "$R/Settings.6n.apk" 2>&1 | grep -v DEBUG
cat "$R/Settings.6n.apk" > "$A"   # in place: owner, mode and SELinux label stay
rm -f "$R/Settings.6n.apk"
rm -rf "$T/system_ext/priv-app/Settings/oat"
set_layer "$STEP"
