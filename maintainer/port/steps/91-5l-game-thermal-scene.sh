#!/bin/sh
# Phase 5l: Xiaomi's game thermal profile while a game is in the foreground (user 2026-11-04).
#
# mi_thermald selects its profile by /sys/class/thermal/thermal_message/sconfig. On HyperOS PowerKeeper sets the
# scene; on ColorOS nothing does: sconfig stayed -1 (daily profile: CPU caps from 38 C skin, also in games).
# Measured profile map (HISTORY 2026-11-04 23:15): 20 = no CPU caps below 46 C skin, 13 = below 48 C, 10 = below 51 C.
# * pipa helper 1.0 GameKeeper: ActivityManager.addOnUidImportanceListener (no polling); an app with
#   appCategory "game" in the foreground -> global pipa_game_fg = 1, else 0. PACKAGE_USAGE_STATS in the privapp file.
# * pipa_port service.sh game_check: on a settings change writes sconfig GAME_THERMAL_SCENE (config.prop, default
#   20; 0 = off) or -1; the daily profile when the screen turns off.
# * rules_5l_system_ext.cil: pipa_port may write sysfs_thermal. rules_5l_vendor.cil: dontaudit for the time service
#   prop read (walt-r16 boot). secilc on the tablet exit 0, neverallow: the same 76.
#NEEDS: "$HERE/../helper/out/PipaHelper.apk" "$ROM/pipa_port/service.sh" "$ROM/pipa_port/config.prop" "$HERE/sepolicy/rules_5l_system_ext.cil" "$HERE/sepolicy/rules_5l_vendor.cil"
set -eu
. "$PORT/lib.sh"
STEP=5l

APK=$HERE/../helper/out/PipaHelper.apk
python3 -I - "$APK" <<'PY'
import sys, zipfile
d = zipfile.ZipFile(sys.argv[1]).read("classes.dex")
assert b"pipa_game_fg" in d and b"Fast" in d, "PipaHelper.apk: not 1.0 (GameKeeper + two-state tile)"
PY
S=$T/system
cat "$APK" > "$S/system/priv-app/PipaHelper/PipaHelper.apk"   # in place: owner, mode and label stay
rm -rf "$S/system/priv-app/PipaHelper/oat"
X=$S/system/etc/permissions/privapp-permissions-pipa-helper.xml
replace_once "$X" '        <permission name="android.permission.ACCESS_CONTEXTUAL_SEARCH" />\n' \
'        <permission name="android.permission.ACCESS_CONTEXTUAL_SEARCH" />\n        <permission name="android.permission.PACKAGE_USAGE_STATS" />\n'

SE=$T/system_ext
for f in service.sh config.prop; do cat "$ROM/pipa_port/$f" > "$SE/pipa_port/$f"; echo "updated system_ext/pipa_port/$f"; done
need_grep 'game_check' "$SE/pipa_port/service.sh"
need_grep '^GAME_THERMAL_SCENE=20' "$SE/pipa_port/config.prop"

for f in system_ext_sepolicy.cil system_ext_sepolicy_debug.cil; do
    [ -f "$SE/etc/selinux/$f" ] || continue
    forbid_grep "pipa port 5l" "$SE/etc/selinux/$f"
    { cat "$SE/etc/selinux/$f"; cat "$HERE/sepolicy/rules_5l_system_ext.cil"; } > "$R/$f.new"
    cat "$R/$f.new" > "$SE/etc/selinux/$f"; rm -f "$R/$f.new"
    echo "edited  system_ext/etc/selinux/$f"
done
need_grep "pipa port 5l" "$SE/etc/selinux/system_ext_sepolicy.cil"
CIL=$T/vendor/etc/selinux/vendor_sepolicy.cil
forbid_grep "pipa port 5l" "$CIL"
{ cat "$CIL"; cat "$HERE/sepolicy/rules_5l_vendor.cil"; } > "$R/vendor_sepolicy.cil.new"
cat "$R/vendor_sepolicy.cil.new" > "$CIL"; rm -f "$R/vendor_sepolicy.cil.new"
echo "edited  vendor/etc/selinux/vendor_sepolicy.cil"

set_layer "$STEP"
