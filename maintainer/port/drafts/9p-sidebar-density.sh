#!/bin/sh
# Step 9p (BUGS-TODO 206, user 2026-11-26 "why is Smart Sidebar huge"): Smart Sidebar at Screen resolution Low.
# SmartSideBar takes the initial density and the base display size from WindowManager and maps the base width in its
# WIDTH_DENSITY table {1080: 480, 1440: 640}. 9g Low = base width 1440 -> 640 dpi instead of 296: the sidebar was
# 2.16x too big (High = 1800: no entry, correct).
# * system/my_stock/app/SmartSideBar/SmartSideBar.apk: maintainer/sidebar/patch_sidebar_density.py (key 1440 ->
#   1441, same size, in place; signature block kept). The prebuilt oat of SmartSideBar is deleted (the dex changed).
# Live test 2026-11-26 on pt169 (bind mount + force-stop): sidebar at Low has the same size as at High.
#NEEDS: "$HERE/sidebar/patch_sidebar_density.py" "$HERE/jar-edits/venv/bin/python"
set -eu
. "$PORT/lib.sh"
STEP=9p
echo "== 9p Smart Sidebar density at Low resolution"

A=$T/system/my_stock/app/SmartSideBar/SmartSideBar.apk
[ -f "$A" ] || die "no $A"
"$HERE/jar-edits/venv/bin/python" -I "$HERE/sidebar/patch_sidebar_density.py" "$A" "$R/SmartSideBar.9p.apk" 2>&1 | grep -v DEBUG
[ -s "$R/SmartSideBar.9p.apk" ] || die "patch failed"
cat "$R/SmartSideBar.9p.apk" > "$A"   # in place: owner, mode and SELinux label stay
rm -f "$R/SmartSideBar.9p.apk"
rm -rf "$T/system/my_stock/app/SmartSideBar/oat"
set_layer "$STEP"
