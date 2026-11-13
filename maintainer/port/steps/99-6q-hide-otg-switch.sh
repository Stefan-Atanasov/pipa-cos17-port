#!/bin/sh
# Step 6q (BUGS-TODO 100, user 2026-11-12 "OTG not working?"): Settings > Accessibility & convenience > OTG
# connection does nothing on pipa (2026-11-13, port-work/codex/bugs100-otg/REPORT.md): it goes through the OPPO charger
# HAL vendor.oplus.hardware.charger.ICharger (absent, oplus_absent_service), so it reads back 0 and snaps off, and the
# kernel has no otg_switch node. USB host mode follows the Type-C role and works either way. Stock mechanism for
# devices without OTG control: app feature com.android.systemui.otg_auto_close_alarm_disable hides the row
# (OtgConnectionPreferenceController.isPreferenceSupport) and stops SystemUI's 10-minute auto-close alarm (OtgHelper).
set -eu
. "$PORT/lib.sh"
STEP=6q
echo "== 6q hide the OTG connection switch"
A=$T/system/my_product/etc/extension/com.oplus.app-features.xml
FEAT=com.android.systemui.otg_auto_close_alarm_disable
[ -f "$A" ] || die "$A not found"
forbid_grep "$FEAT" "$A"
replace_once "$A" '</extend_features>' "	<app_feature name=\"$FEAT\"/>\n</extend_features>"
need_grep "<app_feature name=\"$FEAT\"/>" "$A"
echo "edited  my_product/etc/extension/com.oplus.app-features.xml (+ $FEAT)"
set_layer "$STEP"
