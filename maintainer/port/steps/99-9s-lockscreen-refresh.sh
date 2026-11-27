#!/bin/sh
# Step 9s (BUGS 210/212, user 2026-11-27 "fix root issue"): lock screen at 144 Hz in Auto and High 120.
# OplusRefreshRatePolicyImpl.getKeyguardRefreshRateId() returns the config's maxrefreshsettings when it is not 0. The
# beta4 porter set it to 4 (144) for the 144 mode, so the keyguard always voted 144 ("keyguardShown:4" in
# dumpsys oplusscreenmode): each wake ran at 144 and each unlock animation ended with a 144 -> 120 switch.
# maxrefreshsettings must stay 4 (forceMaxRefreshRateSettings). OPPO's feature
# oplus.software.lockscreen.enable.config_refresh_rate makes the keyguard use the SystemUI NotificationShade rule
# (rateId 3-2-2-3-4) instead: 120 in Auto and High 120, 144 in "FPS Max 144 Hz" (secure mode 8).
# Live test 2026-11-27 (bind mount, peak_check off): Auto and High 120 = 120 on home, lock screen and screen off;
# FPS Max 144 = 144 everywhere; OPPO's own peak_refresh_rate, no service correction.
set -eu
. "$PORT/lib.sh"
STEP=9s
echo "== 9s lock screen refresh follows the mode"

X=$T/system/my_product/etc/extension/com.oplus.oplus-feature.xml
[ -f "$X" ] || die "$X not found"
forbid_grep '"oplus.software.lockscreen.enable.config_refresh_rate"' "$X"
replace_once "$X" '</oplus-config>' \
"	<!-- pipa port 9s: lock screen refresh follows the mode (not maxrefreshsettings 144) -->\n\t<oplus-feature name=\"oplus.software.lockscreen.enable.config_refresh_rate\"/>\n</oplus-config>"
need_grep '<oplus-feature name="oplus.software.lockscreen.enable.config_refresh_rate"/>' "$X"
python3 -I -c 'import sys, xml.dom.minidom; xml.dom.minidom.parse(sys.argv[1])' "$X" || die "XML broken"
R9=$T/system/my_product/etc/refresh_rate_config.xml
need_grep 'maxrefreshsettings="4"' "$R9"
need_grep 'package="com.android.systemui" rateId="3-2-2-3-4"' "$R9"
if grep -q 'peak_check()' "$T/system_ext/pipa_port/service.sh"; then die "service.sh still has peak_check"; fi
echo "edited  my_product/etc/extension/com.oplus.oplus-feature.xml (+1 feature)"
