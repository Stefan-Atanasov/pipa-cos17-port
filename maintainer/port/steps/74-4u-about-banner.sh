#!/bin/sh
# Phase 4u: ColorOS banner card in Settings > About device, without an update action (BUGS-TODO 61, user wish
# 2026-11-03; system_ext only).
#
# * system_ext/priv-app/Settings/Settings.apk: maintainer/aboutcard/patch_settings_otacard.py (2 edits in place in the
#   stored dex, platform signature kept). OtaUpdateController hid the card "key_ota_update" because the ROM removes
#   com.oplus.ota. Now the card shows (ColorOS logo, ro.build.version.oplusrom.display, "Version up to date"), and a
#   tap on it does nothing. Without the OTA app the update count is 0, so there is no "new version" button. Tested
#   live 2026-11-03 (bind mount): card visible, taps on the card and the button open nothing.
# * The prebuilt oat of Settings is deleted (the dex changed).
# * my_manifest/build.prop and my_product/build.prop: ro.build.version.oplusrom.display=17.0 (was "17.0 | by梦归zzz";
#   the banner and Settings > Version show this text; user wish 2026-11-03: version only, no name).
# * system_ext/etc/build.prop: ro.pipa.port.layer=4u (changed APK: early.sh clears the package cache).
#NEEDS: "$HERE/aboutcard/patch_settings_otacard.py" "$HERE/jar-edits/venv/bin/python"
set -eu
. "$PORT/lib.sh"
STEP=4u

A=$T/system_ext/priv-app/Settings/Settings.apk
[ -f "$A" ] || die "no $A"
echo "== Settings: About device banner card"
"$HERE/jar-edits/venv/bin/python" -I "$HERE/aboutcard/patch_settings_otacard.py" "$A" "$R/Settings.card.apk" 2>&1 | grep -v DEBUG
cat "$R/Settings.card.apk" > "$A"   # in place: owner, mode and SELinux label stay
rm -f "$R/Settings.card.apk"
rm -rf "$T/system_ext/priv-app/Settings/oat"
md5sum "$A"   # on the pt32 APK (C.07): 063136e614d9ba33171fd6d00ac7ef71

echo "== ro.build.version.oplusrom.display=17.0"
for f in "$T/system/my_manifest/build.prop" "$T/system/my_product/build.prop"; do
    [ -f "$f" ] || die "no $f"
    [ "$(grep -c '^ro.build.version.oplusrom.display=' "$f")" = 1 ] || die "not one oplusrom.display line in $f"
    t=$(mktemp); sed 's/^ro\.build\.version\.oplusrom\.display=.*/ro.build.version.oplusrom.display=17.0/' "$f" > "$t"
    cat "$t" > "$f"; rm -f "$t"   # in place: owner, mode and SELinux label stay
    grep -n '^ro.build.version.oplusrom.display=' "$f"
done

echo "== system_ext build.prop: ro.pipa.port.layer=$STEP"
set_layer "$STEP"
