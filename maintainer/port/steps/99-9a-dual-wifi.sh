#!/bin/sh
# Step 9a (2026-11-25, BUGS 173): Dual Wi-Fi acceleration (two Wi-Fi networks at once), as on HyperOS.
# OPPO's dual STA (oplus-wifi-service OplusWifiConnect2.getDualStaConcurrencyMode) needs the feature
# oplus.software.wlan.dual_sta (DBS: one network on 2.4 GHz, one on 5 GHz); the donor does not set it. The pipa Wi-Fi
# HAL has STA + STA concurrency (dumpsys wifi: "STA + STA Concurrency Supported: true", up to 3 STA ifaces).
# The switch is in Settings > Wi-Fi > Wi-Fi Assistant > Dual Wi-Fi acceleration (default on, as on OPPO devices).
# OPPO starts the second connection only for apps in its lists (sys_wifi_par_config_list.xml): here Chrome is added
# to NETWORK_DUAL_STA_APPS_EXP and the Play Store to NETWORK_DUAL_STA_DOWNLOAD_APPS.
# Live test 2026-11-25 (pt152, bind mount + zygote restart): the switch appears; a speed test in Opera brought up
# wlan1 (ROLE_CLIENT_SECONDARY, "Dark2.4" next to "Dark5"); user: upload 480 vs 390 Mbit/s, download the same (line).
set -eu
. "$PORT/lib.sh"
STEP=9a
echo "== 9a dual Wi-Fi acceleration (BUGS 173)"
F=$T/system/my_product/etc/extension/com.oplus.oplus-feature.xml
[ -f "$F" ] || die "$F not found"
forbid_grep 'oplus.software.wlan.dual_sta"' "$F"
replace_once "$F" '	<oplus-feature name="oplus.software.wlan.softap_prio_5g"/>\n' \
    '	<oplus-feature name="oplus.software.wlan.softap_prio_5g"/>\n	<oplus-feature name="oplus.software.wlan.dual_sta"/>\n'
need_grep 'oplus.software.wlan.dual_sta"' "$F"
W=$T/system_ext/etc/sys_wifi_par_config_list.xml
[ -f "$W" ] || die "$W not found"
forbid_grep 'com.android.chrome</NETWORK_DUAL_STA_APPS_EXP>' "$W"
replace_once "$W" '</NETWORK_DUAL_STA_APPS_EXP>' ',com.android.chrome</NETWORK_DUAL_STA_APPS_EXP>'
replace_once "$W" '</NETWORK_DUAL_STA_DOWNLOAD_APPS>' ',com.android.vending</NETWORK_DUAL_STA_DOWNLOAD_APPS>'
need_grep 'com.android.chrome</NETWORK_DUAL_STA_APPS_EXP>' "$W"
need_grep 'com.android.vending</NETWORK_DUAL_STA_DOWNLOAD_APPS>' "$W"
echo "edited  my_product com.oplus.oplus-feature.xml (+ wlan.dual_sta), system_ext sys_wifi_par_config_list.xml (+ Chrome, Play Store)"
set_layer "$STEP"
