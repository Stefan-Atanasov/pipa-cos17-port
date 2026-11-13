#!/bin/sh
# Step 6m (2026-11-13, offline feature audit; notes/FEATURE-AUDIT-20261113.md): M1-M6. M7 ("Never" screen timeout)
# is NOT built: user decision. Tested in the pt87 build (live resetprop was not available).
#
# Each item: a value that ColorOS code reads and the port never sets (the donor has no OPPO vendor/odm). Values come
# from the stock OnePlus Pad 3 (OPD2415) / Pad 2 Pro (OPD2413) odm/my_product files (port-work/codex/oppo-ref) or from
# the pipa hardware. All are pure framework/app code paths with no OPPO HAL (triage verdicts HIDDEN/WRONGDEFAULT, LOW).
#
# product/etc/build.prop:
#  M1 ro.vendor.oplus.market.enname=Xiaomi Pad 6   Settings/SettingsProvider device name, oplus-wifi-service P2P and
#     hotspot default name read enname first (only market.name is set, 6f).
#     live: resetprop -n ro.vendor.oplus.market.enname "Xiaomi Pad 6"; check About, Wi-Fi Direct name, new hotspot SSID.
#  M2 ro.oplus.display.screenSizeInches.primary=11.0 + screenSizeCentimeter.primary=27.94   Settings About "screen
#     size" row is empty without them (DeviceInfoUtils.getScreenPhysicSizeByProperty). Reference tablets: 13.2 / 33.53.
#     live: resetprop -n both; am force-stop com.android.settings; open About device.
#  M3 persist.oplus.fstrim.enhance=true   night f2fs trim job OplusFstrimEnhanceIdler instead of the plain idle fstrim
#     (StorageManagerService.schedulePreFstrim). All 3 reference tablets.
#     live: setprop persist.oplus.fstrim.enhance true; reboot; logcat -s OplusFstrimEnhanceIdler; dumpsys jobscheduler.
#  M4 persist.oplus.compensate.dexopt=true   job 8002: re-dexopt up to 5 packages while charging, screen off, cool
#     (OplusCompensateDexOptService.schedule -> ArtManagerLocal.dexoptPackage). All 3 reference tablets.
#     live: setprop; reboot; after a charge: logcat -s OplusCompensateDexOptService; dumpsys jobscheduler | grep 8002.
# my_product/etc/extension/com.oplus.oplus-feature.xml:
#  M5 oplus.software.touchpad_two_finger   two-finger touchpad gesture -> split screen (InputManagerServiceExtImpl ->
#     libinputflinger OPLUS_TWO_FINGER_SPLIT; SystemUI NavBarFeatureOption). All 3 reference tablets. Acts only on a
#     real touchpad (BUGS 97: the phantom "Xiaomi Touch" device sends no events). Test with a BT/USB touchpad.
#  M6 oplus.software.wlan.softap_prio_5g   a NEW default hotspot config uses 5 GHz (OplusSoftApManager
#     .generateAndSetApDefaultConfig; standard SoftApConfiguration). Pad 3. Saved configs are not changed.
# USER DECISION (not on the reference tablets):
#  M7 oplus.software.screen_off_never_support (oplus-feature.xml) + app feature com.android.settings.show_never_timeout
#     (app-features.xml)   adds "Never" to Display > Auto screen off (SettingsProvider SettingsUtils.isShowNeverTimeout,
#     Settings DisplayTimeOutController). LCD: no burn-in, but a tablet left on drains the battery.
# Feature live test (M5-M7): no resetprop for features. Bind-mount an edited copy of the XML over the ROM file in init's
# mount namespace (su -M -c), then reboot is NOT allowed (it removes the bind): restart system_server is also not
# allowed (CLAUDE.md). So: test features with a ROM build, or for app features (M7 second half) use the AppFeatureProvider
# `content insert` (CLAUDE.md "OPPO app features").
# NOT here on purpose (RISK/UNSURE, see the audit): ro.oplus.media.ovfr (refresh vs video, may fight 2o/2z: A/B first),
# ro.oplus.wifi.llm.media_boost, oplus.software.mini_window_switch_to_fullscreen, rgb_ball min/max, all tango/app32,
# dolby_vision_dpu, HDR/EDR, meta_audio/mss, OPPO Wi-Fi driver features, nandswap/osense swap.
set -eu
. "$PORT/lib.sh"
STEP=6m
echo "== 6m feature audit values (DRAFT)"

BP=$T/product/etc/build.prop
[ -f "$BP" ] || die "no $BP"
PROPS='ro.vendor.oplus.market.enname=Xiaomi Pad 6
ro.oplus.display.screenSizeInches.primary=11.0
ro.oplus.display.screenSizeCentimeter.primary=27.94
persist.oplus.fstrim.enhance=true
persist.oplus.compensate.dexopt=true'
# one effective value: none of them may exist in any build.prop of the tree
echo "$PROPS" | while IFS= read -r kv; do
    k=${kv%%=*}
    for f in $(find "$T" -maxdepth 4 -name build.prop -type f); do forbid_grep "^$k=" "$f"; done
done
{ cat "$BP"; echo "# pipa port 6m (feature audit 2026-11-13): values that OPPO sets in odm/vendor"; echo "$PROPS"; } > "$R/build.prop.6m"
cat "$R/build.prop.6m" > "$BP"; rm -f "$R/build.prop.6m"   # same inode: label, owner, mode kept
echo "$PROPS" | while IFS= read -r kv; do need_grep "^$kv\$" "$BP"; done
echo "edited  product/etc/build.prop (+5 props)"

X=$T/system/my_product/etc/extension/com.oplus.oplus-feature.xml
[ -f "$X" ] || die "$X not found"
for F in oplus.software.touchpad_two_finger oplus.software.wlan.softap_prio_5g; do
    forbid_grep "\"$F\"" "$X"
done
replace_once "$X" '</oplus-config>' \
"	<!-- pipa port 6m (feature audit 2026-11-13) -->\n\t<oplus-feature name=\"oplus.software.touchpad_two_finger\"/>\n\t<oplus-feature name=\"oplus.software.wlan.softap_prio_5g\"/>\n</oplus-config>"
need_grep '<oplus-feature name="oplus.software.wlan.softap_prio_5g"/>' "$X"
echo "edited  my_product/etc/extension/com.oplus.oplus-feature.xml (+2 features)"

set_layer "$STEP"
