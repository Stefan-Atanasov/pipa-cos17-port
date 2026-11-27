#!/bin/sh
# Step 9d (2026-11-25, BUGS 193): "Install update" in Pipa Helper (3.4). The helper writes global pipa_ota_payload and
# pipa_ota = 1; the pipa_port service (service.sh ota_check, copied by step 2e) runs update_engine_client, which installs
# the signed A/B payload into the other slot (key: step 9c), and reports the progress in global settings.
# SELinux (maintainer/sepolicy/rules_9d_system_ext.cil): pipa_port may find and call update_engine, update_engine may call
# back (status updates). Host secilc 2026-11-25 (otatools 16968706): exit 0, neverallow failures 76 = donor base.
# The helper may restart the tablet after the install: android.permission.REBOOT in its privapp list (as stock updaters).
#NEEDS: "$HERE/sepolicy/rules_9d_system_ext.cil"
set -eu
. "$PORT/lib.sh"
STEP=9d
SE=$T/system_ext
need_grep 'update_engine_client --update --follow' "$SE/pipa_port/service.sh"
need_grep 'ota_check$' "$SE/pipa_port/service.sh"
for f in system_ext_sepolicy.cil system_ext_sepolicy_debug.cil; do
    [ -f "$SE/etc/selinux/$f" ] || continue
    forbid_grep "pipa port 9d" "$SE/etc/selinux/$f"
    { cat "$SE/etc/selinux/$f"; cat "$HERE/sepolicy/rules_9d_system_ext.cil"; } > "$R/$f.new"
    cat "$R/$f.new" > "$SE/etc/selinux/$f"; rm -f "$R/$f.new"
    need_grep "pipa port 9d" "$SE/etc/selinux/$f"
done
X=$T/system/system/etc/permissions/privapp-permissions-pipa-helper.xml
[ -f "$X" ] || die "no $X"
if ! grep -q 'android.permission.REBOOT' "$X"; then
    replace_once "$X" '        <permission name="android.permission.WRITE_SECURE_SETTINGS" />\n' \
'        <permission name="android.permission.WRITE_SECURE_SETTINGS" />\n        <permission name="android.permission.REBOOT" />\n'
fi
need_grep 'android.permission.REBOOT' "$X"
echo "ota_check in service.sh, update_engine rules, helper REBOOT permission"
set_layer "$STEP"
