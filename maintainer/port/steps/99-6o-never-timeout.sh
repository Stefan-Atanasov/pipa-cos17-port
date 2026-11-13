#!/bin/sh
# Step 6o (feature audit M7, user OK 2026-11-13 "if easy and works"): "Never" in Display > Auto screen off.
# * oplus.software.screen_off_never_support (my_product oplus-feature.xml): SettingsProvider SettingsUtils adds the
#   value 86400000 ms (24 h) to its allowed list.
# * app feature com.android.settings.show_never_timeout (my_product app-features.xml): Settings
#   DisplayTimeOutController / ExpUstUtils.getTimeOutEntryValues show the entry.
# LCD panel: no burn-in; only a tablet left on with this choice drains the battery.
set -eu
. "$PORT/lib.sh"
STEP=6o
echo "== 6o Never screen timeout"

X=$T/system/my_product/etc/extension/com.oplus.oplus-feature.xml
[ -f "$X" ] || die "$X not found"
forbid_grep '"oplus.software.screen_off_never_support"' "$X"
replace_once "$X" '</oplus-config>' \
"	<!-- pipa port 6o: Never screen timeout -->\n\t<oplus-feature name=\"oplus.software.screen_off_never_support\"/>\n</oplus-config>"
need_grep '<oplus-feature name="oplus.software.screen_off_never_support"/>' "$X"
echo "edited  my_product/etc/extension/com.oplus.oplus-feature.xml (+1 feature)"

A=$T/system/my_product/etc/extension/com.oplus.app-features.xml
FEAT=com.android.settings.show_never_timeout
[ -f "$A" ] || die "$A not found"
forbid_grep "$FEAT" "$A"
replace_once "$A" '</extend_features>' "	<app_feature name=\"$FEAT\" args=\"boolean:true\"/>\n</extend_features>"
need_grep "<app_feature name=\"$FEAT\" args=\"boolean:true\"/>" "$A"
echo "edited  my_product/etc/extension/com.oplus.app-features.xml (+ $FEAT)"
set_layer "$STEP"
