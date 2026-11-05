#!/bin/sh
# Phase 5v (beta7.1, user 2026-11-05): no "Set charging limit to 80%" pop-up after each boot.
#
# * system_ext/app/Battery: battery/patch_long_charge.py. OPPO Battery shows the pop-up (and with bit 29 it sets an 80 %
#   limit by itself) when the charger notify code has bit 28 (NOTIFY_CODE_LONG_CHARGE_LEVEL_ONE). On pipa our charger
#   shim always reports 0; the pop-up came at every boot from one bogus value. Both masks become 0 (same-size dex edit,
#   OPPO signature kept, as 4k/5t). The user's own charging limit in Settings stays.
#NEEDS: "$HERE/battery/patch_long_charge.py" "$HERE/ipe-fluid/patch_ipemanager.py"
set -eu
. "$PORT/lib.sh"
STEP=5v

B=$T/system_ext/app/Battery
[ -f "$B/Battery.apk" ] || die "Battery.apk missing: $B"
python3 -I "$HERE/battery/patch_long_charge.py" "$B/Battery.apk" "$R/Battery.patched.apk"
cat "$R/Battery.patched.apk" > "$B/Battery.apk"     # in place (cat >): owner, mode and SELinux label stay
rm -f "$R/Battery.patched.apk"
rm -rf "$B/oat"                                     # the prebuilt odex no longer matches the dex
md5sum "$B/Battery.apk"
set_layer "$STEP"
