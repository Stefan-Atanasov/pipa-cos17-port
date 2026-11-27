#!/bin/sh
# Step 9i (BUGS-TODO 200, tester request 2026-11-26, user OK): Settings > System & update > Google settings with the
# stock CN "Google Mobile Services" switch is back. ColorOS shows it only if SettingsUtils.isGoogleAccountSupport()
# (= hasSystemFeature("cn.google.services")) and the oplus feature oplus.software.disable_cn_gms are present. Step 4l
# removed cn.google.services (with it GMS treats the tablet as a China device and turns Quick Share off, BUGS 53), so
# the entry was hidden, and users who disabled Google by hand got "Turn on Google Mobile Services and try again".
# * system_ext/priv-app/Settings/Settings.apk: maintainer/cts/patch_settings_google_switch.py (1 edit in place, same
#   size: isGoogleAccountSupport returns true; platform signature block kept). 4l stays (Quick Share works with GMS on).
# * The prebuilt oat of Settings is deleted (the dex changed).
# Live test 2026-11-26 on pt167 (bind mount): entry visible; Off -> ColorOS dialog "Turn off Google Mobile Services?",
# com.google.android.gms disabled, its process stops; On -> package list as before, Quick Share opens with the account,
# its component state unchanged. Turning GMS off also turns Quick Share off (it is part of GMS): expected.
#NEEDS: "$HERE/cts/patch_settings_google_switch.py" "$HERE/jar-edits/venv/bin/python"
set -eu
. "$PORT/lib.sh"
STEP=9i
echo "== 9i Google Mobile Services switch in Settings"

A=$T/system_ext/priv-app/Settings/Settings.apk
[ -f "$A" ] || die "no $A"
"$HERE/jar-edits/venv/bin/python" -I "$HERE/cts/patch_settings_google_switch.py" "$A" "$R/Settings.9i.apk" 2>&1 | grep -v DEBUG
[ -s "$R/Settings.9i.apk" ] || die "patch failed"
cat "$R/Settings.9i.apk" > "$A"   # in place: owner, mode and SELinux label stay
rm -f "$R/Settings.9i.apk"
rm -rf "$T/system_ext/priv-app/Settings/oat"
set_layer "$STEP"
