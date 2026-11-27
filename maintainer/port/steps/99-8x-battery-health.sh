#!/bin/sh
# Step 8x (2026-11-25, BUGS 176): Settings > Battery > Battery health shows "Maximum capacity".
# The Battery app (BatteryHealthFragment.T) shows the row only with the app feature
# os.charge.settings.batterysettings.batteryhealth (m6.a.e()); the donor does not set it. The value comes from
# OplusBatteryManager.getUIsohValue -> our chargershim (step 3z): charge_full * 100 / charge_full_design.
# Live test 2026-11-25 (pt151, bind mount + zygote restart): "Maximum capacity 94%" (8367000 / 8840000 uAh).
set -eu
. "$PORT/lib.sh"
STEP=8x
echo "== 8x battery health page: Maximum capacity (BUGS 176)"
A=$T/system/my_product/etc/extension/com.oplus.app-features.xml
FEAT=os.charge.settings.batterysettings.batteryhealth
[ -f "$A" ] || die "$A not found"
forbid_grep "$FEAT" "$A"
replace_once "$A" '</extend_features>' "	<app_feature name=\"$FEAT\"/>\n</extend_features>"
need_grep "<app_feature name=\"$FEAT\"/>" "$A"
echo "edited  my_product/etc/extension/com.oplus.app-features.xml (+ $FEAT)"
set_layer "$STEP"
