#!/bin/sh
# Phase 4g: Circle to Search from the gesture bar, last part (BUGS-TODO 49; system and system_ext).
#
# Android 17 does not start Circle to Search through the assistant session (read-only flag
# disable_starting_contextual_search_via_vims), and ColorOS CN has no ContextualSearchManager call. pipa helper 0.8
# has an ACTION_ASSIST activity that calls contextual_search.startContextualSearch(2) (ACCESS_CONTEXTUAL_SEARCH,
# privileged: privapp file below). pipa_port makes the helper the default assistant once when the Google app is
# installed (service.sh, CTS_ASSISTANT; rule role_service in pipa_port_rules.cil). Live test 2026-11-02 (binds +
# zygote restart): long press -> helper -> Google Circle to Search.
#NEEDS: "$HERE/../helper/out/PipaHelper.apk" "$ROM/pipa_port/service.sh"
set -eu
. "$PORT/lib.sh"
STEP=4g

APK=$HERE/../helper/out/PipaHelper.apk
python3 -I - "$APK" <<'PY'
import sys, zipfile
d = zipfile.ZipFile(sys.argv[1]).read("classes.dex")
assert b"CircleSearchActivity" in d, "PipaHelper.apk: not 0.8 (no CircleSearchActivity)"
PY
S=$T/system
cat "$APK" > "$S/system/priv-app/PipaHelper/PipaHelper.apk"   # in place: owner, mode and label stay
rm -rf "$S/system/priv-app/PipaHelper/oat"
X=$S/system/etc/permissions/privapp-permissions-pipa-helper.xml
replace_once "$X" '        <permission name="android.permission.WRITE_SECURE_SETTINGS" />\n' \
'        <permission name="android.permission.WRITE_SECURE_SETTINGS" />\n        <permission name="android.permission.ACCESS_CONTEXTUAL_SEARCH" />\n'
SE=$T/system_ext
cat "$ROM/pipa_port/service.sh" > "$SE/pipa_port/service.sh"
need_grep 'cts_assistant_set' "$SE/pipa_port/service.sh"
need_grep "(allow pipa_port role_service (service_manager (find)))" "$SE/etc/selinux/system_ext_sepolicy.cil"
set_layer "$STEP"
